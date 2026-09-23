#!/usr/bin/env bash
# 幂等启动 Qwen-Image-2.1 生成服务器,并等模型就绪
# 退出码: 0=ready  3=缺 wired limit(需用户 sudo)  4=服务器起不来/模型加载失败
set -uo pipefail
PORT="${QWEN_PORT:-11234}"
URL="http://127.0.0.1:$PORT"
MODEL="ddalcu/Qwen-Image-2.1-MLX-Serve-4bit"
SRVBIN="$HOME/mlx-serve/zig-out/bin/mlx-serve"
WANT_MB=13312

CUR=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
if [ "$CUR" -lt "$WANT_MB" ]; then
  echo "GPU 内存上限不足($CUR < $WANT_MB MB)。请用户执行(需密码,重启后失效):"
  echo "  sudo sysctl iogpu.wired_limit_mb=$WANT_MB"
  exit 3
fi
[ -x "$SRVBIN" ] || { echo "未找到 $SRVBIN,部署状态看 ~/mlx-serve/DEPLOY.md"; exit 4; }

if ! curl -sf "$URL/health" >/dev/null 2>&1; then
  "$SRVBIN" serve --port "$PORT" \
    --max-resident-mem 0 --os-reserve-gib 0 --skip-mem-preflight \
    >>/tmp/mlxserve-qwenimage.log 2>&1 &
  for i in $(seq 1 60); do
    curl -sf "$URL/health" >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -sf "$URL/health" >/dev/null 2>&1 || { echo "server 起不来,看 /tmp/mlxserve-qwenimage.log"; exit 4; }

curl -s -m 600 "$URL/v1/load-model" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\"}" >/dev/null 2>&1
for i in $(seq 1 600); do
  ST=$(curl -s "$URL/v1/models" | python3 -c \
    "import sys,json;d=json.load(sys.stdin)['data'];print(next((m['state'] for m in d if 'MLX-Serve' in m['id'] or 'qwen' in m['id'].lower()),'none'))" 2>/dev/null)
  [ "$ST" = "ready" ] && { echo "READY: $MODEL (port $PORT)"; exit 0; }
  [ "$ST" = "failed" ] && { echo "模型加载失败,看 /tmp/mlxserve-qwenimage.log"; exit 4; }
  sleep 2
done
echo "模型从未 ready"; exit 4