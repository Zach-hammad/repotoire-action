#!/usr/bin/env bash
set -uo pipefail

REPO_PATH="${INPUT_PATH:-.}"
FORMAT="${INPUT_FORMAT:-sarif}"
FAIL_ON="${INPUT_FAIL_ON:-}"
DIFF_ONLY="${INPUT_DIFF_ONLY:-auto}"
CONFIG="${INPUT_CONFIG:-}"
EXTRA_ARGS="${INPUT_ARGS:-}"

# Warn if shallow clone
if [ -d "$REPO_PATH/.git" ]; then
  DEPTH=$(git -C "$REPO_PATH" rev-list --count --all 2>/dev/null || echo "0")
  if [ "$DEPTH" -lt 10 ]; then
    echo "::warning::Shallow clone detected ($DEPTH commits). Use 'fetch-depth: 0' in checkout for full git analysis (churn, blame, co-change)."
  fi
fi

# `config` input is not wired to a CLI flag — `repotoire analyze`/`diff` have no --config;
# repotoire auto-detects repotoire.toml in the analyzed path.
if [ -n "$CONFIG" ]; then
  echo "::warning::The 'config' input is not supported by the repotoire CLI (no --config flag); repotoire auto-detects repotoire.toml in '$REPO_PATH'. Ignoring config='$CONFIG'."
fi

# Output paths
OUTPUT_DIR="${RUNNER_TEMP:-/tmp}/repotoire-results"
mkdir -p "$OUTPUT_DIR"
SARIF_FILE="$OUTPUT_DIR/results.sarif.json"
JSON_FILE="$OUTPUT_DIR/results.json"
if [ "$FORMAT" = "json" ]; then
  PRIMARY_FILE="$JSON_FILE"
else
  PRIMARY_FILE="$SARIF_FILE"
fi

# Resolve mode: diff (on PRs) or full analysis
if [ "$DIFF_ONLY" = "auto" ]; then
  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] || [ "${GITHUB_EVENT_NAME:-}" = "pull_request_target" ]; then
    DIFF_ONLY="true"
  else
    DIFF_ONLY="false"
  fi
fi

MODE="analyze"
BASE_SHA=""
if [ "$DIFF_ONLY" = "true" ] && [ -n "${GITHUB_EVENT_PATH:-}" ]; then
  BASE_SHA=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
  if [ -n "$BASE_SHA" ]; then
    MODE="diff"
  else
    echo "::warning::Could not determine the PR base SHA — falling back to a full analysis."
  fi
fi

# Whether the installed repotoire supports `analyze --json-sidecar` (avoids a 2nd pass).
HAS_SIDECAR=false
if repotoire analyze --help 2>&1 | grep -q "json-sidecar"; then HAS_SIDECAR=true; fi

# run_repotoire <mode> <format> <output-file> <apply-fail-on:1|0>
#   diff:    `repotoire diff <base> <path> --format … --output … [--fail-on …]`   (path is positional;
#            diff accepts NEITHER --per-page NOR --json-sidecar — those are analyze-only)
#   analyze: `repotoire analyze <path> --format … --output … --per-page 0 [--json-sidecar JSON_FILE] [--fail-on …]`
# Sets REPO_OUT to the combined stdout+stderr; returns repotoire's exit code.
run_repotoire() {
  local mode="$1" fmt="$2" out="$3" applyfo="$4"
  local args=()
  if [ "$mode" = "diff" ]; then
    args=(diff "$BASE_SHA" "$REPO_PATH" --format "$fmt" --output "$out")
  else
    args=(analyze "$REPO_PATH" --format "$fmt" --output "$out" --per-page 0)
    if [ "$HAS_SIDECAR" = "true" ] && [ "$fmt" != "json" ] && [ "$out" != "$JSON_FILE" ]; then
      args+=(--json-sidecar "$JSON_FILE")
    fi
  fi
  if [ "$applyfo" = "1" ] && [ -n "$FAIL_ON" ]; then args+=(--fail-on "$FAIL_ON"); fi
  if [ -n "$EXTRA_ARGS" ]; then
    # shellcheck disable=SC2206
    args+=($EXTRA_ARGS)
  fi
  echo "Command: repotoire ${args[*]}"
  local rc=0
  REPO_OUT="$(repotoire "${args[@]}" 2>&1)" || rc=$?
  [ -n "$REPO_OUT" ] && printf '%s\n' "$REPO_OUT"
  return $rc
}

is_fail_on_failure() {  # $1 = repotoire output
  [ -n "$FAIL_ON" ] && printf '%s' "$1" | grep -q "Failing due to --fail-on"
}

echo "::group::Repotoire Analysis"
echo "Mode: $MODE${BASE_SHA:+ (base $BASE_SHA)}"

REPO_OUT=""
EXIT_CODE=0
run_repotoire "$MODE" "$FORMAT" "$PRIMARY_FILE" 1 || EXIT_CODE=$?
PRIMARY_OUT="$REPO_OUT"

FELL_BACK=false
if [ "$EXIT_CODE" -ne 0 ] && [ "$MODE" = "diff" ] && ! is_fail_on_failure "$PRIMARY_OUT"; then
  # diff mode failed for a non-fail-on reason (path isn't a git repo, base unresolvable, …) —
  # degrade to a full `repotoire analyze` (the gate is NOT applied to the fallback).
  echo "::warning::repotoire diff mode failed (exit $EXIT_CODE) — falling back to a full \`repotoire analyze\` of '$REPO_PATH'. The --fail-on gate is not applied to this fallback run."
  MODE="analyze"
  EXIT_CODE=0
  run_repotoire analyze "$FORMAT" "$PRIMARY_FILE" 0 || EXIT_CODE=$?
  PRIMARY_OUT="$REPO_OUT"
  FELL_BACK=true
fi

# Ensure a JSON results file exists for the outputs/comment steps.
if [ ! -f "$JSON_FILE" ]; then
  if [ "$FORMAT" = "json" ] && [ -f "$PRIMARY_FILE" ] && [ "$PRIMARY_FILE" != "$JSON_FILE" ]; then
    cp "$PRIMARY_FILE" "$JSON_FILE" 2>/dev/null || true
  else
    echo "Producing JSON results (secondary pass)..."
    run_repotoire "$MODE" json "$JSON_FILE" 0 >/dev/null 2>&1 || true
  fi
fi

echo "::endgroup::"

echo "sarif-file=$SARIF_FILE" >> "$GITHUB_OUTPUT"
echo "json-file=$JSON_FILE" >> "$GITHUB_OUTPUT"
echo "exit-code=$EXIT_CODE" >> "$GITHUB_OUTPUT"

# Exit semantics: 0 = pass; 1+ with the fail-on tell-tale = --fail-on threshold triggered (intended
# failure); other nonzero = repotoire CLI error — surface clearly, NOT as a findings failure.
if [ "$EXIT_CODE" -eq 0 ]; then
  if [ "$FELL_BACK" = "true" ]; then echo "Repotoire full-mode fallback completed."; else echo "Repotoire analysis passed."; fi
elif is_fail_on_failure "$PRIMARY_OUT"; then
  echo "::error::Repotoire: new findings at or above '$FAIL_ON' severity."
  exit 1
else
  echo "::error::Repotoire CLI failed (exit code $EXIT_CODE) — see the analysis output above. This is a tool/usage error, not a findings failure."
  exit "$EXIT_CODE"
fi
