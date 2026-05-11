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

# --- Read results (handle both analyze-JSON and diff-JSON shapes) ---
JSON_FILE="${RUNNER_TEMP:-/tmp}/repotoire-results/results.json"
if [ ! -f "$JSON_FILE" ]; then
  echo "::warning::No JSON results file — skipping PR comment"
  exit 0
fi

# analyze JSON: { overall_score, grade, findings: [{severity, title, affected_files, line_start}] }
# diff JSON:    { score_after, total_new_findings, new_findings: [{severity, title, description, file, line, attribution}] }  (no grade)
_JQ_OUT=$(jq -r '
  (if has("new_findings") then .new_findings else (.findings // []) end) as $f
  | [ (.overall_score // .score_after // 0),
      (.grade // "-"),
      ($f | length),
      ([$f[] | select((.severity // "" | ascii_downcase) == "critical")] | length),
      ([$f[] | select((.severity // "" | ascii_downcase) == "high")] | length),
      (if has("new_findings") then "diff" else "full" end) ]
  | @tsv' "$JSON_FILE" 2>/dev/null || true)
[ -n "$_JQ_OUT" ] || _JQ_OUT=$'0\t-\t0\t0\t0\tfull'
IFS=$'\t' read -r SCORE GRADE TOTAL CRITICAL HIGH IS_DIFF <<< "$_JQ_OUT"
SCORE=$(printf "%.1f" "$SCORE" 2>/dev/null || echo "$SCORE")

# --- Build file link base ---
HEAD_SHA="${INPUT_HEAD_SHA:-${GITHUB_SHA:-HEAD}}"
LINK_BASE="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/blob/${HEAD_SHA}"

# --- Extract top 5 findings ---
FINDINGS_TABLE=$(jq -r --arg base "$LINK_BASE" '
  def sev_order: {"critical":0,"high":1,"medium":2,"low":3,"info":4}[. | ascii_downcase] // 5;
  def escape_md: tostring | gsub("\\|"; "\\|") | gsub("`"; "") | gsub("\n"; " ");
  def clean_path: tostring | ltrimstr("./");
  (if has("new_findings") then .new_findings else (.findings // []) end)
  | [ .[]
      | {
          severity: (.severity // "?"),
          title: ((.title // .description // "") | escape_md),
          file: (((.file // (.affected_files? // [null] | .[0])) // null) | if . then clean_path else null end),
          line: (.line // .line_start)
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
if [ "$IS_DIFF" = "diff" ]; then
  FINDINGS_SUMMARY="Top new findings"
  HEADER="| Score | New findings | Critical | High |"
  SEP="|-------|--------------|----------|------|"
  ROW="| ${SCORE} | ${TOTAL} | ${CRITICAL} | ${HIGH} |"
  EMPTY_MSG="No new findings introduced by this PR's changes."
else
  FINDINGS_SUMMARY="Top findings"
  HEADER="| Score | Grade | Findings | Critical | High |"
  SEP="|-------|-------|----------|----------|------|"
  ROW="| ${SCORE} | ${GRADE} | ${TOTAL} | ${CRITICAL} | ${HIGH} |"
  EMPTY_MSG="No findings detected."
fi

cat > "$BODY_FILE" << MDEOF
<!-- repotoire-comment -->
### Repotoire Analysis

${HEADER}
${SEP}
${ROW}
MDEOF

if [ "$TOTAL" -gt 0 ] && [ -n "$FINDINGS_TABLE" ]; then
  DISPLAY_COUNT=$(echo "$FINDINGS_TABLE" | wc -l | tr -d ' ')
  cat >> "$BODY_FILE" << MDEOF

<details>
<summary>${FINDINGS_SUMMARY} (${DISPLAY_COUNT})</summary>

| Severity | File | Finding |
|----------|------|---------|
${FINDINGS_TABLE}

</details>
MDEOF
elif [ "$TOTAL" -eq 0 ]; then
  printf '\n%s\n' "$EMPTY_MSG" >> "$BODY_FILE"
fi

# --- Find existing comment ---
COMMENT_ID=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
  --paginate \
  --jq '.[] | select(.body | contains("<!-- repotoire-comment -->")) | .id' \
  2>/dev/null | head -1 || true)
case "$COMMENT_ID" in ''|*[!0-9]*) COMMENT_ID="" ;; esac  # only a numeric comment id; ignore error bodies

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
