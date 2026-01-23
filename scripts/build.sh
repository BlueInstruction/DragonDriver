#!/bin/bash -e

set -o pipefail

# COLORS
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# CONFIG
BUILD_DIR="$(pwd)/build_workspace"
PATCHES_DIR="$(pwd)/patches"
NDK_VERSION="${NDK_VERSION:-android-ndk-r30}"
API_LEVEL="${API_LEVEL:-35}"

# Mesa Sources
MESA_FREEDESKTOP="https://gitlab.freedesktop.org/mesa/mesa.git"
MESA_FREEDESKTOP_MIRROR="https://github.com/mesa3d/mesa.git"
MESA_WHITEBELYASH="https://github.com/whitebelyash/mesa-tu8.git"
MESA_WHITEBELYASH_BRANCH="gen8"

# Runtime Config
MESA_REPO_SOURCE="${MESA_REPO_SOURCE:-freedesktop}"
BUILD_VARIANT="${1:-gen8}"
CUSTOM_COMMIT="${2:-}"
COMMIT_HASH_SHORT=""
MESA_VERSION=""
MAX_RETRIES=3
RETRY_DELAY=15
BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# LOGGING
log()     { echo -e "${CYAN}[Build]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info()    { echo -e "${MAGENTA}[INFO]${NC} $1"; }
header()  { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"; }

# UTILITIES
retry_command() {
    local cmd="$1"
    local description="$2"
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log "Attempt $attempt/$MAX_RETRIES: $description"
        if eval "$cmd"; then
            return 0
        fi
        warn "Failed, retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        ((attempt++))
    done

    return 1
}

check_dependencies() {
    log "Checking dependencies..."
    local deps=(git curl unzip patchelf zip meson ninja ccache)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}"
    fi
    success "All dependencies found"
}

# NDK SETUP
setup_ndk() {
    header "NDK Setup"

    if [ -n "${ANDROID_NDK_LATEST_HOME}" ] && [ -d "${ANDROID_NDK_LATEST_HOME}" ]; then
        export ANDROID_NDK_HOME="${ANDROID_NDK_LATEST_HOME}"
        info "Using system NDK: $ANDROID_NDK_HOME"
        return
    fi

    if [ -d "$BUILD_DIR/$NDK_VERSION" ]; then
        export ANDROID_NDK_HOME="$BUILD_DIR/$NDK_VERSION"
        info "Using cached NDK: $ANDROID_NDK_HOME"
        return
    fi

    log "Downloading NDK $NDK_VERSION..."
    local ndk_url="https://dl.google.com/android/repository/${NDK_VERSION}-linux.zip"

    if ! retry_command "curl -sL '$ndk_url' -o core.zip" "Downloading NDK"; then
        error "Failed to download NDK"
    fi

    unzip -q core.zip && rm -f core.zip
    export ANDROID_NDK_HOME="$BUILD_DIR/$NDK_VERSION"
    success "NDK installed: $ANDROID_NDK_HOME"
}

# MESA CLONE
clone_mesa() {
    header "Mesa Source"

    [ -d "$BUILD_DIR/mesa" ] && rm -rf "$BUILD_DIR/mesa"

    if [ "$MESA_REPO_SOURCE" = "whitebelyash" ]; then
        log "Cloning from Whitebelyash (Gen8 branch)..."
        if retry_command "git clone --depth=200 --branch '$MESA_WHITEBELYASH_BRANCH' '$MESA_WHITEBELYASH' '$BUILD_DIR/mesa' 2>/dev/null" "Cloning Whitebelyash"; then
            setup_mesa_repo
            apply_whitebelyash_fixes
            return
        fi
        warn "Whitebelyash unavailable, falling back to freedesktop..."
    fi

    log "Cloning from freedesktop.org..."
    if retry_command "git clone --depth=500 '$MESA_FREEDESKTOP' '$BUILD_DIR/mesa' 2>/dev/null" "Cloning from GitLab"; then
        cd "$BUILD_DIR/mesa"
        
        
        log "Updating to latest main branch..."
        git remote set-branches origin main
        git fetch origin main --depth=1 --update-shallow || warn "Shallow fetch failed, continuing anyway"
        git checkout main || warn "Checkout main failed"
        git reset --hard origin/main || warn "Reset to origin/main failed"
        git clean -fdx || true  
        
        setup_mesa_repo
        return
    fi

    warn "GitLab unavailable, trying GitHub mirror..."
    if retry_command "git clone --depth=500 '$MESA_FREEDESKTOP_MIRROR' '$BUILD_DIR/mesa' 2>/dev/null" "Cloning from GitHub"; then
        setup_mesa_repo
        return
    fi

    error "Failed to clone Mesa from all sources"
}

setup_mesa_repo() {
    cd "$BUILD_DIR/mesa"
    git config user.name "BuildUser"
    git config user.email "build@system.local"

    if [ -n "$CUSTOM_COMMIT" ]; then
        log "Checking out: $CUSTOM_COMMIT"
        git fetch --depth=100 origin 2>/dev/null || true
        git checkout "$CUSTOM_COMMIT" 2>/dev/null || warn "Could not checkout $CUSTOM_COMMIT, using HEAD"
    fi

    COMMIT_HASH_SHORT=$(git rev-parse --short HEAD)
    MESA_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")

    echo "$MESA_VERSION" > "$BUILD_DIR/version.txt"
    success "Mesa ready: $MESA_VERSION ($COMMIT_HASH_SHORT)"
}

apply_whitebelyash_fixes() {
    log "Applying Whitebelyash compatibility fixes..."
    cd "$BUILD_DIR/mesa"

    if [ -f "src/freedreno/common/freedreno_devices.py" ]; then
        perl -i -p0e 's/(\n\s*a8xx_825)/,$1/s' src/freedreno/common/freedreno_devices.py 2>/dev/null || true
        sed -i '/REG_A8XX_GRAS_UNKNOWN_/d' src/freedreno/common/freedreno_devices.py 2>/dev/null || true
    fi

    find src/freedreno/vulkan -name "*.cc" -print0 2>/dev/null | \
        xargs -0 sed -i 's/ && (pdevice->info->chip != 8)//g' 2>/dev/null || true
    find src/freedreno/vulkan -name "*.cc" -print0 2>/dev/null | \
        xargs -0 sed -i 's/ && (pdevice->info->chip == 8)//g' 2>/dev/null || true

    success "Whitebelyash fixes applied"
}

# PREPARE BUILD DIR
prepare_build_dir() {
    header "Preparing Build Directory"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    setup_ndk
    clone_mesa

    cd "$BUILD_DIR"
    success "Build directory ready - Mesa $MESA_VERSION ($COMMIT_HASH_SHORT)"
}

# PATCH SYSTEM
apply_patch_file() {
    local patch_path="$1"
    local full_path="$PATCHES_DIR/$patch_path.patch"
    if [ ! -f "$full_path" ]; then warn "Patch not found: $patch_path"; return 1; fi
    log "Applying patch: $patch_path"
    cd "$BUILD_DIR/mesa"
    if git apply "$full_path" --check 2>/dev/null; then
        git apply "$full_path"
        success "Patch applied: $patch_path"
        return 0
    fi
    warn "Patch failed: $patch_path"
    return 1
}

apply_sysmem_rendering() {
    log "Applying sysmem rendering preference..."
    cd "$BUILD_DIR/mesa"
    local file="src/freedreno/vulkan/tu_device.cc"
    if [ ! -f "$file" ]; then return 1; fi
    sed -i '1i\/* Build: Sysmem Rendering Preference */' "$file"
    if grep -q "use_bypass" "$file"; then
        sed -i 's/use_bypass = false/use_bypass = true/g' "$file" 2>/dev/null || true
    fi
    success "Sysmem rendering applied"
}


configure_and_build() {
    header "Meson Configuration"
    cd "$BUILD_DIR/mesa"
    
    
    meson setup build \
        --prefix="/tmp/mesa-install" \
        -Dbuildtype=release \
        -Dplatforms=android \
        -Dplatform-sdk-version=$API_LEVEL \
        -Dgallium-drivers=freedreno \
        -Dvulkan-drivers=freedreno \
        -Dfreedreno-kmds=msm,virtio \
        -Dvulkan-layers=device-select,overlay \
        -Dbuild-aco-tests=true \
        -Dfreedreno-enable-sparse=true \
        -Dandroid-libbacktrace=disabled \
        -Dcpp_rtti=false

    log "Starting Ninja build..."
    ninja -C build
}

# START
check_dependencies
prepare_build_dir
apply_sysmem_rendering
configure_and_build
