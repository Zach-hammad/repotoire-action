#!/usr/bin/env bash
set -euo pipefail

# --- Gate checks ---
if [ "${INPUT_COMMENT:-}" != "true" ]; then
  echo "PR comment disabled (comment=$INPUT_COMMENT)"
  exit 0
fi

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ] && [ "${GITHUB_EVENT_NAME:-}" != "pull_request_target" ]; then
  echo "Not a PR event (event=$GITHUB_EVENT_NAME) — skipping comment"
  exit 0
fi

# --- Read PR number ---
PR_NUMBER=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
if [ -z "$PR_NUMBER" ]; then
  echo "::warning::Could not read PR number from event payload — skipping comment"
  exit 0
fi

# --- Read results ---
JSON_FILE="${RUNNER_TEMP:-/tmp}/repotoire-results/results.json"
if [ ! -f "$JSON_FILE" ]; then
  echo "::warning::No JSON results file — skipping PR comment"
  exit 0
fi

SCORE=$(jq -r '.overall_score // 0' "$JSON_FILE")
GRADE=$(jq -r '.grade // "?"' "$JSON_FILE")
TOTAL=$(jq -r '.findings | length' "$JSON_FILE")
CRITICAL=$(jq -r '[.findings[] | select(.severity == "critical")] | length' "$JSON_FILE")
HIGH=$(jq -r '[.findings[] | select(.severity == "high")] | length' "$JSON_FILE")

SCORE=$(printf "%.1f" "$SCORE")

# --- Build file link base ---
HEAD_SHA="${INPUT_HEAD_SHA:-${GITHUB_SHA:-HEAD}}"
LINK_BASE="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/blob/${HEAD_SHA}"

# --- Extract top 5 findings ---
FINDINGS_TABLE=$(jq -r --arg base "$LINK_BASE" '
  def sev_order: {"critical":0,"high":1,"medium":2,"low":3,"info":4}[.] // 5;
  def escape_md: gsub("\\|"; "\\|") | gsub("`"; "");
  def clean_path: ltrimstr("./");
  [.findings[]
    | {
        severity,
        title: (.title | escape_md),
        file: ((.affected_files[0] // null) | if . then clean_path else null end),
        line: .line_start
      }
  ]
  | sort_by(.severity | sev_order)
  | .[0:5]
  | .[]
  | if .file then
      if .line then
        "| \(.severity) | [`\(.file):\(.line)`](\($base)/\(.file)#L\(.line)) | \(.title) |"
      else
        "| \(.severity) | `\(.file)` | \(.title) |"
      end
    else
      "| \(.severity) | | \(.title) |"
    end
' "$JSON_FILE" 2>/dev/null || true)

# --- Build comment body ---
BODY_FILE=$(mktemp)

cat > "$BODY_FILE" << MDEOF
<!-- repotoire-comment -->
### Repotoire Analysis

| Score | Grade | Findings | Critical | High |
|-------|-------|----------|----------|------|
| ${SCORE} | ${GRADE} | ${TOTAL} | ${CRITICAL} | ${HIGH} |
MDEOF

if [ "$TOTAL" -gt 0 ] && [ -n "$FINDINGS_TABLE" ]; then
  DISPLAY_COUNT=$(echo "$FINDINGS_TABLE" | wc -l)
  cat >> "$BODY_FILE" << MDEOF

<details>
<summary>Top findings (${DISPLAY_COUNT})</summary>

| Severity | File | Finding |
|----------|------|---------|
${FINDINGS_TABLE}

</details>
MDEOF
elif [ "$TOTAL" -eq 0 ]; then
  echo "" >> "$BODY_FILE"
  echo "No findings detected." >> "$BODY_FILE"
fi

# --- Find existing comment ---
COMMENT_ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
  --paginate \
  --jq '.[] | select(.body | contains("<!-- repotoire-comment -->")) | .id' \
  2>/dev/null | head -1 || true)

# --- Create or update ---
if [ -n "$COMMENT_ID" ]; then
  echo "Updating existing comment $COMMENT_ID"
  jq -Rs '{body: .}' "$BODY_FILE" | \
    gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${COMMENT_ID}" \
      --method PATCH \
      --input - \
      > /dev/null 2>&1 \
    || echo "::warning::Failed to update PR comment (check pull-requests: write permission)"
else
  echo "Creating new comment on PR #${PR_NUMBER}"
  jq -Rs '{body: .}' "$BODY_FILE" | \
    gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
      --method POST \
      --input - \
      > /dev/null 2>&1 \
    || echo "::warning::Failed to create PR comment (check pull-requests: write permission)"
fi

rm -f "$BODY_FILE"
echo "PR comment done"
