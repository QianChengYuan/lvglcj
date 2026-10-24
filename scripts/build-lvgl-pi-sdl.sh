#!/usr/bin/env bash
# 交叉编译 LVGL 9.5.0 + lvglcj 垫片 → lib/linux-arm64-sdl/（aarch64，SDL 后端）
#
# 用途：Pi Zero 2 W 上跑桌面（labwc / XWayland），LVGL 以 SDL 窗口形式显示，
#       不抢 DRM master；中文用 FreeType 加载系统字体。
#
# 依赖（与 DRM 版不同，这里只需要 SDL2 / FreeType 的 aarch64 头文件）：
#   sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu cmake ninja-build pkg-config
#   在 Pi 上：
#     sudo apt install libsdl2-dev libfreetype-dev
#   把它们的头文件与库拷回 WSL（只需一次）：
#     mkdir -p /root/aarch64-sdl/include /root/aarch64-sdl/lib
#     scp -r pi:/usr/include/SDL2          /root/aarch64-sdl/include/
#     scp -r pi:/usr/include/freetype2     /root/aarch64-sdl/include/
#     scp pi:/usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0 \
#         pi:/usr/lib/aarch64-linux-gnu/libfreetype.so.6 \
#         pi:/usr/lib/aarch64-linux-gnu/libz.so.1 \
#         pi:/usr/lib/aarch64-linux-gnu/libbz2.so.1.0 \
#         pi:/usr/lib/aarch64-linux-gnu/libpng16.so.16   /root/aarch64-sdl/lib/
#     cd /root/aarch64-sdl/lib && ln -sf libSDL2-2.0.so.0 libSDL2.so \
#       && ln -sf libfreetype.so.6 libfreetype.so \
#       && ln -sf libz.so.1 libz.so && ln -sf libbz2.so.1.0 libbz2.so \
#       && ln -sf libpng16.so.16 libpng.so
#
# 用法：./scripts/build-lvgl-pi-sdl.sh
#   环境变量（都可选）：
#     LVGL_DIR=/path/to/lvgl      复用已有源码
#     BUILD_DIR=/opt/build-pi-sdl 构建目录
#     SYSROOT=/root/aarch64-sdl   aarch64 的 SDL2/FreeType 头文件与库根目录
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_SRC="$ROOT/native/shim/lvgl_shim.c"
CONF="$ROOT/native/config/pi-sdl/lv_conf.h"
TOOLCHAIN="$ROOT/cmake/toolchain-aarch64.cmake"
LVGL_TAG="v9.5.0"
LVGL_DIR="${LVGL_DIR:-$ROOT/lvgl}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/pi-sdl}"
OUT_DIR="${OUT_DIR:-$ROOT/lib/linux-arm64-sdl}"
SHIM_BUILD="$BUILD_DIR/shim"
CROSS="aarch64-linux-gnu-"
SYSROOT="${SYSROOT:-/root/aarch64-sdl}"
INC_DIR="$SYSROOT/include"
LIB_DIR="$SYSROOT/lib"

for f in "$SHIM_SRC" "$CONF" "$TOOLCHAIN"; do
  [ -f "$f" ] || { echo "缺少文件：$f" >&2; exit 1; }
done

for d in "$INC_DIR/SDL2" "$INC_DIR/freetype2"; do
  [ -d "$d" ] || { echo "缺少 $d（按脚本头部注释从 Pi 上拷回来）" >&2; exit 1; }
done

if [ ! -d "$LVGL_DIR" ]; then
  echo "==> 克隆 LVGL $LVGL_TAG"
  git clone --depth 1 -b "$LVGL_TAG" https://gitcode.com/gh_mirrors/lvgl/lvgl.git "$LVGL_DIR"
fi

mkdir -p "$OUT_DIR" "$SHIM_BUILD"

echo "==> cmake 配置（aarch64 交叉，SDL 后端）"
cmake -B "$BUILD_DIR" -G Ninja -S "$LVGL_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DLV_BUILD_CONF_PATH="$CONF" \
  -DCMAKE_C_FLAGS="-I$INC_DIR -I$INC_DIR/freetype2" \
  -DCMAKE_CXX_FLAGS="-I$INC_DIR -I$INC_DIR/freetype2"

echo "==> 编译 liblvgl.a"
cmake --build "$BUILD_DIR"

echo "==> 编译 C 垫片 liblvglcjshim.a"
${CROSS}gcc -c -O2 -fPIC -Wall -Wextra \
  -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
  -I"$LVGL_DIR" -I"$(dirname "$CONF")" -I"$INC_DIR" -I"$INC_DIR/freetype2" \
  -o "$SHIM_BUILD/lvgl_shim.o" \
  "$SHIM_SRC"
${CROSS}ar rcs "$OUT_DIR/liblvglcjshim.a" "$SHIM_BUILD/lvgl_shim.o"

cp -f "$BUILD_DIR/lib/liblvgl.a" "$OUT_DIR/liblvgl.a" 2>/dev/null || \
  find "$BUILD_DIR" -name 'liblvgl.a' -exec cp -f {} "$OUT_DIR/" \;

echo "==> 完成：$OUT_DIR"
ls -l "$OUT_DIR"
${CROSS}readelf -h "$OUT_DIR/liblvgl.a" 2>/dev/null | grep -m1 Machine
echo
echo "仓颉侧交叉链接需要："
echo "  -L$LIB_DIR -lSDL2 -lfreetype"
echo "    （见 cjpm.toml 的 [target.aarch64-unknown-linux-gnu].link-option）"
