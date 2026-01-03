#!/usr/bin/env bash
set -e

ROOT_DIR="$(pwd)"
WORKDIR="$ROOT_DIR/workdir"
OUTDIR="$ROOT_DIR/out"

NDK_VERSION="r27d"
API=27

mkdir -p "$WORKDIR" "$OUTDIR"

# Download Android NDK
if [ ! -d "$WORKDIR/android-ndk-$NDK_VERSION" ]; then
  echo "Downloading Android NDK..."
  curl -L -o ndk.zip https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip
  unzip -q ndk.zip -d "$WORKDIR"
  # 重命名目錄以去除版本號中的尾隨字符
  mv "$WORKDIR/android-ndk-$NDK_VERSION"* "$WORKDIR/android-ndk-$NDK_VERSION" 2>/dev/null || true
fi

# 設置 NDK 路徑
if [ -d "$WORKDIR/android-ndk-$NDK_VERSION" ]; then
  export NDKDIR="$WORKDIR/android-ndk-$NDK_VERSION"
elif [ -d "$WORKDIR/android-ndk-$NDK_VERSION-linux" ]; then
  export NDKDIR="$WORKDIR/android-ndk-$NDK_VERSION-linux"
else
  echo "Error: Could not find NDK directory"
  ls -la "$WORKDIR"
  exit 1
fi

export PATH="$NDKDIR/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

echo "Using NDK at: $NDKDIR"

# Clone Mesa fresh - 直接克隆 24.1 分支
rm -rf "$WORKDIR/mesa"
echo "Cloning Mesa repository (24.1 branch)..."
# 嘗試多個可能的穩定分支
if git clone --depth 1 --branch 24.1 https://gitlab.freedesktop.org/mesa/mesa.git "$WORKDIR/mesa" 2>/dev/null; then
  echo "Successfully cloned 24.1 branch"
elif git clone --depth 1 --branch 24.0 https://gitlab.freedesktop.org/mesa/mesa.git "$WORKDIR/mesa" 2>/dev/null; then
  echo "Successfully cloned 24.0 branch"
elif git clone --depth 1 --branch 23.3 https://gitlab.freedesktop.org/mesa/mesa.git "$WORKDIR/mesa" 2>/dev/null; then
  echo "Successfully cloned 23.3 branch"
else
  echo "Falling back to main branch..."
  git clone --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git "$WORKDIR/mesa"
fi

cd "$WORKDIR/mesa"

# 顯示當前分支
echo "Current branch: $(git branch --show-current)"

# 創建一個簡單的 pkg-config 腳本來繞過依賴檢查
echo "Creating dummy pkg-config script..."
cat > dummy-pkg-config << 'EOF'
#!/bin/bash
# 一個假的 pkg-config 腳本，返回成功但沒有輸出
if [ "$1" = "--exists" ]; then
    # 對於 --exists 參數，返回失敗（非0）來強制使用 fallback
    exit 1
fi
# 返回空輸出
exit 0
EOF

chmod +x dummy-pkg-config

# Generate Meson cross file
echo "Generating cross-compilation configuration..."
cat > android-aarch64.txt <<EOF
[binaries]
c = ['aarch64-linux-android${API}-clang']
cpp = ['aarch64-linux-android${API}-clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
pkg-config = '$PWD/dummy-pkg-config'

[properties]
sys_root = '$NDKDIR/toolchains/llvm/prebuilt/linux-x86_64/sysroot'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

# 手動創建 libdrm.wrap 文件以確保使用 subproject
echo "Creating libdrm wrap file..."
mkdir -p subprojects
cat > subprojects/libdrm.wrap << 'EOF'
[wrap-git]
url = https://gitlab.freedesktop.org/mesa/drm.git
revision = main
depth = 1

[provide]
dependency_names = libdrm
EOF

# 先下載 subprojects
echo "Downloading subprojects..."
meson subprojects download 2>/dev/null || true

# Configure Mesa with minimal Android build
echo "Configuring Mesa build..."
meson setup build-android . \
  --cross-file android-aarch64.txt \
  -Dplatforms=android \
  -Dandroid-stub=true \
  -Dvulkan-drivers=freedreno \
  -Dgallium-drivers= \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dllvm=disabled \
  -Dshared-glapi=disabled \
  -Dglvnd=disabled \
  -Dosmesa=false \
  -Dbuildtype=release \
  -Dstrip=true \
  -Dlibunwind=disabled \
  -Dzstd=disabled

# Build
echo "Building Mesa Turnip driver..."
ninja -C build-android

# Output
echo "Copying output files..."
cp build-android/src/freedreno/vulkan/libvulkan_freedreno.so \
  "$OUTDIR/vulkan.ad07xx.so"

cat > "$OUTDIR/meta.json" <<EOF
{
  "name": "Mesa Turnip (Adreno)",
  "vendor": "Mesa",
  "driver": "turnip",
  "arch": "aarch64"
}
EOF

echo "Build completed successfully!"
echo "Output files in: $OUTDIR"
ls -la "$OUTDIR"
