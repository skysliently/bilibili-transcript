# bilibili-transcript

**B站视频提取与文字稿生成** —— 一个面向本机 AI 智能体（ZCode / Claude Code / Hermes 等）的 Agent Skill：给定任意 B 站链接（含 `b23.tv` 短链），自动产出**视频文件 + 可信文字稿**三层产物：

```
B站链接 ──解析──▶ BV号 ──yt-dlp──▶ 视频mp4 ──ffmpeg──▶ 音频 ──mlx-whisper──▶ 原始转写
                                                                            │
      口述整理稿 ◀──编辑整理◀── 校订版(txt+srt) ◀── 修订 ◀── 智能校审 ◀──────┘
                                  ▲
                    检索工具数字核验（独立证据源）
```

工作流于 2026-11-02 在 macOS (Apple Silicon) 端到端验证：12 分 40 秒视频全流程跑通，转写时间轴与视频时长对齐（760.0s vs 760.1s）。

## 功能特性

- **短链解析**：`b23.tv` 短链自动还原 BV 号
- **清晰度阶梯**：未登录 720P → 普通登录 1080P 高清 → 大会员 1080P 高码率/4K/HDR
- **付费视频 / 高画质**：用本机浏览器 Cookie 借登录态下载（含严格的出错处理规则，见下文）
- **字幕优先原则**：先查 B 站站内 CC / AI 字幕（零成本路径），有则直接取，跳过整个本地转写
- **本地 ASR 兜底**：mlx-whisper（Apple Silicon 加速）+ whisper-large-v3-turbo，中文识别质量高；模型一次性下载后转写即快路径
- **完整性校验**：ffprobe 视频时长 vs 转写末段时间轴对齐，实证无截断
- **智能校审规范**：ASR 直出稿不做人工润色不可信——先核数后改字、A/B 两级纠错、全部修订可追溯
- **三层产物保回溯**：原始转写 → 校订版 → 口述整理稿，任何一句都能查到原稿

## 安装

本仓库设计为直接位于智能体的 skill 发现目录（如 `~/.agents/skills/`）：

```bash
git clone https://github.com/skysliently/bilibili-transcript.git ~/.agents/skills/bilibili-transcript
```

### 依赖

| 工具 | 安装 | 用途 |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | `brew install yt-dlp` | 视频与字幕下载 |
| [ffmpeg](https://ffmpeg.org) | `brew install ffmpeg` | 音视频抽取与合并 |
| [uv](https://github.com/astral-sh/uv) | `brew install uv` | 运行 mlx-whisper（Apple Silicon） |

> whisper-large-v3-turbo 模型约 1.5G，首次转写自动下载至 `~/.cache/huggingface/`，之后复用免下载。
> 非 Apple Silicon 机器：将 ASR 环节替换为 whisper.cpp（`brew install whisper-cpp` + ggml 模型）。

## 使用

### 交给智能体（推荐）

skill 安装后，直接对智能体说：

> 帮我提取这个视频的文字稿：https://b23.tv/xxxx

或显式调用 `/bilibili-transcript <链接>`。智能体会按 SKILL.md 的 7 步手册执行全流程。

### 手动跑确定性环节

```bash
./scripts/extract.sh "https://b23.tv/xxxx" downloads
```

一条命令完成：下载视频 → 查站内字幕（有则直接取）→ 无字幕时本地转写。

## 付费视频 / 高画质视频的处理规则

B 站清晰度受登录态与会员态限制。本 skill 的规则：

1. **用本机浏览器做下载入口**——浏览器持有登录态/会员态，yt-dlp 直接借用其 Cookie：

   ```bash
   yt-dlp --cookies-from-browser Edge <URL>     # Edge / Chrome / Firefox 均可
   ```

2. **macOS 上 Safari 不可用**：Cookie 文件在容器沙箱内，yt-dlp 读取会报 `Operation not permitted`，直接排除。

3. **出错处理：中止并要求用户提供可用的浏览器环境**，不猜测哪个浏览器已登录、不静默降级到低画质硬试。可要求用户提供任一形式：
   - 指明哪个浏览器已登录（且含所需会员权限），换该浏览器重试；
   - 在该浏览器登录目标账号后重跑；
   - 从浏览器导出 `cookies.txt`（如 Get cookies.txt 扩展），改用 `--cookies cookies.txt`。

## 智能校审规范

ASR（语音识别）直出稿存在同音字、专名、术语错误，**不得直接交付**。本 skill 的校审规范：

1. **先核数、后改字**：数字与专名先检索权威来源核验；数字错误宁可保留原样也不臆改，核验来源写入修订说明
2. **两级纠错**，逐条留"原文 → 修正 → 依据"对照表：
   - **A 类确定性纠正**：同音字、专名、术语（如 炼主→链主、御永定→余永定、两斤→两金）
   - **B 类语境重建**：原音节无法还原时按上下文重建，标注存疑，正文用〔注N〕标记
3. **替换脚本注意跨行未命中**：转写逐行断句，批量替换需配未命中检测，漏项缩小粒度重跑
4. **B站字幕查询需登录态**：播放器 API `https://api.bilibili.com/x/player/v2?cid=<cid>&aid=<aid>` 返回 `ai_status` 与字幕列表，无 Cookie 时恒为空

## 输出布局

```
downloads/
├── <视频标题>.mp4
└── transcripts/
    ├── <标题>_文字稿.txt / .srt          # 原始转写
    ├── <标题>_文字稿_校订版.txt / .srt    # 校审后
    ├── 修订说明.md                        # 全部修订对照 + 核验来源
    └── <标题>_口述整理稿.md               # 可阅读版（分节、注记）
```

## 目录结构

```
SKILL.md            # skill 主体：7 步操作手册（含付费视频规则与校审规范）
scripts/extract.sh  # 确定性流水线：下载 → 字幕优先 → 本地转写
```

## 适用范围与边界

- ✅ 已验证：B 站单视频，macOS Apple Silicon，中文内容
- ⚠️ B 站风控：大批量下载可能触发限流，本 skill 按单视频使用设计，未做批量压测
- ⚠️ 其他平台（YouTube 等）：yt-dlp 同理适用，Cookie 规则相同，未单独验证
- ⚠️ 云端转写 API（OpenAI / 讯飞 / 阿里等）可替代本地 ASR，本仓库未内置
