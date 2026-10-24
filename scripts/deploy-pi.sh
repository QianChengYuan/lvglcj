#!/usr/bin/env bash
# 部署 examples 产物到 Raspberry Pi Zero 2 W 并远程运行
# 用法：./scripts/deploy-pi.sh <demo>     # demo: hello|widgets|touch|image|canvas|perf
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO="${1:-hello}"
PI_HOST="${PI_HOST:-pi@raspberrypi.local}"
REMOTE_DIR="${REMOTE_DIR:-/home/pi}"

BIN="$ROOT/examples/target/release/bin/main"
if [ ! -x "$BIN" ]; then
  echo "找不到 $BIN，请先在 examples/ 执行 cjpm build（交叉编译）" >&2
  exit 1
fi

echo "==> scp -> $PI_HOST:$REMOTE_DIR/main"
scp "$BIN" "$PI_HOST:$REMOTE_DIR/main"

echo "==> 远程运行：./main $DEMO"
ssh "$PI_HOST" "chmod +x $REMOTE_DIR/main && $REMOTE_DIR/main $DEMO"
