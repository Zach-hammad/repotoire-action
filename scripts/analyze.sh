#!/usr/bin/env bash
set -euo pipefail

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
    echo "::warning::Could not determine the PR base SHA — falling back to full analysis."
  fi
fi

# `repotoire diff` takes [PATH] positionally and accepts neither --per-page nor --json-sidecar
# (those are `analyze`-only). Build the command per-mode accordingly.
PRIMARY_ARGS=()
if [ "$MODE" = "diff" ]; then
  PRIMARY_ARGS=(diff "$BASE_SHA" "$REPO_PATH" --format "$FORMAT" --output "$PRIMARY_FILE")
else
  PRIMARY_ARGS=(analyze "$REPO_PATH" --format "$FORMAT" --output "$PRIMARY_FILE" --per-page 0)
fi
[ -n "$FAIL_ON" ] && PRIMARY_ARGS+=(--fail-on "$FAIL_ON")

# Get a JSON sidecar alongside non-JSON output (analyze only; diff has no --json-sidecar).
USE_SIDECAR=false
if [ "$MODE" = "analyze" ] && [ "$FORMAT" != "json" ] && repotoire analyze --help 2>&1 | grep -q "json-sidecar"; then
  USE_SIDECAR=true
  PRIMARY_ARGS+=(--json-sidecar "$JSON_FILE")
fi

# Extra args (documented as "passed to repotoire analyze"; word-split intentionally)
if [ -n "$EXTRA_ARGS" ]; then
  # shellcheck disable=SC2206
  PRIMARY_ARGS+=($EXTRA_ARGS)
fi

echo "::group::Repotoire Analysis"
echo "Mode: $MODE${BASE_SHA:+ (base $BASE_SHA)}"
echo "Command: repotoire ${PRIMARY_ARGS[*]}"

EXIT_CODE=0
repotoire "${PRIMARY_ARGS[@]}" || EXIT_CODE=$?

# Ensure a JSON results file exists for the outputs/comment steps.
if [ ! -f "$JSON_FILE" ]; then
  if [ "$FORMAT" = "json" ] && [ -f "$PRIMARY_FILE" ] && [ "$PRIMARY_FILE" != "$JSON_FILE" ]; then
    cp "$PRIMARY_FILE" "$JSON_FILE" 2>/dev/null || true
  elif [ "$USE_SIDECAR" = "false" ]; then
    echo "Producing JSON results (secondary pass)..."
    if [ "$MODE" = "diff" ]; then
      repotoire diff "$BASE_SHA" "$REPO_PATH" --format json --output "$JSON_FILE" >/dev/null 2>&1 || true
    else
      repotoire analyze "$REPO_PATH" --format json --output "$JSON_FILE" --per-page 0 >/dev/null 2>&1 || true
    fi
  fi
fi

echo "::endgroup::"

echo "sarif-file=$SARIF_FILE" >> "$GITHUB_OUTPUT"
echo "json-file=$JSON_FILE" >> "$GITHUB_OUTPUT"
echo "exit-code=$EXIT_CODE" >> "$GITHUB_OUTPUT"

# Exit semantics: 0 = pass; 1 = --fail-on threshold triggered (intended failure);
# >=2 = repotoire CLI error (bad args, panic, etc.) — surface clearly, do NOT call it a findings failure.
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "Repotoire analysis passed."
elif [ "$EXIT_CODE" -eq 1 ] && [ -n "$FAIL_ON" ]; then
  echo "::error::Repotoire: new findings at or above '$FAIL_ON' severity."
  exit 1
else
  echo "::error::Repotoire CLI failed (exit code $EXIT_CODE) — see the analysis output above. This is a tool/usage error, not a findings failure."
  exit "$EXIT_CODE"
fi
