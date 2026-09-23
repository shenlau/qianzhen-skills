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

## Install all

```bash
git clone https://github.com/shenlau/qianzhen-skills.git
for d in qianzhen-skills/*/; do ln -s "$PWD/$d" ~/.pi/agent/skills/$(basename "$d"); done
```