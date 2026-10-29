#!/usr/bin/env bash
# 一键构建（Linux / macOS / WSL）
#
# 目的：`cjpm.toml` 里 `[ffi.c] path = "${LVGLCJ_LIB_DIR}"` 不支持默认值
# （cjpm 1.2.0 没有 ${VAR:-默认} 语法），新克隆的仓库不设变量就构建失败。
# 本脚本自动选预编译库目录、注入环境变量，再交给 cjpm。
#
# 用法：
#   bash scripts/build.sh                    # 库，debug
#   bash scripts/build.sh --release          # 库，release
#   bash scripts/build.sh --examples         # 库 + examples（--cfg）
#   bash scripts/build.sh --test             # 库 + 单元测试
#   bash scripts/build.sh --display-tests    # requires_display 用例（SDL dummy 驱动）
#   bash scripts/build.sh --lib-dir lib/linux-arm64-sdl
#
# 说明：
# - 已有的 $LVGLCJ_LIB_DIR 会被沿用（--lib-dir 可覆盖）；都没有才按平台猜。
# - 注入的是绝对路径：examples 是独立模块，cjpm 拿相对路径去根模块解析，
#   写 "lib/linux-x64" 时从 examples 里构建会找不到库。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR=""
EXAMPLES=0
RELEASE=0
RUN_TEST=0
DISPLAY_TESTS=0

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --lib-dir) LIB_DIR="${2:-}"; shift 2 ;;
    --lib-dir=*) LIB_DIR="${1#*=}"; shift ;;
    --examples) EXAMPLES=1; shift ;;
    --release) RELEASE=1; shift ;;
    --test) RUN_TEST=1; shift ;;
    --display-tests) DISPLAY_TESTS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 1 ;;
  esac
done

detect_lib_dir() {
  case "$(uname -s)" in
    # macOS 暂无预编译产物；保留分支只为让报错里能列出可选目录，请用 --lib-dir 指定
    Darwin) echo "lib/macos-arm64" ;;
    *)
      case "$(uname -m)" in
        aarch64|arm64)
          # 桌面上跑用 SDL 版；只有 DRM 版时才退回
          if [ -f "$ROOT/lib/linux-arm64-sdl/liblvgl.a" ]; then
            echo "lib/linux-arm64-sdl"
          else
            echo "lib/linux-arm64"
          fi
          ;;
        *) echo "lib/linux-x64" ;;
      esac
      ;;
  esac
}

if [ -z "$LIB_DIR" ]; then
  LIB_DIR="${LVGLCJ_LIB_DIR:-$(detect_lib_dir)}"
fi

case "$LIB_DIR" in
  /*) LIB_ABS="$LIB_DIR" ;;
  *) LIB_ABS="$ROOT/$LIB_DIR" ;;
esac

for f in liblvgl.a liblvglcjshim.a; do
  if [ ! -f "$LIB_ABS/$f" ]; then
    echo "缺少 $LIB_ABS/$f" >&2
    echo "可选目录：$(ls -d "$ROOT"/lib/*/ 2>/dev/null | xargs -n1 basename | sed 's#^#lib/#' | tr '\n' ' ')" >&2
    exit 1
  fi
done

export LVGLCJ_LIB_DIR="$LIB_ABS"
echo "LVGLCJ_LIB_DIR = $LIB_ABS"

echo "==> cjpm build ${RELEASE:+--release}"
if [ "$RELEASE" -eq 1 ]; then
  cjpm build --release
else
  cjpm build
fi

if [ "$EXAMPLES" -eq 1 ]; then
  echo "==> examples: cjpm build --cfg"
  ( cd "$ROOT/examples" && cjpm build --cfg )
fi

if [ "$RUN_TEST" -eq 1 ]; then
  echo "==> cjpm test"
  cjpm test
fi

if [ "$DISPLAY_TESTS" -eq 1 ]; then
  # 无头环境（CI）用 dummy 视频驱动；有桌面时它会去开真窗口
  export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-dummy}"
  echo "==> cjpm test --include-tags=requires_display --exclude-tags=notag"
  cjpm test --include-tags=requires_display --exclude-tags=notag
fi

echo "全部完成"
