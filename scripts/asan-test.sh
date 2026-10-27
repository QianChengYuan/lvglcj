#!/usr/bin/env bash
# 在 ASan 插桩库上跑单测（普通用例 + requires_display 用例）
#
# 前置：bash scripts/build-lvgl-asan.sh  （产出 .build/asan-lib，不入库）
#
# 会**临时**给 cjpm.toml 的 linux link-option 加 `-lasan`，退出时自动还原
# （trap EXIT，包含 ASan 报错退出）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${ASAN_LIB:-$ROOT/.build/asan-lib}"

if [ ! -f "$LIB/liblvgl.a" ]; then
  echo "缺少 $LIB/liblvgl.a" >&2
  echo "先跑：LVGL_SRC=/path/to/lvgl bash scripts/build-lvgl-asan.sh" >&2
  exit 1
fi

export LVGLCJ_LIB_DIR="$LIB"
# 无头环境靠 dummy 视频驱动建 display；有桌面时也可以覆盖成别的驱动
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-dummy}"
ASANLIB="$(gcc -print-file-name=libasan.so)"
if [ ! -e "$ASANLIB" ]; then
  echo "找不到 libasan（装 gcc 的 libasan 包）" >&2
  exit 1
fi

# cjpm 把 [target.*].link-option 直接交给 ld（不经 gcc 驱动），所以不能写
# -fsanitize=address（ld 会报 "-f may not be used without -shared"），只能显式 -lasan；
# 运行时再由 LD_PRELOAD 把 libasan 顶到最前面（否则 ASan 会因 "not first" 中止）。
BACKUP="$(mktemp)"
cp "$ROOT/cjpm.toml" "$BACKUP"
restore() { cp "$BACKUP" "$ROOT/cjpm.toml"; rm -f "$BACKUP"; }
trap restore EXIT

python3 - "$ROOT/cjpm.toml" <<'EOF'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = '[target.x86_64-unknown-linux-gnu]\nlink-option = "-lSDL2 -lfreetype"'
new = '[target.x86_64-unknown-linux-gnu]\nlink-option = "-lSDL2 -lfreetype -lasan"'
if old not in text:
    sys.exit("cjpm.toml 里没找到 x86_64-unknown-linux-gnu 的 link-option，脚本需要同步更新")
open(path, "w", encoding="utf-8").write(text.replace(old, new))
EOF

# detect_leaks=0：仓颉运行时的全局对象在退出时不算 GCRoot，LeakSanitizer 会误报一片
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:abort_on_error=1}"

cd "$ROOT"

echo "==> cjpm test（默认用例）"
LD_PRELOAD="$ASANLIB" cjpm test

echo "==> cjpm test（requires_display 用例，强制重绘，最容易走到绘制路径）"
LD_PRELOAD="$ASANLIB" cjpm test --include-tags=requires_display --exclude-tags=notag

echo "ASan 检查通过"
