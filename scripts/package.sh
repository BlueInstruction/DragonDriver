#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

VERSION="${1:-}"
COMMIT="${2:-}"
ARCH="${3:-x86_64}"
BUILD_DIR="${4:-$PROJECT_ROOT/output}"
PKG_DIR="$PROJECT_ROOT/package"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ -z "$VERSION" ]] && error "version required"
[[ -z "$COMMIT" ]] && error "commit required"

VERSION_CLEAN="${VERSION#v}"

if [[ "$ARCH" == "x86_64" ]]; then
    ARTIFACT_NAME="vkd3d-proton-${VERSION_CLEAN}-${COMMIT}-experimental"
else
    ARTIFACT_NAME="vkd3d-proton-arm64ec-${VERSION_CLEAN}-${COMMIT}-experimental"
fi

log "packaging: $ARTIFACT_NAME"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/system32" "$PKG_DIR/syswow64"

if [[ "$ARCH" == "x86_64" ]]; then
    SRC_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "vkd3d-proton-*" | head -1)
    [[ -z "$SRC_PATH" ]] && error "build output not found"

    cp "$SRC_PATH/x64/"*.dll "$PKG_DIR/system32/"
    cp "$SRC_PATH/x86/"*.dll "$PKG_DIR/syswow64/"
else
    for dll in d3d12.dll d3d12core.dll; do
        arm64_dll=$(find "$PROJECT_ROOT/src/build-arm64ec" -name "$dll" -type f 2>/dev/null | head -1)
        i686_dll=$(find "$PROJECT_ROOT/src/build-i686" -name "$dll" -type f 2>/dev/null | head -1)
        [[ -n "$arm64_dll" ]] && cp "$arm64_dll" "$PKG_DIR/system32/"
        [[ -n "$i686_dll" ]] && cp "$i686_dll" "$PKG_DIR/syswow64/"
    done
fi

cd "$PKG_DIR"
sha256sum system32/*.dll syswow64/*.dll > checksums.txt

if [[ "$ARCH" == "x86_64" ]]; then
    ARCH_DESC="x86_64"
else
    ARCH_DESC="arm64ec"
fi

cat > profile.json << EOF
{
  "type": "VKD3D",
  "versionName": "${VERSION_CLEAN}-${COMMIT}-experimental",
  "versionCode": $(date +%Y%m%d),
  "description": "vkd3d-proton ${VERSION_CLEAN} experimental build",
  "files": [
    {"source": "system32/d3d12.dll", "target": "\${system32}/d3d12.dll"},
    {"source": "system32/d3d12core.dll", "target": "\${system32}/d3d12core.dll"},
    {"source": "syswow64/d3d12.dll", "target": "\${syswow64}/d3d12.dll"},
    {"source": "syswow64/d3d12core.dll", "target": "\${syswow64}/d3d12core.dll"}
  ]
}
EOF

tar --zstd -cf "$PROJECT_ROOT/${ARTIFACT_NAME}.wcp" .

log "package: ${ARTIFACT_NAME}.wcp"
log "size: $(du -h "$PROJECT_ROOT/${ARTIFACT_NAME}.wcp" | cut -f1)"

echo "ARTIFACT_NAME=$ARTIFACT_NAME" >> "${GITHUB_ENV:-/dev/null}"
