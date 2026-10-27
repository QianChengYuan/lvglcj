#!/usr/bin/env bash
# 编 ASan 插桩版 LVGL + 垫片 → .build/asan-lib（不入库，只给内存检查用）
#
# 为什么不直接用 lib/linux-x64 的预编译库：
#   ASan 只能发现**插桩代码**里的越界/悬垂访问。预编译的 liblvgl.a 没有
#   -fsanitize=address，LVGL 内部读到已释放内存时 ASan 什么都看不到。
#   （实测：拿未插桩的 .a 跑 Line 用例、故意注入 UAF，ASan 毫无反应；
#     换成这里编的库后立刻报 heap-use-after-free @ lv_line.c:226。）
#
# 用法：
#   LVGL_SRC=/path/to/lvgl bash scripts/build-lvgl-asan.sh
#   bash scripts/asan-test.sh
#
# 环境变量：
#   LVGL_SRC  LVGL v9.5.0 源码目录（默认 $ROOT/../lvgl-ref）
#   CONF      配置源（默认 native/config/sdl/lv_conf.h）
#   BUILD     构建目录（默认 .build/lvgl-asan）
#   OUT       产物目录（默认 .build/asan-lib）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LVGL_SRC="${LVGL_SRC:-$ROOT/../lvgl-ref}"
CONF="${CONF:-$ROOT/native/config/sdl/lv_conf.h}"
BUILD="${BUILD:-$ROOT/.build/lvgl-asan}"
OUT="${OUT:-$ROOT/.build/asan-lib}"

if [ ! -f "$LVGL_SRC/CMakeLists.txt" ]; then
  echo "找不到 LVGL 源码：$LVGL_SRC" >&2
  echo "用法：LVGL_SRC=/path/to/lvgl（v9.5.0）bash scripts/build-lvgl-asan.sh" >&2
  exit 1
fi
if [ ! -f "$CONF" ]; then
  echo "找不到配置源：$CONF" >&2
  exit 1
fi

FT_CFLAGS="$(pkg-config --cflags freetype2)"

cmake -B "$BUILD" -G Ninja -S "$LVGL_SRC" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF \
  -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DLV_BUILD_CONF_PATH="$CONF" \
  -DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g -O1 $FT_CFLAGS"
cmake --build "$BUILD" -j"$(nproc)"

mkdir -p "$OUT"
gcc -c -O1 -g -fsanitize=address -fno-omit-frame-pointer \
  -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
  -I"$LVGL_SRC" -I"$(dirname "$CONF")" $FT_CFLAGS \
  -o "$BUILD/shim-asan.o" "$ROOT/native/shim/lvgl_shim.c"
ar rcs "$OUT/liblvglcjshim.a" "$BUILD/shim-asan.o"
cp "$BUILD/lib/liblvgl.a" "$OUT/"

echo "ASan 插桩库就绪：$OUT"
echo "下一步：bash scripts/asan-test.sh"
