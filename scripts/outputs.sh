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

# Parse results
SCORE=$(jq -r '.overall_score // 0' "$JSON_FILE")
GRADE=$(jq -r '.grade // "?"' "$JSON_FILE")
TOTAL=$(jq -r '.findings | length' "$JSON_FILE")
CRITICAL=$(jq -r '[.findings[] | select(.severity == "critical")] | length' "$JSON_FILE")
HIGH=$(jq -r '[.findings[] | select(.severity == "high")] | length' "$JSON_FILE")

# Round score to 1 decimal
SCORE=$(printf "%.1f" "$SCORE")

echo "score=$SCORE" >> "$GITHUB_OUTPUT"
echo "grade=$GRADE" >> "$GITHUB_OUTPUT"
echo "findings-count=$TOTAL" >> "$GITHUB_OUTPUT"
echo "critical-count=$CRITICAL" >> "$GITHUB_OUTPUT"
echo "high-count=$HIGH" >> "$GITHUB_OUTPUT"

# Summary
echo "### Repotoire Analysis" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| Metric | Value |" >> "$GITHUB_STEP_SUMMARY"
echo "|--------|-------|" >> "$GITHUB_STEP_SUMMARY"
echo "| Score | $SCORE ($GRADE) |" >> "$GITHUB_STEP_SUMMARY"
echo "| Findings | $TOTAL |" >> "$GITHUB_STEP_SUMMARY"
echo "| Critical | $CRITICAL |" >> "$GITHUB_STEP_SUMMARY"
echo "| High | $HIGH |" >> "$GITHUB_STEP_SUMMARY"
