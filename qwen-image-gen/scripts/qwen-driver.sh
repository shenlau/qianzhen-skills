#!/usr/bin/env bash
# 大图/长时生成驱动 — 配合 screen 脱离会话跑:
#   screen -dmS qwengen bash qwen-driver.sh /tmp/prompt.txt 1080x1920 14 704x1248 544x960
# 参数: <提示词文件> <尺寸> [步数=14] [备选尺寸1] [备选尺寸2] ...
# 行为: SSE 每步进度 -> /tmp/qwen_state.txt;内存监控 -> /tmp/qwen_mem.log;
#       失败/OOM 自动沿备选尺寸降级(每次先确保服务器活着,自动重启);
#       产物 -> /tmp/portrait-<尺寸>-<步数>.png + 拷贝 QWEN_OUT(默认 ~/Desktop/portrait-vertical.png)
set -uo pipefail
exec >>/tmp/qwen_state.txt 2>&1
SHELLDIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="${1:?用法: qwen-driver.sh <提示词文件> <尺寸> [步数] [备选尺寸...]}"
SIZE="${2:?缺尺寸,如 1080x1920}"
STEPS="${3:-14}"
shift $(($# < 3 ? 2 : 3)) || true
FALLBACKS=("$@")
URL="http://127.0.0.1:${QWEN_PORT:-11234}"
OUT="${QWEN_OUT:-$HOME/Desktop/portrait-vertical.png}"
ts() { date +%H:%M:%S; }
log() { echo "[$(ts)] $*"; }

(while :; do echo "[$(ts)] free:$(memory_pressure 2>/dev/null | grep -o '[0-9]*%') $(ps aux | grep '[m]lx-serve serve' | awk '{printf "cpu=%s%%", $3}')" >> /tmp/qwen_mem.log; sleep 20; done) &
MON=$!

ensure_server() {  # 幂等:活着只做 load-model 确认;挂了重启
  curl -sf "$URL/health" >/dev/null 2>&1 || {
    log "server down - reboot"
    bash "$SHELLDIR/qwen-serve.sh" >>/tmp/qwen_state.txt 2>&1 && return 0 || return 1
  }
  curl -s -m 600 "$URL/v1/load-model" -H 'Content-Type: application/json' \
    -d '{"model":"ddalcu/Qwen-Image-2.1-MLX-Serve-4bit"}' >/dev/null 2>&1
  for i in $(seq 1 300); do
    ST=$(curl -s "$URL/v1/models" | python3 -c \
      "import sys,json;d=json.load(sys.stdin)['data'];print(next((m['state'] for m in d if 'MLX-Serve' in m['id'] or 'qwen' in m['id'].lower()),'none'))" 2>/dev/null)
    [ "$ST" = "ready" ] && { log "model ready (poll $i)"; return 0; }
    sleep 2
  done
  log "model never ready"; return 1
}
gen() {  # <size>
  local size="$1" out="/tmp/portrait-$1-$STEPS.png"
  rm -f /tmp/genfinal.json; touch "$PROMPT_FILE" || { log "no prompt file"; return 9; }
  log "=== gen $size steps=$STEPS ==="
  python3 - "$size" "$STEPS" "$PROMPT_FILE" <<'PY'
import json, sys, time, urllib.request
size, steps, pfile = sys.argv[1:4]
prompt = open(pfile).read()
req = {"model":"ddalcu/Qwen-Image-2.1-MLX-Serve-4bit","prompt":prompt,
       "size":size,"steps":int(steps),"seed":7,"stream":True}
r = urllib.request.Request("http://127.0.0.1:11234/v1/images/generations",
        data=json.dumps(req).encode(), headers={"Content-Type":"application/json"})
t0 = time.time()
with urllib.request.urlopen(r, timeout=3300) as resp:
    for raw in resp:
        ln = raw.decode("utf-8","replace").strip()
        if not ln.startswith("data:"): continue
        if '"b64_json"' in ln:
            open("/tmp/genfinal.json","w").write(ln[6:])
            print(f"[{time.time()-t0:.0f}s] FINAL len={len(ln)}")
            break
        if '"progress"' in ln:
            print(f"[{time.time()-t0:6.0f}s] {ln}", flush=True)
PY
  [ -f /tmp/genfinal.json ] || { log "gen $size produced no image"; return 1; }
  python3 - "$out" <<'PY'
import json, base64, struct, sys
b = base64.b64decode(json.load(open("/tmp/genfinal.json"))["data"][0]["b64_json"])
w, h = struct.unpack(">II", b[16:24])
open(sys.argv[1],"wb").write(b); print(f"PNG {w}x{h} {len(b)//1024}KB")
PY
  [ $? -eq 0 ] && { cp "$out" "$OUT"; log "SAVED $out (-> $OUT)"; return 0; }
  return 1
}

log "DRIVER START: size=$SIZE steps=$STEPS fallbacks=${FALLBACKS[*]:-none}"
[ -f "$PROMPT_FILE" ] || { log "no prompt file: $PROMPT_FILE"; kill $MON; exit 1; }
ensure_server || { kill $MON; exit 1; }
FINAL=""
if gen "$SIZE"; then
  FINAL="/tmp/portrait-$SIZE-$STEPS.png"
else
  for FB in "${FALLBACKS[@]:-}"; do
    [ -z "$FB" ] && continue
    ensure_server || break
    if gen "$FB"; then FINAL="/tmp/portrait-$FB-$STEPS.png"; break; fi
  done
fi
kill "$MON" 2>/dev/null
log "DRIVER DONE: ${FINAL:-ALL FAILED}"