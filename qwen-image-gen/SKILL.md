---
name: qwen-image-gen
description: "用本机已部署的 Qwen-Image-2.1 mlx-serve 服务器(端口 11234,4-bit 包,16GB M1 Pro 实测)生成图片:文生图、img2img、改参数重生成、指定尺寸/比例/步数/种子。用户要求'生成图片/出图/画一张/文生图/Qwen-Image 生图'时调用。Generate images locally with Qwen-Image-2.1 on this Mac (txt2img, img2img, size/aspect/steps/seed control)."
license: Apache-2.0
---

# Qwen-Image-2.1 本地生图(mlx-serve)

已部署在本机:4-bit 包 10.67GB 开服务器加载,峰值 ~10GB,16GB M1 Pro(需 `iogpu.wired_limit_mb=13312`)可跑。
完整部署/重建/转换手册见 `~/mlx-serve/DEPLOY.md`(不是本技能范围,出问题才去读)。

## 硬件参数标尺(16GB M1 Pro 实测)

| 尺寸 | tokens | 每步 | 全程 |
|---|---|---|---|
| 512×512 | 1024 | ~3-4s | 6步 43s(含首次编译+编码器读盘) |
| 512×896 | 1568 | ~6s | 8步 ~1.5 分钟 |
| 1080×1920(→1088×1920) | 8160 | **~60s** | 14步 **~15 分钟** |

- 尺寸规则:任意 `WxH` 自动归到 **16 的倍数、上限 2048**(`1920x1080`→`1920x1088`);比例从提示词里读(见"9:16"→竖、16:9→横)
- token 每 ×4,单步耗时约 ×15(注意力平方项)
- **先草稿后定稿**:512×896/8 步选构图,满意再上 1080P+14~20 步
- `steps` 生成质量够了用 14-20;省略默认 40(这台机器太慢)
- 负向提示词(CFG)每步两次前向,时间 ×2,大尺寸慎用;`seed` 固定可复现

## 使用流程

### 0. 前置检查(每次)

```bash
sysctl -n iogpu.wired_limit_mb   # 必须 = 13312;重启后失效,不足时引导用户跑:
# sudo sysctl iogpu.wired_limit_mb=13312   ← 需要用户输密码,助手无法代输
```

### 1. 起服务器(health 探活可跳过)

```bash
bash ~/.pi/agent/skills/qwen-image-gen/scripts/qwen-serve.sh
# 幂等:活着不动,没活则起并等模型 enrich ready(标错即返回非 0)
# 内存不够时先引导用户退出 Chrome 等大应用
```

必带三个参数的原理(16GB 机器缺一不可):`--max-resident-mem 0`(默认 9.5GB 上限 < 模型 9.94GB)、`--os-reserve-gib 0`(默认扣 2GB 预留)、`--skip-mem-preflight`(预检保守,按实测峰值放行)。

### 2. 生成

**A. 快速/中小图**(≤1024 宽,同步等结果):

```bash
bash ~/.pi/agent/skills/qwen-image-gen/scripts/qwen-gen.sh "提示词" [512x512] [steps] [seed] [out.png]
# 环境变量:QWEN_NEG="负向提示词" 自动开 CFG(guidance 默认 4,可用 QWEN_GUID 覆盖)
```

**B. 大图/长时间**(`screen` 脱离会话跑,免得工具调用被用户中断就全挂):

```bash
# 1) 把提示词写进文件
# 2) 起驱动(参数:提示词文件 尺寸 步数 备选尺寸1 备选尺寸2 …)
screen -dmS qwengen bash ~/.pi/agent/skills/qwen-image-gen/scripts/qwen-driver.sh /tmp/prompt.txt 1080x1920 14 704x1248 544x960
# 3) 用短调用轮询进度(别用长 sleep,用户可能中断;中断也不影响 screen 里的任务)
tail -3 /tmp/qwen_state.txt; tail -3 /tmp/qwen/qwen_mem.log
```

驱动特性(实测验证过):SSE 每步进度(`data: {"type":"progress","step":N,"total":M}`)、OOM/失败按备选尺寸自动降级、产物自动拷 `~/Desktop/portrait-vertical.png`、完成后写 `DRIVER DONE: <png>`。

### 3. 交付

- PNG 默认落 `~/Desktop/`;用 PNG 头校验宽高(`struct.unpack(">II", b[16:24])`)
- 完整会话末尾**保留服务器运行**(下次生成免加载,~15s);用户明确不用了执行 `pkill -f "mlx-serve serve"` 释放 10GB

## 常见坑(都以实錸过)

1. **重启后 wired limit 回 0**:模型加载报 `Not enough free memory` / preflight 拒绝 → 99% 是它,引导用户跑 sudo
2. **后台进程被工具调用牵连**:长任务一律放 `screen`(`screen -dmS 名字 bash script`);`pkill -f mlx-serve` 会连坐同驱动脚本里的服务器,先杀驱动 bash 再动服务器
3. **图片编码器按请求 stage-in**(读盘 ~5GB/次,首步前骤停 10-60s 属正常,GPU 利用率期间就是低的)
4. OOM 信号:server 进程消失 / 返回 503 → 降尺寸或请用户关应用后重试;10.67GB 包下限是 544×960
5. 模型 ID 的 `Qwen` 是大写,写脚本时 `id` 判断别用小写 `qwen`
6. 服务器 7×24 跑过:别并发多请求(16GB 会崩);一次一张