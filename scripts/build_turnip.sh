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

echo ">>> [3/6] Generating and Applying Patch..."
cd mesa
TARGET_FILE=$(find src -name "tu_device.c" | head -n 1)

if [ -z "$TARGET_FILE" ]; then
    echo "ERROR: tu_device.c not found."
    exit 1
fi

cat << EOF > ../recipe.patch
--- a/$TARGET_FILE
+++ b/$TARGET_FILE
@@ -234,6 +234,18 @@
    instance->physical_device_count = -1;
    instance->api_version = TU_API_VERSION;
+
+   // === SECRET RECIPE OPTIMIZATIONS ===
+   if (!getenv("FD_DEV_FEATURES")) {
+       setenv("FD_DEV_FEATURES", "enable_tp_ubwc_flag_hint=1", 1);
+   }
+   if (!getenv("MESA_SHADER_CACHE_MAX_SIZE")) {
+       setenv("MESA_SHADER_CACHE_MAX_SIZE", "1024M", 1);
+   }
+   if (!getenv("TU_DEBUG")) {
+       setenv("TU_DEBUG", "force_unaligned_device_local", 1);
+   }
EOF

git apply -p1 ../recipe.patch
cd ..

echo ">>> [4/6] Configuring Meson..."
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

echo ">>> [6/6] Packaging..."
DRIVER_LIB=$(find "$BUILD_DIR" -name "libvulkan_freedreno.so" | head -n 1)
cp "$DRIVER_LIB" ../"$OUTPUT_DIR"/vulkan.ad07xx.so

cd ../"$OUTPUT_DIR"
cat <<EOF > meta.json
{
  "name": "Turnip v25.3.3 - Adreno 750 Secret Recipe",
  "version": "25.3.3",
  "description": "Optimized A750 build for Winlator/CMOD. Fixes sky bugs and stutter.",
  "library": "vulkan.ad07xx.so"
}
EOF

zip -r turnip_adreno750_optimized.zip vulkan.ad07xx.so meta.json
echo ">>> Build Complete."
