# Repotoire Action

[![GitHub Action](https://img.shields.io/badge/GitHub%20Action-v2-blue?logo=github)](https://github.com/Zach-hammad/repotoire-action)
[![Repotoire](https://img.shields.io/badge/repotoire-%E2%89%A5%200.9.0-green)](https://github.com/Zach-hammad/repotoire)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**The branch-relative code-health gate for CI.** Runs [Repotoire](https://github.com/Zach-hammad/repotoire) on every push / PR and fails the build only on what *this change* introduced — a tainted flow into a dangerous sink, a committed credential, a known-vulnerable dependency the code actually calls — never on the repo's existing backlog or on taste. Everything else is advisory. Produces SARIF for GitHub Code Scanning plus structured JSON for downstream automation.

## `@v2` vs `@v1`

| | `@v2` (current) | `@v1` (frozen) |
|---|---|---|
| Default gate | `fail-on-tier: blocking` — fails only on Blocking-tier findings (evidence-carrying "you broke something") | `fail-on: ''` — never fails unless you set `fail-on: <severity>` |
| Gate input | `fail-on-tier` (`blocking` \| `advisory` \| `deep` \| `''`) | `fail-on` (`critical` \| `high` \| `medium` \| `low` \| `''`) |
| Requires | `repotoire >= 0.9.0` (auto with `version: latest`) | any released `repotoire` |
| Legacy `fail-on` | still works — when set it overrides `fail-on-tier` and runs the old severity gate (with a deprecation warning) | this is the only gate |

`@v1` keeps working unchanged. Move to `@v2` to get the blocking-tier gate as the default.

## Quick Start

```yaml
- uses: Zach-hammad/repotoire-action@v2
  id: repotoire
- uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: ${{ steps.repotoire.outputs.sarif-file }}
```

That's it: on a PR the action runs `repotoire diff <base> --fail-on-tier blocking` (changed hunks only); on a push it runs a full `repotoire analyze`. The build fails iff a Blocking-tier finding lands in the change.

## Full Example with Code Scanning

```yaml
name: Code Health
on: [push, pull_request]

permissions:
  security-events: write   # SARIF upload to Code Scanning
  pull-requests: write     # PR comment with the analysis summary
  contents: read

jobs:
  repotoire:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # full history for git analysis (churn, blame, co-change)

      - uses: Zach-hammad/repotoire-action@v2
        id: repotoire
        # fail-on-tier: blocking is the default — set it explicitly to widen (advisory) or disable ('')

      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.repotoire.outputs.sarif-file }}
```

## PR Workflow (Recommended Setup)

On pull requests Repotoire automatically runs in diff mode against the PR base — only findings introduced by the changed hunks can trip the gate:

```yaml
name: PR Code Health
on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  security-events: write
  pull-requests: write
  contents: read

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: Zach-hammad/repotoire-action@v2
        id: repotoire
        with:
          # diff-only: auto    # diff on PRs, full on push (default)
          # fail-on-tier: blocking   # default

      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.repotoire.outputs.sarif-file }}

      # PR comment is posted automatically (comment: 'true' by default); set comment: 'false' to disable
```

### Legacy severity gate

To keep the pre-`@v2` behavior (fail on a severity threshold rather than the tier), set `fail-on` — it overrides `fail-on-tier`:

```yaml
- uses: Zach-hammad/repotoire-action@v2
  with:
    fail-on: high   # deprecated; prints a warning, runs the old severity gate
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Repotoire version to install (e.g., `v0.9.0` or `latest`). The default gate (`fail-on-tier`) needs `repotoire >= 0.9.0`. | `latest` |
| `path` | Path to the repository/directory to analyze | `.` |
| `format` | Output format: `sarif`, `json`, `text`, `markdown` | `sarif` |
| `fail-on-tier` | Fail the build if a new finding at this tier or higher lands in the change: `blocking`, `advisory`, `deep`. Empty = never fail. | `blocking` |
| `fail-on` | **Deprecated** — use `fail-on-tier`. Severity gate (`critical` \| `high` \| `medium` \| `low`); when non-empty it overrides `fail-on-tier`. | `''` |
| `diff-only` | Only analyze the diff vs base. `auto` = diff on PRs, full on push. | `auto` |
| `config` | Path to `repotoire.toml` config file. Empty = auto-detect. | `''` |
| `args` | Additional CLI arguments passed to `repotoire` | `''` |
| `comment` | Post the analysis summary as a PR comment | `'true'` |

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
| `exit-code` | Repotoire exit code (0 = pass, 1 = the `fail-on-tier` / `fail-on` gate triggered) |

## Using Outputs in Downstream Steps

```yaml
- uses: Zach-hammad/repotoire-action@v2
  id: repotoire
- run: |
    echo "Score: ${{ steps.repotoire.outputs.score }}"
    echo "Grade: ${{ steps.repotoire.outputs.grade }}"
    if [ "${{ steps.repotoire.outputs.critical-count }}" -gt 0 ]; then
      echo "::error::Critical findings detected!"
    fi
```

## Troubleshooting

### `--fail-on-tier` not recognized

The `fail-on-tier` gate needs `repotoire >= 0.9.0`. If you pin an older `version:`, the action degrades to `--fail-on high` with a warning — pin `version: latest` (or `>= v0.9.0`) to use the blocking-tier gate.

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
  pull-requests: write     # PR comment with analysis summary
  contents: read
```

Without `pull-requests: write`, the PR comment step will warn but not fail. Without `security-events: write`, SARIF upload will fail.

### Version pinning

For reproducible builds, pin to a specific version instead of `latest`:

```yaml
- uses: Zach-hammad/repotoire-action@v2
  with:
    version: 'v0.9.0'
```

### Platform support

The action supports `ubuntu-latest` and `macos-latest` runners (both x86_64 and ARM64 for macOS). Windows runners are not currently supported.

## License

MIT -- see [LICENSE](LICENSE).

## Links

- [Repotoire](https://github.com/Zach-hammad/repotoire) -- the code health analysis engine
- [Repotoire Documentation](https://github.com/Zach-hammad/repotoire#readme)
