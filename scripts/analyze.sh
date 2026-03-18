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

# Build output paths
OUTPUT_DIR="${RUNNER_TEMP:-/tmp}/repotoire-results"
mkdir -p "$OUTPUT_DIR"
SARIF_FILE="$OUTPUT_DIR/results.sarif.json"
JSON_FILE="$OUTPUT_DIR/results.json"

# Determine output file based on format
if [ "$FORMAT" = "json" ]; then
  OUTPUT_FILE="$JSON_FILE"
else
  OUTPUT_FILE="$SARIF_FILE"
fi

# Build command
CMD_ARGS=()

# Determine mode: diff or full analysis
if [ "$DIFF_ONLY" = "auto" ]; then
  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] || [ "${GITHUB_EVENT_NAME:-}" = "pull_request_target" ]; then
    DIFF_ONLY="true"
  else
    DIFF_ONLY="false"
  fi
fi

if [ "$DIFF_ONLY" = "true" ] && [ -n "${GITHUB_EVENT_PATH:-}" ]; then
  BASE_SHA=$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
  if [ -n "$BASE_SHA" ]; then
    echo "Running diff analysis against base: $BASE_SHA"
    CMD_ARGS+=(diff "$BASE_SHA" --path "$REPO_PATH")
    CMD_ARGS+=(--format "$FORMAT" --output "$OUTPUT_FILE")
  else
    echo "::warning::Could not determine base SHA for diff. Falling back to full analysis."
    CMD_ARGS+=(analyze "$REPO_PATH" --format "$FORMAT" --output "$OUTPUT_FILE")
  fi
else
  CMD_ARGS+=(analyze "$REPO_PATH" --format "$FORMAT" --output "$OUTPUT_FILE")
fi

# Add fail-on if specified
if [ -n "$FAIL_ON" ]; then
  CMD_ARGS+=(--fail-on "$FAIL_ON")
fi

# Add config if specified
if [ -n "$CONFIG" ]; then
  CMD_ARGS+=(--config "$CONFIG")
fi

# Add per-page 0 for full output in structured formats
if [ "$FORMAT" = "sarif" ] || [ "$FORMAT" = "json" ]; then
  CMD_ARGS+=(--per-page 0)
fi

# Try --json-sidecar if available (v0.3.114+), fall back to second run
HAS_SIDECAR=false
if repotoire analyze --help 2>&1 | grep -q "json-sidecar"; then
  HAS_SIDECAR=true
  if [ "$FORMAT" != "json" ]; then
    CMD_ARGS+=(--json-sidecar "$JSON_FILE")
  fi
fi

# Add extra args (word-split intentionally)
if [ -n "$EXTRA_ARGS" ]; then
  # shellcheck disable=SC2206
  CMD_ARGS+=($EXTRA_ARGS)
fi

echo "::group::Repotoire Analysis"
echo "Command: repotoire ${CMD_ARGS[*]}"

# Run primary analysis
EXIT_CODE=0
repotoire "${CMD_ARGS[@]}" || EXIT_CODE=$?

# If no sidecar support and format isn't json, run a second pass for JSON outputs
if [ "$HAS_SIDECAR" = "false" ] && [ "$FORMAT" != "json" ]; then
  echo "Running secondary JSON pass for outputs..."
  repotoire analyze "$REPO_PATH" --format json --output "$JSON_FILE" --per-page 0 2>/dev/null || true
fi

echo "::endgroup::"

# Set outputs
echo "sarif-file=$SARIF_FILE" >> "$GITHUB_OUTPUT"
echo "json-file=$JSON_FILE" >> "$GITHUB_OUTPUT"
echo "exit-code=$EXIT_CODE" >> "$GITHUB_OUTPUT"

# Fail the step if fail-on was triggered
if [ -n "$FAIL_ON" ] && [ "$EXIT_CODE" -ne 0 ]; then
  echo "::error::Repotoire found findings at or above '$FAIL_ON' severity (exit code $EXIT_CODE)"
  exit "$EXIT_CODE"
fi
