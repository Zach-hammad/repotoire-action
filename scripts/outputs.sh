#!/usr/bin/env bash
set -euo pipefail

JSON_FILE="${RUNNER_TEMP:-/tmp}/repotoire-results/results.json"

if [ ! -f "$JSON_FILE" ]; then
  echo "::warning::No JSON results file found at $JSON_FILE — skipping output parsing"
  echo "score=0" >> "$GITHUB_OUTPUT"
  echo "grade=?" >> "$GITHUB_OUTPUT"
  echo "findings-count=0" >> "$GITHUB_OUTPUT"
  echo "critical-count=0" >> "$GITHUB_OUTPUT"
  echo "high-count=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Handle both shapes:
#   analyze JSON -> { overall_score, grade, findings: [{severity,...}], ... }
#   diff JSON    -> { score_after, total_new_findings, new_findings: [{severity,...}], ... }  (no grade)
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

# Round score to 1 decimal (tolerate non-numeric)
SCORE=$(printf "%.1f" "$SCORE" 2>/dev/null || echo "$SCORE")

echo "score=$SCORE" >> "$GITHUB_OUTPUT"
echo "grade=$GRADE" >> "$GITHUB_OUTPUT"
echo "findings-count=$TOTAL" >> "$GITHUB_OUTPUT"
echo "critical-count=$CRITICAL" >> "$GITHUB_OUTPUT"
echo "high-count=$HIGH" >> "$GITHUB_OUTPUT"

# Step summary
if [ "$IS_DIFF" = "diff" ]; then
  FINDINGS_LABEL="New findings (vs base)"
else
  FINDINGS_LABEL="Findings"
fi
{
  echo "### Repotoire Analysis"
  echo ""
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Score | $SCORE ($GRADE) |"
  echo "| $FINDINGS_LABEL | $TOTAL |"
  echo "| Critical | $CRITICAL |"
  echo "| High | $HIGH |"
} >> "$GITHUB_STEP_SUMMARY"
