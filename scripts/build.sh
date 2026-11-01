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
#   bash scripts/build.sh --target aarch64-unknown-linux-gnu --backend drm
#
# --target 按目标三元组选库目录（cjpm 1.2.0 不支持 [target.<triple>.ffi.c]，只能脚本做）：
#   x86_64-w64-mingw32        → lib/windows-x64
#   x86_64-unknown-linux-gnu  → lib/linux-x64
#   aarch64-unknown-linux-gnu → lib/linux-arm64-sdl（--backend drm 时 lib/linux-arm64）
#
# 说明：
# - 已有的 $LVGLCJ_LIB_DIR 会被沿用（--lib-dir 可覆盖）；都没有才按平台猜。
# - 注入的是绝对路径：examples 是独立模块，cjpm 拿相对路径去根模块解析，
#   写 "lib/linux-x64" 时从 examples 里构建会找不到库。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 非登录 shell 不读 /etc/profile.d，cjpm/cjc 会报
#   cjpm: error while loading shared libraries: libcangjie-runtime.so
if [ -n "${CANGJIE_HOME:-}" ]; then
  for d in "$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative" "$CANGJIE_HOME/lib/linux_x86_64_cjnative"; do
    if [ -d "$d" ]; then
      case ":${LD_LIBRARY_PATH:-}:" in
        *":$d:"*) ;;
        *) export LD_LIBRARY_PATH="$d:${LD_LIBRARY_PATH:-}" ;;
      esac
    fi
  done
fi
LIB_DIR=""
TARGET=""
BACKEND="sdl"
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
    --target) TARGET="${2:-}"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --backend) BACKEND="${2:-}"; shift 2 ;;
    --backend=*) BACKEND="${1#*=}"; shift ;;
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

lib_dir_for_target() {
  case "$1" in
    x86_64-w64-mingw32) echo "lib/windows-x64" ;;
    x86_64-unknown-linux-gnu) echo "lib/linux-x64" ;;
    aarch64-unknown-linux-gnu)
      if [ "$2" = "drm" ]; then echo "lib/linux-arm64"; else echo "lib/linux-arm64-sdl"; fi ;;
    aarch64-apple-darwin) echo "lib/macos-arm64" ;;
    *)
      echo "未知目标三元组 '$1'（可用：x86_64-w64-mingw32 / x86_64-unknown-linux-gnu / aarch64-unknown-linux-gnu / aarch64-apple-darwin）" >&2
      exit 1 ;;
  esac
}

if [ -z "$LIB_DIR" ] && [ -n "$TARGET" ]; then
  LIB_DIR="$(lib_dir_for_target "$TARGET" "$BACKEND")"
fi
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

# cjc 交叉编译需要 SDK 里带目标平台的 stdlib 模块（modules/<arch>_<os>_cjnative），
# 官方 linux-x64 SDK 只带 linux_x86_64 / windows_x86_64 两套，缺 aarch64 时会报
#   error: failed to detect cangjie modules, reason: target library path is not exist
check_target_modules() {
  local t="$1" mod=""
  case "$t" in
    aarch64-unknown-linux-gnu) mod="linux_aarch64_cjnative" ;;
    x86_64-unknown-linux-gnu) mod="linux_x86_64_cjnative" ;;
    x86_64-w64-mingw32) mod="windows_x86_64_cjnative" ;;
    *) return 0 ;;
  esac
  if [ -n "${CANGJIE_HOME:-}" ] && [ ! -d "$CANGJIE_HOME/modules/$mod" ]; then
    echo "[build] 警告：$CANGJIE_HOME/modules/$mod 不存在，cjc 交叉编译会失败。" >&2
    echo "[build]       需要带目标平台 stdlib 模块的仓颉 SDK，或改用目标机原生编译。" >&2
  fi
}

host_triple() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) echo "aarch64-apple-darwin" ;;
    Darwin-x86_64) echo "x86_64-apple-darwin" ;;
    Linux-aarch64 | Linux-arm64) echo "aarch64-unknown-linux-gnu" ;;
    *) echo "x86_64-unknown-linux-gnu" ;;
  esac
}

CJPM_BUILD_ARGS=(build)
if [ "$RELEASE" -eq 1 ]; then CJPM_BUILD_ARGS+=(--release); fi
# 与宿主一致时不传 --target（cjpm 会打 "will be ignored" 告警）
if [ -n "$TARGET" ] && [ "$TARGET" != "$(host_triple)" ]; then
  check_target_modules "$TARGET"
  CJPM_BUILD_ARGS+=(--target "$TARGET")
fi
echo "==> cjpm ${CJPM_BUILD_ARGS[*]}"
cjpm "${CJPM_BUILD_ARGS[@]}"

if [ "$EXAMPLES" -eq 1 ]; then
  echo "==> examples: build-example.sh"
  EX_ARGS=()
  if [ -n "$TARGET" ]; then EX_ARGS+=(--target "$TARGET" --backend "$BACKEND"); fi
  "$ROOT/scripts/build-example.sh" ${EX_ARGS[@]+"${EX_ARGS[@]}"}
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
