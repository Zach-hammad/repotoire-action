#!/usr/bin/env bash
set -euo pipefail

VERSION="${INPUT_VERSION:-latest}"

# Determine platform
case "${RUNNER_OS:-Linux}" in
  Linux)
    PLATFORM="linux-x86_64"
    EXT="tar.gz"
    ;;
  macOS)
    case "${RUNNER_ARCH:-X64}" in
      ARM64) PLATFORM="macos-aarch64" ;;
      *)     PLATFORM="macos-x86_64" ;;
    esac
    EXT="tar.gz"
    ;;
  *)
    echo "::error::Unsupported platform: ${RUNNER_OS}. Only Linux and macOS are supported."
    exit 1
    ;;
esac

# Resolve 'latest' to actual version tag
if [ "$VERSION" = "latest" ]; then
  echo "::group::Resolving latest version"
  VERSION=$(curl -sfL \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/Zach-hammad/repotoire/releases/latest \
    | jq -r .tag_name)
  if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "::error::Failed to resolve latest version from GitHub API"
    exit 1
  fi
  echo "Resolved latest version: $VERSION"
  echo "::endgroup::"
fi

# Check cache
INSTALL_DIR="${RUNNER_TOOL_CACHE:-/tmp}/repotoire/${VERSION}"
if [ -x "$INSTALL_DIR/repotoire" ]; then
  echo "Using cached repotoire $VERSION"
  echo "$INSTALL_DIR" >> "$GITHUB_PATH"
  exit 0
fi

# Download
echo "::group::Installing repotoire $VERSION ($PLATFORM)"
DOWNLOAD_URL="https://github.com/Zach-hammad/repotoire/releases/download/${VERSION}/repotoire-${PLATFORM}.${EXT}"
echo "Downloading: $DOWNLOAD_URL"

mkdir -p "$INSTALL_DIR"
HTTP_CODE=$(curl -sfL -w "%{http_code}" -o /tmp/repotoire-download.${EXT} "$DOWNLOAD_URL" || true)

if [ "$HTTP_CODE" != "200" ]; then
  # Retry once
  echo "First download attempt failed (HTTP $HTTP_CODE), retrying..."
  sleep 2
  HTTP_CODE=$(curl -sfL -w "%{http_code}" -o /tmp/repotoire-download.${EXT} "$DOWNLOAD_URL" || true)
  if [ "$HTTP_CODE" != "200" ]; then
    echo "::error::Failed to download repotoire $VERSION for $PLATFORM (HTTP $HTTP_CODE). Check that the version exists at: $DOWNLOAD_URL"
    exit 1
  fi
fi

# Extract
tar xzf /tmp/repotoire-download.${EXT} -C "$INSTALL_DIR"
rm -f /tmp/repotoire-download.${EXT}

# Verify binary
if [ ! -x "$INSTALL_DIR/repotoire" ]; then
  # Binary might be nested in a directory
  FOUND=$(find "$INSTALL_DIR" -name "repotoire" -type f | head -1)
  if [ -n "$FOUND" ]; then
    mv "$FOUND" "$INSTALL_DIR/repotoire"
    chmod +x "$INSTALL_DIR/repotoire"
  else
    echo "::error::Downloaded archive did not contain a 'repotoire' binary"
    exit 1
  fi
fi

echo "$INSTALL_DIR" >> "$GITHUB_PATH"
echo "Installed repotoire $VERSION to $INSTALL_DIR"
"$INSTALL_DIR/repotoire" version
echo "::endgroup::"
