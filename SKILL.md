---
name: bilibili-transcript
description: 提取B站(bilibili)视频并生成可信文字稿。处理 b23.tv 短链或 BV 链接：解析短链、yt-dlp 下载视频（付费/高画质视频用本机浏览器 Cookie 借登录态，macOS Safari 不可用；Cookie 出错时中止并要求用户提供可用的浏览器环境，不猜测不降级）、优先获取站内字幕（零成本路径）、无字幕时本地 mlx-whisper 转写、ASR 智能校审（先核数后改字）、生成口述整理稿。触发词：B站、提取视频、下载视频、文字稿、字幕、转写、校对、口述稿、bilibili、transcript。Use when the user gives a Bilibili video URL and wants the video file, a transcript, subtitles, or a reading-ready oral-history draft.
---

# B站视频提取与文字稿生成

把 B 站链接变成三层产物：**视频文件 → 可信文字稿（校订版）→ 口述整理稿（可阅读版）**。
本 skill 是本机已验证流水线的操作手册（首次端到端验证：2026-11-02，12min40s 视频全流程通过）。

## 环境依赖

| 工具 | 用途 | 缺失时 |
|---|---|---|
| yt-dlp | 下载视频/字幕 | `brew install yt-dlp` |
| ffmpeg | 音视频处理 | `brew install ffmpeg` |
| uv | 起 mlx-whisper 环境 | `brew install uv` 或用官方安装脚本 |

mlx-whisper 模型（whisper-large-v3-turbo，约 1.5G）首次转写时自动下载到 `~/.cache/huggingface/hub/blobs/`，之后复用免下载。可先用 `scripts/extract.sh <URL> [输出目录]` 跑通确定性环节，校审与整理稿为编辑环节（见步骤 6/7）。

## 步骤 1：解析短链

```bash
curl -sI "https://b23.tv/xxxx" | grep -i ^location   # Location 头里取 BV 号
```

短链也可直接丢给 yt-dlp，无需手动解析；解析只为获得干净的 BV 链接。

## 步骤 2：下载视频

```bash
yt-dlp -F URL                    # 先列清晰度再决定
yt-dlp -f "bv*+ba/b" --merge-output-format mp4 -o "downloads/%(title).80s.%(ext)s" URL
```

清晰度阶梯：未登录 720P → 普通登录 1080P 高清 → 大会员 1080P 高码率/4K/HDR。

**付费视频 / 高画质视频（用户规则，必须遵守）：**

- 用**本机浏览器**做下载入口——浏览器持有登录态/会员态，yt-dlp 直接借其 Cookie：
  ```bash
  yt-dlp --cookies-from-browser Edge URL     # Edge/Chrome/Firefox 均可
  ```
- macOS 上 **Safari 有容器权限墙**（`Operation not permitted`），直接排除，不要浪费时间尝试。
- **Cookie 读取失败 / 该浏览器未登录 / 无对应会员权限时：中止，并要求用户提供可用的浏览器环境**——指明已登录的浏览器、补登录会员账号、或从浏览器导出 `cookies.txt` 后改用 `--cookies cookies.txt`。**不要猜测哪个浏览器登录了，不要静默降级到低画质硬试。**

## 步骤 3：字幕优先（零成本路径先走）

```bash
yt-dlp --list-subs URL
```

- B 站 **AI 字幕需登录态才能查询**。用浏览器 Cookie 调播放器 API 确认：
  `https://api.bilibili.com/x/player/v2?cid=<cid>&aid=<aid>` → 看 `ai_status` 与 `subtitle.list`
- 有字幕 → 直接拉 srt（`--write-subs --sub-langs ".*" --skip-download`），**跳过整个本地转写环节**
- `ai_status: None` 属正常：并非所有视频都有 AI 字幕，查完再决定是否转写

## 步骤 4：无字幕时本地转写（mlx-whisper，Apple Silicon 加速）

```bash
ffmpeg -i video.mp4 -vn -ac 1 -ar 16000 audio_16k.wav   # 16kHz 单声道是 ASR 标准输入
uvx --python 3.12 --from mlx-whisper mlx_whisper audio_16k.wav \
    --model mlx-community/whisper-large-v3-turbo --language zh \
    --output-dir transcripts --output-format all
```

注意：本机默认 python 若 ≥3.13，mlx-whisper 装不上，uvx **必须 `--python 3.12`**。
非 Apple Silicon 机器改用 whisper.cpp（`brew install whisper-cpp` + ggml 模型）。

## 步骤 5：完整性校验

```bash
ffprobe -show_entries format=duration video.mp4   # 视频实际时长
```

对照转写 json 最后一段 `end` / srt 最后一条时间轴：**差异 <1s 即通过**（结尾间隙属自然现象）；差距大说明转写截断，须排查。

## 步骤 6：智能校审（ASR 输出不得直接交付）

1. **先核数、后改字**：数字/专名先用检索工具对权威来源核验；数字错误宁可保留原样也不臆改，核验来源写进修订说明
2. 纠错分两级，逐条留"原文→修正→依据"对照表：
   - **A 类确定性纠正**：同音字、专名、术语（如 炼主→链主、御永定→余永定、两斤→两金）
   - **B 类语境重建**：原音节无法还原时按上下文重建，标注存疑，正文用〔注N〕标记
3. 批量替换用脚本（参考 `/tmp/proofread_transcript.py` 模式：`(原文, 修正, 置信级, 依据)` 列表 + 未命中检测）；注意转写是**逐行断句**的，替换串可能跨行未命中——有漏项就缩小替换粒度重跑
4. 产物三层保可回溯：**原始转写 → 校订版 → 口述整理稿**，原始稿不动

## 步骤 7：口述整理稿

按口述记录体整理：卷首档案信息（口述人/来源/时长/整理日期/底稿版本）→ 按内容脉络分节 → 段落化 → 轻度归并语气词（"那么/呢/啊"），**实质内容与全部数字不改**；B 类存疑改为文末"整理注记"表，不打断正文。

## 输出布局约定

```
<工作目录>/downloads/
├── <视频标题>.mp4
└── transcripts/
    ├── <标题>_文字稿.txt / .srt          # 原始转写
    ├── <标题>_文字稿_校订版.txt / .srt    # 校审后
    ├── 修订说明.md                        # 全部修订对照 + 核验来源
    └── <标题>_口述整理稿.md               # 可阅读版
```
