# qianzhen-skills

Personal [pi](https://github.com/earendil-works/pi-coding-agent) skill collection. Each top-level directory is one skill (`SKILL.md` + assets), designed to be cloned/symlinked into `~/.pi/agent/skills/`.

## Skills

### longrun

Long-haul (>24h) execution & monitoring patterns for pi: tmux process survival, mission-as-recovery-backbone, scheduled checks, checkpointed async lanes, and budget guardrails.

- Install: `ln -s "$PWD/longrun" ~/.pi/agent/skills/longrun`

### x-search

Complete read-only X (Twitter) client using the logged-in browser session from the [x-refresh](https://github.com/your/x-refresh) project (`~/x-refresh`). Search tweets/users, browse For You & Following timelines, open threads and replies, read profiles/media, bookmarks and likes. GraphQL queryIds are extracted live from x.com's JavaScript (cached 24h), so it survives X's rotation cycles.

- Depends on: `~/x-refresh/config.json` (cookies + proxy), `python3`, `curl`
- Install: `ln -s "$PWD/x-search" ~/.pi/agent/skills/x-search`

### qwen-image-gen

Generate images locally with Qwen-Image-2.1 (4-bit mlx-serve pack, Apple Silicon). Text-to-image, image-to-image, size/aspect/steps/seed control — served on `localhost:11234` with the OpenAI images API. Idempotent server boot for 16 GB machines (wired-limit check, `--max-resident-mem 0`, staged text encoder), a sync quick-gen script, and a detached `screen` driver with SSE step progress and OOM size-fallbacks for 1080P-class runs. Field-tested: 512x512/6 steps 43 s, 1080x1920/14 steps ~15 min on a 16 GB M1 Pro.

- Depends on: `~/mlx-serve` (feat/qwen-image-2.1 build), `~/.mlx-serve/models/ddalcu/Qwen-Image-2.1-MLX-Serve-4bit` (10.7 GB pack), `sysctl iogpu.wired_limit_mb=13312` (user-run sudo), `screen`
- Install: `ln -s "$PWD/qwen-image-gen" ~/.pi/agent/skills/qwen-image-gen`

## Install all

```bash
git clone https://github.com/shenlau/qianzhen-skills.git
for d in qianzhen-skills/*/; do ln -s "$PWD/$d" ~/.pi/agent/skills/$(basename "$d"); done
```