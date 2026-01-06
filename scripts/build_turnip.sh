#!/usr/bin/env bash
set -e

# Configuration
MESA_VERSION="mesa-25.3.3"
MESA_URL="https://gitlab.freedesktop.org/mesa/mesa.git"
BUILD_DIR="build-android"
OUTPUT_DIR="build_output"
ANDROID_API_LEVEL="29"

echo ">>> [1/6] Preparing Build Environment..."
mkdir -p "$OUTPUT_DIR"
rm -rf mesa "$BUILD_DIR"

echo ">>> [2/6] Cloning Mesa ($MESA_VERSION)..."
git clone --depth 1 --branch "$MESA_VERSION" "$MESA_URL" mesa

echo ">>> [3/6] Applying Secret Recipe via Direct Injection..."
cd mesa

# DYNAMIC FILE DISCOVERY
# This finds exactly where tu_device.c is located
TARGET_FILE=$(find . -name "tu_device.c" | grep "vulkan" | head -n 1)

if [ -z "$TARGET_FILE" ]; then
    echo "CRITICAL ERROR: tu_device.c not found in cloned mesa directory."
    exit 1
fi

echo "Found target file at: $TARGET_FILE"

# Injection using sed with a simpler append to avoid escape character issues
# We look for the api_version line and append our optimizations after it.
sed -i '/instance->api_version = TU_API_VERSION;/a \
\
   setenv("FD_DEV_FEATURES", "enable_tp_ubwc_flag_hint=1", 1);\
   setenv("MESA_SHADER_CACHE_MAX_SIZE", "1024M", 1);\
   setenv("TU_DEBUG", "force_unaligned_device_local", 1);' "$TARGET_FILE"

echo "Injection successful. Verifying changes:"
grep -C 5 "setenv" "$TARGET_FILE"
cd ..

echo ">>> [4/6] Configuring Meson..."
# Ensure android-aarch64 is in the ROOT of your repo
if [ ! -f "android-aarch64" ]; then
    echo "ERROR: Cross file 'android-aarch64' not found in repository root."
    exit 1
fi

cp android-aarch64 mesa/
cd mesa
meson setup "$BUILD_DIR" \
    --cross-file android-aarch64 \
    --buildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version="$ANDROID_API_LEVEL" \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Db_lto=true \
    -Doptimization=3 \
    -Dstrip=true \
    -Dllvm=disabled

echo ">>> [5/6] Compiling..."
ninja -C "$BUILD_DIR"

echo ">>> [6/6] Packaging Artifacts..."
# Find the compiled .so file
DRIVER_LIB=$(find "$BUILD_DIR" -name "libvulkan_freedreno.so" | head -n 1)
cp "$DRIVER_LIB" ../"$OUTPUT_DIR"/vulkan.ad07xx.so

cd ../"$OUTPUT_DIR"
cat <<EOF > meta.json
{
  "name": "Turnip v25.3.3 - Adreno 750 Optimized",
  "version": "25.3.3",
  "description": "Production A750 build. UBWC + 1GB Cache + Alignment Fixes.",
  "library": "vulkan.ad07xx.so"
}
EOF

zip -r turnip_adreno750_optimized.zip vulkan.ad07xx.so meta.json
echo ">>> Build Complete Successfully."
