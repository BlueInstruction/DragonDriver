#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }


: "${UNI_KIND:?UNI_KIND is required}"
: "${REL_TAG_STABLE:?REL_TAG_STABLE is required}"
: "${PATCH_DIR:?PATCH_DIR is required}"
: "${OUT_DIR:?OUT_DIR is required}"

ref="${1:?ref is required}"
ver_name="${2:?ver_name is required}"
filename="${3:?filename is required}"

log_info "Building ${ver_name} from ref: ${ref}"


for cmd in meson ninja patch tar; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
done

log_info "Meson version: $(meson --version)"
log_info "Ninja version: $(ninja --version)"


PKG_ROOT="../pkg_temp/${UNI_KIND}-${ref}"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}"

rm -rf build_x86 build_ec


if [[ -d "$PATCH_DIR" ]] && [[ -n "$(ls -A "$PATCH_DIR"/*.patch 2>/dev/null)" ]]; then
    log_info "Applying patches from $PATCH_DIR..."
    for patch_file in "$PATCH_DIR"/*.patch; do
        [[ -f "$patch_file" ]] || continue
        log_info "  → Applying $(basename "$patch_file")..."
        if ! patch -p1 --dry-run < "$patch_file" &>/dev/null; then
            log_error "Patch $(basename "$patch_file") cannot be applied"
            exit 1
        fi
        patch -p1 < "$patch_file"
    done
    log_info "All patches applied successfully"
else
    log_warn "No patches found in $PATCH_DIR"
fi

# x86 (32-bit)
log_info "Compiling x86 (32-bit)..."
if ! meson setup build_x86 \
    --cross-file build-win32.txt \
    --buildtype release \
    --prefix "$PWD/${PKG_ROOT}/x32"; then
    log_error "Meson setup failed for x86"
    exit 1
fi

if ! ninja -C build_x86 install; then
    log_error "Ninja build failed for x86"
    exit 1
fi
log_info "x86 build completed"

# ARM64EC
log_info "Compiling ARM64EC..."
ARGS_FLAGS=""

if [[ -n "${MOCK_DIR:-}" ]]; then
    log_info "Using ARM64EC shim from MOCK_DIR=$MOCK_DIR"
    ARGS_FLAGS="-I${MOCK_DIR} -include sarek_all_in_one.h"
elif [[ -n "${ARM64EC_CPP_ARGS:-}" ]]; then
    log_info "Using custom ARM64EC cpp_args: ${ARM64EC_CPP_ARGS}"
    ARGS_FLAGS="${ARM64EC_CPP_ARGS}"
fi

_orig_cflags="${CFLAGS:-}"
_orig_cxxflags="${CXXFLAGS:-}"

# اarm64ec.meson.ini
if [[ ! -f "../toolchains/arm64ec.meson.ini" ]]; then
    log_error "ARM64EC toolchain file not found: ../toolchains/arm64ec.meson.ini"
    exit 1
fi

if ! CFLAGS="${_orig_cflags}" \
     CXXFLAGS="${_orig_cxxflags:+${_orig_cxxflags} }${ARGS_FLAGS}" \
     meson setup build_ec \
       --cross-file ../toolchains/arm64ec.meson.ini \
       --buildtype release \
       --prefix "$PWD/${PKG_ROOT}/arm64ec" \
       ${ARGS_FLAGS:+-Dcpp_args="${ARGS_FLAGS}"}; then
    log_error "Meson setup failed for ARM64EC"
    exit 1
fi

if ! ninja -C build_ec install; then
    log_error "Ninja build failed for ARM64EC"
    exit 1
fi
log_info "ARM64EC build completed"

# WCP
log_info "Preparing WCP structure..."
WCP_DIR="../${REL_TAG_STABLE}_WCP"
rm -rf "$WCP_DIR"
mkdir -p "$WCP_DIR"/{bin,lib,share}

SRC_EC="${PKG_ROOT}/arm64ec"
SRC_32="${PKG_ROOT}/x32"


if [[ ! -d "$SRC_EC/bin" ]]; then
    log_error "ARM64EC bin directory not found: $SRC_EC/bin"
    exit 1
fi

cp -r "$SRC_EC/bin" "$WCP_DIR/"
cp -r "$SRC_EC/lib" "$WCP_DIR/"
cp -r "$SRC_EC/share" "$WCP_DIR/"

# prefixPack
if [[ -f "$SRC_EC/prefixPack.txz" ]]; then
    cp "$SRC_EC/prefixPack.txz" "$WCP_DIR/"
    log_info "Copied prefixPack.txz"
else
    log_warn "prefixPack.txz not found, skipping"
fi

# profile.json
log_info "Creating profile.json..."
cat > "$WCP_DIR/profile.json" <<EOF
{
  "type": "Wine",
  "versionName": "${ver_name}",
  "versionCode": 0,
  "description": "Proton ${REL_TAG_STABLE} ARM64EC (built with Turnip + VKD3D)",
  "files": [],
  "wine": {
    "binPath": "bin",
    "libPath": "lib"$([ -f "$WCP_DIR/prefixPack.txz" ] && echo ',
    "prefixPack": "prefixPack.txz"')
  }
}
EOF

# WCP
log_info "Creating compressed archive..."
mkdir -p "$OUT_DIR"

if ! tar -cJf "$OUT_DIR/$filename" -C "$WCP_DIR" .; then
    log_error "Failed to create archive"
    exit 1
fi


file_size=$(du -h "$OUT_DIR/$filename" | cut -f1)
log_info "Archive created: $OUT_DIR/$filename (${file_size})"

# checksum
if command -v sha256sum &> /dev/null; then
    checksum=$(sha256sum "$OUT_DIR/$filename" | cut -d' ' -f1)
    echo "$checksum" > "$OUT_DIR/${filename}.sha256"
    log_info "SHA256: $checksum"
fi

log_info "Build complete!"
log_info "Artifact: $OUT_DIR/$filename"
