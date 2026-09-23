---
name: x-search
description: "Complete read-only X (Twitter) client using the logged-in browser session from the x-refresh project (~/x-refresh). Search tweets/users, browse For You & Following timelines, open threads and replies, read any profile's posts/replies/media, bookmarks and likes. Use whenever the user asks to do anything on X/Twitter: 搜索推文、浏览时间线/为你推荐/关注、看帖子回复、查某人的推文、书签点赞。"
license: MIT (txid generator ported from iSarabjitDhiman/XClientTransaction; re-anchor pattern after agentic-x)
---

# X client via the x-refresh session

One CLI replaces everyday X-in-the-browser reading. Credentials/proxy come from
`~/x-refresh/config.json` (override `--config`). Zero pip dependencies; all
traffic goes through that project's proxy via `curl` (robust retries).

## Command

```bash
python3 ~/.pi/agent/skills/x-search/scripts/x_search.py <command> [options]
```

## Commands

| Command | What it does |
|---|---|
| `search "query" [--latest/--people/--product P]` | tweet/user search (Top by default; supports all X operators) |
| `home [--following]` | your home timeline — For You (default) or Following |
| `tweet <url-or-id>` | a post + its thread: ancestors, focal, replies |
| `user <handle> [--media/--replies]` | a profile's posts / media / replies (likes empty unless it is you) |
| `bookmarks` | your bookmarked posts |
| `likes` | your liked posts |

Legacy shorthand: `x_search.py "query"` → `x_search.py search "query"`.

Shared options: `-n N` (per page, 1–100, default 20) · `--pages N` (cursor
pagination, max 5, ~2.5s pacing) · `--json` · `--no-cache` (re-extract
runtime) · `-v` (diagnostics).

All commands print human-readable output with author (✔ verified), local time
+ age, link, full text (long-form notes included) and view/like/RT/reply
stats. `--json` emits the same data machine-readable — prefer it for
post-processing.

## Query recipes (search)

- Latest buzz: `"DLSS 5" --latest`
- High-signal: `"RTX 6090" min_faves:100 --latest`
- One account: `from:nvidia DLSS since:2026-09-15`
- No replies/links noise: `"GPT-6" -filter:replies -filter:links`
- Windowed: `"芯片禁令" since:2026-09-20 until:2026-09-23 lang:zh`
- Users: `--people` · media only: `filter:media filter:videos`

Default product is `Top`; for "最新消息/舆情" pick `--latest`.

## How it stays alive against X's countermeasures

- **queryId rotation (every 2–4 weeks):** every op's GraphQL queryId and
  feature switches are extracted **live** from x.com's current JavaScript:
  main.js first, then the lazily-loaded chunk index embedded in the home
  page (webpack `.u=e=>` maps), swept in parallel with early stop. Cached
  24h in `~/.cache/x-search/state.json`. On a 404 the cache is dropped, the
  runtime is re-extracted once, and the request auto-retries.
- **transaction-id gate (SearchTimeline):** search additionally needs a
  per-request `x-client-transaction-id`, single-use, mixed from method+path+time;
  minted locally per call (algorithm ported verbatim, MIT, from
  iSarabjitDhiman/XClientTransaction — inputs from the home page: verification
  meta, loading-anim SVG frames, ondemand.s indices). Other commands
  (home/tweet/user/bookmarks/likes) stay off that gate and deliberately send
  no such header.
- **"Following" tab uses HomeLatestTimeline**; "For You" uses HomeTimeline.
- Profile **replies** use the un-gated `UserRepliesTimeline`; the interleaved
  `UserTweetsAndReplies` op is behind the transaction-id wall and unused.
- Likes are only yours: X made other accounts' likes private (a request
  against someone else returns empty, not an error).

## Failure modes (exit codes)

- **2** cookie expiry / bad config → user must refresh auth_token/ct0 in
  `~/x-refresh/config.json` from their browser (no auto-fix).
- **3** x.com no longer serves an ingredient the extractor needs (X redeploy):
  the extraction regexes need a re-port. `--no-cache` rules out stale cache.
- **4** a freshly minted transaction-id was rejected (404 after retry): X
  changed the generation algorithm — re-port from upstream.
- **5** rate-limited (429): the message carries the bucket reset time.
  SearchTimeline ≈ 50 requests/15 min; one search page = 1 request. Never
  retry-loop a 429; lower `--pages`, wait, or batch queries.
- **6** request/pagination failure — retrying once usually passes; decaying
  proxies sometimes yield curl-level noise which the script already retries.

## Good practice

- Follow pagination with `--pages`, not repeated calls (costs one request per
  page either way, but pacing is built in).
- `search --latest` + `since:` is the fastest way to "X 上关于 <X> 的最新
  消息"; synthesize then and cite `https://x.com/<user>/status/<id>` links.
- For conversations start from `tweet <url>` — the parser separates the
  ancestor chain, the focal post and replies; more replies come via `--pages`.
- The runtime cache refresh is automatic (24h TTL); only reach for
  `--no-cache` after repeated 404/parse failures on different commands.