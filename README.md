# Repotoire Action

[![GitHub Action](https://img.shields.io/badge/GitHub%20Action-v1-blue?logo=github)](https://github.com/Zach-hammad/repotoire-action)
[![Repotoire](https://img.shields.io/badge/repotoire-latest-green)](https://github.com/Zach-hammad/repotoire)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Graph-powered code health analysis as a GitHub Action. 107 detectors, 9 languages, one binary.

Runs [Repotoire](https://github.com/Zach-hammad/repotoire) on your codebase and produces SARIF output compatible with GitHub Code Scanning, plus structured JSON for downstream automation.

## Quick Start

Add Repotoire to any workflow in 3 lines:

```yaml
- uses: Zach-hammad/repotoire-action@v1
  id: repotoire
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: ${{ steps.repotoire.outputs.sarif-file }}
```

## Full Example with Code Scanning

```yaml
name: Code Health
on: [push, pull_request]

permissions:
  security-events: write
  contents: read

jobs:
  repotoire:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for git analysis (churn, blame, co-change)

      - uses: Zach-hammad/repotoire-action@v1
        id: repotoire
        with:
          fail-on: high

      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.repotoire.outputs.sarif-file }}
```

## PR Workflow (Recommended Setup)

For pull requests, Repotoire automatically runs in diff mode, analyzing only changed files:

```yaml
name: PR Code Health
on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  security-events: write
  contents: read

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: Zach-hammad/repotoire-action@v1
        id: repotoire
        with:
          fail-on: high
          diff-only: auto  # Diff on PRs, full on push (default)

      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.repotoire.outputs.sarif-file }}

      # PR comment is posted automatically (comment: 'true' by default)
      # Set comment: 'false' to disable
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Repotoire version to install (e.g., `v0.3.113` or `latest`) | `latest` |
| `path` | Path to the repository/directory to analyze | `.` |
| `format` | Output format: `sarif`, `json`, `text`, `markdown` | `sarif` |
| `fail-on` | Fail if any finding meets this severity: `critical`, `high`, `medium`, `low`. Empty = do not fail. | `''` |
| `diff-only` | Only analyze diff vs base. `auto` = diff on PRs, full on push. | `auto` |
| `config` | Path to `repotoire.toml` config file. Empty = auto-detect. | `''` |
| `args` | Additional CLI arguments passed to `repotoire analyze` | `''` |
| `comment` | Post analysis summary as a PR comment | `'true'` |

## Outputs

| Output | Description |
|--------|-------------|
| `score` | Overall health score (0-100) |
| `grade` | Letter grade (A+ through F) |
| `findings-count` | Total number of findings |
| `critical-count` | Critical severity findings |
| `high-count` | High severity findings |
| `sarif-file` | Path to the SARIF output file |
| `json-file` | Path to the JSON output file |
| `exit-code` | Repotoire exit code (0 = pass, 1 = fail-on triggered) |

## Using Outputs in Downstream Steps

```yaml
- uses: Zach-hammad/repotoire-action@v1
  id: repotoire
- run: |
    echo "Score: ${{ steps.repotoire.outputs.score }}"
    echo "Grade: ${{ steps.repotoire.outputs.grade }}"
    if [ "${{ steps.repotoire.outputs.critical-count }}" -gt 0 ]; then
      echo "::error::Critical findings detected!"
    fi
```

## Troubleshooting

### Shallow clone warning

If you see a warning about shallow clones, add `fetch-depth: 0` to your checkout step:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

Without full git history, Repotoire cannot perform churn analysis, blame-based detection, or co-change analysis. The action will still work, but git-dependent detectors will be skipped.

### Permissions

For full functionality, your workflow needs:

```yaml
permissions:
  security-events: write   # SARIF upload to Code Scanning
  pull-requests: write      # PR comment with analysis summary
  contents: read
```

Without `pull-requests: write`, the PR comment step will warn but not fail. Without `security-events: write`, SARIF upload will fail.

### Version pinning

For reproducible builds, pin to a specific version instead of `latest`:

```yaml
- uses: Zach-hammad/repotoire-action@v1
  with:
    version: 'v0.3.113'
```

### Platform support

The action supports `ubuntu-latest` and `macos-latest` runners (both x86_64 and ARM64 for macOS). Windows runners are not currently supported.

## License

MIT -- see [LICENSE](LICENSE).

## Links

- [Repotoire](https://github.com/Zach-hammad/repotoire) -- the code health analysis engine
- [Repotoire Documentation](https://github.com/Zach-hammad/repotoire#readme)
