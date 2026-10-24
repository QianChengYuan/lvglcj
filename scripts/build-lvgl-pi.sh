#!/usr/bin/env bash
# 交叉编译 LVGL 9.5.0 + lvglcj 垫片 → lib/linux-arm64/（aarch64，DRM + evdev）
#
# 已实测环境：Ubuntu 24.04 (WSL2)，aarch64-linux-gnu-gcc 13.3，cmake 3.28，ninja 1.11
#
# 依赖：
#   sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu cmake ninja-build pkg-config
#   sudo dpkg --add-architecture arm64
#   sudo apt install libdrm-dev:arm64 libevdev-dev:arm64
#   （amd64 机器上装 arm64 包需要 multiarch：主源标 Architectures: amd64，
#     另加 ubuntu-ports 源标 Architectures: arm64）
#
# 用法：./scripts/build-lvgl-pi.sh
#   环境变量（都可选）：
#     LVGL_DIR=/path/to/lvgl      复用已有源码
#     BUILD_DIR=/opt/build-pi     构建目录
#     INC_DIR=/opt/arm64-include  架构无关头文件目录（默认自动准备）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_SRC="$ROOT/native/shim/lvgl_shim.c"
CONF="$ROOT/native/config/pi/lv_conf.h"     # Pi 专用配置（DRM + evdev + RGB565）
TOOLCHAIN="$ROOT/cmake/toolchain-aarch64.cmake"
LVGL_TAG="v9.5.0"
LVGL_DIR="${LVGL_DIR:-$ROOT/lvgl}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/pi}"
OUT_DIR="${OUT_DIR:-$ROOT/lib/linux-arm64}"
SHIM_BUILD="$BUILD_DIR/shim"
CROSS="aarch64-linux-gnu-"

# libdrm / libevdev 的头文件是架构无关的，交叉 gcc 不会自动搜 /usr/include，
# 所以把它们扁平拷到独立目录，避免把 host 的整个 /usr/include 塞进 include 路径。
INC_DIR="${INC_DIR:-/opt/arm64-include}"

for f in "$SHIM_SRC" "$CONF" "$TOOLCHAIN"; do
  [ -f "$f" ] || { echo "缺少文件：$f" >&2; exit 1; }
done

if [ ! -d "$LVGL_DIR" ]; then
  echo "==> 克隆 LVGL $LVGL_TAG"
  git clone --depth 1 -b "$LVGL_TAG" https://gitcode.com/gh_mirrors/lvgl/lvgl.git "$LVGL_DIR"
fi

if [ ! -d "$INC_DIR" ]; then
  echo "==> 准备 $INC_DIR（libdrm / libevdev 头文件）"
  mkdir -p "$INC_DIR"
  cp /usr/include/xf86drm*.h "$INC_DIR"/
  cp /usr/include/libdrm/*.h "$INC_DIR"/
  cp -r /usr/include/libevdev-1.0 "$INC_DIR"/
fi

mkdir -p "$OUT_DIR" "$SHIM_BUILD"

echo "==> cmake 配置（aarch64 交叉）"
# LVGL 9.5 用 LV_BUILD_CONF_PATH（旧名 LV_CONF_PATH 会被静默忽略）
cmake -B "$BUILD_DIR" -G Ninja -S "$LVGL_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DLV_BUILD_CONF_PATH="$CONF" \
  -DCMAKE_C_FLAGS="-I$INC_DIR -I$INC_DIR/libevdev-1.0" \
  -DCMAKE_CXX_FLAGS="-I$INC_DIR -I$INC_DIR/libevdev-1.0"

echo "==> 编译 liblvgl.a"
cmake --build "$BUILD_DIR"

echo "==> 编译 C 垫片 liblvglcjshim.a"
# lib/linux-arm64 的配置未开 LV_USE_FREETYPE，故无需 freetype 头文件；
# 中文字形依赖内置思源黑体子集（要完整中文就在 Pi 上开 FREETYPE 并装 Noto CJK）。
${CROSS}gcc -c -O2 -fPIC -Wall -Wextra \
  -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
  -I"$LVGL_DIR" -I"$(dirname "$CONF")" -I"$INC_DIR" -I"$INC_DIR/libevdev-1.0" \
  -o "$SHIM_BUILD/lvgl_shim.o" \
  "$SHIM_SRC"
${CROSS}ar rcs "$OUT_DIR/liblvglcjshim.a" "$SHIM_BUILD/lvgl_shim.o"

cp -f "$BUILD_DIR/lib/liblvgl.a" "$OUT_DIR/liblvgl.a" 2>/dev/null || \
  find "$BUILD_DIR" -name 'liblvgl.a' -exec cp -f {} "$OUT_DIR/" \;

echo "==> 完成：$OUT_DIR"
ls -l "$OUT_DIR"
${CROSS}readelf -h "$OUT_DIR/liblvgl.a" 2>/dev/null | grep -m1 Machine
echo
echo "注意：仓颉侧交叉到 aarch64 需要 linux-aarch64 版 SDK（cjc --target），"
echo "      linux-x64 SDK 只能本机编译；详见 docs/build-guide.md。"
