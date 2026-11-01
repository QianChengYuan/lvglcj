#!/usr/bin/env bash
# 一键构建 examples（Linux / WSL）：
#   - 自动挑预编译库目录并注入 LVGLCJ_LIB_DIR（不设这个变量 cjpm 会报
#     can not find the library 'lvgl' which is listed in 'ffi.c' field）
#   - cjpm build --cfg
#   - LD_LIBRARY_PATH 里补上仓颉运行时（非登录 shell 下 /etc/profile.d 不生效）
#
# 用法：
#   ./scripts/build-example.sh                 # 只构建
#   ./scripts/build-example.sh --run all       # 构建后直接跑 `main all`
#   LIB_DIR=lib/linux-arm64-sdl ./scripts/build-example.sh
#   ./scripts/build-example.sh --target aarch64-unknown-linux-gnu --backend sdl
#
# --target 按目标三元组选库目录（cjpm 1.2.0 不支持 [target.<triple>.ffi.c]，只能脚本做）：
#   x86_64-w64-mingw32        → lib/windows-x64
#   x86_64-unknown-linux-gnu  → lib/linux-x64
#   aarch64-unknown-linux-gnu → lib/linux-arm64-sdl（--backend drm 时 lib/linux-arm64）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLES="$ROOT/examples"

RUN_ARG=""
TARGET=""
BACKEND="sdl"
while [ $# -gt 0 ]; do
    case "$1" in
        --run) RUN_ARG="${2:-all}"; shift 2 ;;
        --target) TARGET="${2:-}"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        --backend) BACKEND="${2:-}"; shift 2 ;;
        --backend=*) BACKEND="${1#*=}"; shift ;;
        *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

lib_dir_for_target() {
    case "$1" in
        x86_64-w64-mingw32) echo "lib/windows-x64" ;;
        x86_64-unknown-linux-gnu) echo "lib/linux-x64" ;;
        aarch64-unknown-linux-gnu)
            if [ "$2" = "drm" ]; then echo "lib/linux-arm64"; else echo "lib/linux-arm64-sdl"; fi ;;
        aarch64-apple-darwin) echo "lib/macos-arm64" ;;
        *) echo "未知目标三元组 '$1'" >&2; exit 1 ;;
    esac
}

if [ -z "${LIB_DIR:-}" ] && [ -n "$TARGET" ]; then
    LIB_DIR="$(lib_dir_for_target "$TARGET" "$BACKEND")"
fi
if [ -z "${LIB_DIR:-}" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) LIB_DIR=lib/macos-arm64 ;;
        Linux-aarch64 | Linux-arm64) LIB_DIR=lib/linux-arm64-sdl ;;
        *) LIB_DIR=lib/linux-x64 ;;
    esac
fi
export LVGLCJ_LIB_DIR="$ROOT/$LIB_DIR"
echo "[build-example] LVGLCJ_LIB_DIR=$LVGLCJ_LIB_DIR"

if [ -n "${CANGJIE_HOME:-}" ]; then
    export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/lib/linux_x86_64_cjnative:${LD_LIBRARY_PATH:-}"
fi

cd "$EXAMPLES"
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST_TRIPLE=aarch64-apple-darwin ;;
    Darwin-x86_64) HOST_TRIPLE=x86_64-apple-darwin ;;
    Linux-aarch64 | Linux-arm64) HOST_TRIPLE=aarch64-unknown-linux-gnu ;;
    *) HOST_TRIPLE=x86_64-unknown-linux-gnu ;;
esac
if [ -n "$TARGET" ] && [ "$TARGET" != "$HOST_TRIPLE" ]; then
    if [ "$TARGET" = "aarch64-unknown-linux-gnu" ] && [ -z "${LVGLCJ_AARCH64_SDL_LIB:-}" ]; then
        echo "[build-example] 交叉到 aarch64 需要 LVGLCJ_AARCH64_SDL_LIB（aarch64 的 SDL2/FreeType 库目录）"
    fi
    if [ -n "${CANGJIE_HOME:-}" ] && [ ! -d "$CANGJIE_HOME/modules/linux_aarch64_cjnative" ]         && [ "$TARGET" = "aarch64-unknown-linux-gnu" ]; then
        echo "[build-example] 警告：$CANGJIE_HOME/modules/linux_aarch64_cjnative 不存在，cjc 交叉编译会失败" >&2
    fi
    cjpm build --cfg --target "$TARGET"
else
    cjpm build --cfg
fi

BIN="$EXAMPLES/target/release/bin/main"
if [ -n "$RUN_ARG" ]; then
    "$BIN" "$RUN_ARG"
else
    echo "[build-example] 直接运行：$BIN all"
fi
