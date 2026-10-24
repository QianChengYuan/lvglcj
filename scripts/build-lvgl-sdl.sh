#!/usr/bin/env bash
# 编译 LVGL 9.5.0 + lvglcj 垫片 → lib/linux-x64/（x86_64 ELF，SDL2 + WSLg）
#
# 已实测环境：Ubuntu 24.04 (WSL2)，gcc 13.3，cmake 3.28，ninja 1.11，SDL2 2.30
# 依赖：
#   sudo apt install build-essential cmake ninja-build pkg-config \
#                    libsdl2-dev libfreetype-dev libevdev-dev
#   （lv_conf.h 在非 Windows 分支开了 LV_USE_EVDEV=1，所以 libevdev-dev 必需）
#   WSLg 下跑窗口还要中文字体：sudo apt install fonts-noto-cjk
#
# 用法：./scripts/build-lvgl-sdl.sh
#   环境变量（都可选）：
#     LVGL_DIR=/path/to/lvgl      复用已有源码，省一次克隆
#     BUILD_DIR=/opt/build-sdl    构建目录（放原生盘比 /mnt/c 快很多）
#     OUT_DIR=...                 产物目录，默认 lib/linux-x64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM_SRC="$ROOT/native/shim/lvgl_shim.c"
CONF="$ROOT/native/config/sdl/lv_conf.h"   # 配置源（与 Windows 共用，内含 _WIN32 分支）
LVGL_TAG="v9.5.0"
LVGL_DIR="${LVGL_DIR:-$ROOT/lvgl}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/linux-x64}"
OUT_DIR="${OUT_DIR:-$ROOT/lib/linux-x64}"
SHIM_BUILD="$BUILD_DIR/shim"

[ -f "$SHIM_SRC" ] || { echo "找不到垫片源码：$SHIM_SRC" >&2; exit 1; }
[ -f "$CONF" ] || { echo "找不到配置源：$CONF" >&2; exit 1; }

if [ ! -d "$LVGL_DIR" ]; then
  echo "==> 克隆 LVGL $LVGL_TAG"
  git clone --depth 1 -b "$LVGL_TAG" https://gitcode.com/gh_mirrors/lvgl/lvgl.git "$LVGL_DIR"
fi

mkdir -p "$OUT_DIR" "$SHIM_BUILD"

echo "==> cmake 配置（x86_64 + SDL）"
# 注意：LVGL 9.5 的配置项叫 LV_BUILD_CONF_PATH（9.2 及以前才是 LV_CONF_PATH，
# 传错名字不会报错，只会静默使用默认 lv_conf.h，导致 SDL 后端被关掉）。
# FreeType（lv_conf.h 里 LV_USE_FREETYPE=1）的头文件要显式加进来，LVGL 的 CMake 不管这个。
FT_CFLAGS="$(pkg-config --cflags freetype2)"
cmake -B "$BUILD_DIR" -G Ninja -S "$LVGL_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DLV_BUILD_CONF_PATH="$CONF" \
  -DCMAKE_C_FLAGS="$FT_CFLAGS" -DCMAKE_CXX_FLAGS="$FT_CFLAGS"

echo "==> 编译 liblvgl.a"
cmake --build "$BUILD_DIR"

echo "==> 编译 C 垫片 liblvglcjshim.a"
# 垫片用 LV_CONF_INCLUDE_SIMPLE + -I 配置目录 找 lv_conf.h（与 CMake 传 LV_CONF_PATH 等价，
# 但省掉一层引号转义，跨平台更省心）
gcc -c -O2 -fPIC -Wall -Wextra \
  -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
  -I"$LVGL_DIR" -I"$(dirname "$CONF")" $FT_CFLAGS \
  -o "$SHIM_BUILD/lvgl_shim.o" \
  "$SHIM_SRC"
ar rcs "$OUT_DIR/liblvglcjshim.a" "$SHIM_BUILD/lvgl_shim.o"

cp -f "$BUILD_DIR/lib/liblvgl.a" "$OUT_DIR/liblvgl.a" 2>/dev/null || \
  find "$BUILD_DIR" -name 'liblvgl.a' -exec cp -f {} "$OUT_DIR/" \;

echo "==> 完成：$OUT_DIR"
ls -l "$OUT_DIR"
echo
echo "下一步："
echo "    export LVGLCJ_LIB_DIR=lib/linux-x64"
echo "    cd examples && cjpm build --cfg"
