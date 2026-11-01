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
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLES="$ROOT/examples"

RUN_ARG=""
if [ "${1:-}" = "--run" ]; then
    RUN_ARG="${2:-all}"
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
cjpm build --cfg

BIN="$EXAMPLES/target/release/bin/main"
if [ -n "$RUN_ARG" ]; then
    "$BIN" "$RUN_ARG"
else
    echo "[build-example] 直接运行：$BIN all"
fi
