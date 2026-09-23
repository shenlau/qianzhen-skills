#!/usr/bin/env bash
# 快速同步型生成(中小图);大长图用 qwen-driver.sh(screen 脱离跑)
# 用法: qwen-gen.sh "提示词" [512x512] [steps] [seed] [out.png]
# 环境变量:
#   QWEN_NEG   负向提示词(设置后自动 CFG, guidance=QWEN_GUID, 默认 4.0)
#   QWEN_PORT  端口,默认 11234
set -euo pipefail
PORT="${QWEN_PORT:-11234}"
MODEL="ddalcu/Qwen-Image-2.1-MLX-Serve-4bit"
PROMPT="${1:?用法: qwen-gen.sh \"提示词\" [512x512] [步数] [seed] [输出.png]}"
SIZE="${2:-512x512}"
STEPS="${3:-20}"
SEED="${4:-42}"
OUT="${5:-$HOME/Desktop/qwen-$(date +%m%d-%H%M%S).png}"

bash "$(dirname "$0")/qwen-serve.sh" || exit $?

python3 - "$PROMPT" "$SIZE" "$STEPS" "$SEED" "$OUT" "$PORT" "${QWEN_NEG:-}" "${QWEN_GUID:-}" <<'PY'
import json, sys, urllib.request, base64, time, struct
prompt, size, steps, seed, out, port, neg, guid = sys.argv[1:9]
req = {"model": "ddalcu/Qwen-Image-2.1-MLX-Serve-4bit", "prompt": prompt,
       "size": size, "steps": int(steps), "seed": int(seed)}
if neg:
    req["negative_prompt"] = neg
    req["guidance_scale"] = float(guid) if guid else 4.0
r = urllib.request.Request(f"http://127.0.0.1:{port}/v1/images/generations",
                           data=json.dumps(req).encode(),
                           headers={"Content-Type": "application/json"})
t0 = time.time()
with urllib.request.urlopen(r, timeout=3600) as resp:
    d = json.load(resp)
b = base64.b64decode(d["data"][0]["b64_json"])
open(out, "wb").write(b)
w, h = struct.unpack(">II", b[16:24])
cfg = f" CFG={req['guidance_scale']}(两前向/步)" if neg else ""
print(f"OK {w}x{h} / {steps}步{cfg} / {time.time()-t0:.0f}s\n  -> {out}")
PY