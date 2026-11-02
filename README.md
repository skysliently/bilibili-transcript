# bilibili-transcript

ZCode / Claude Code / Hermes 等本机智能体通用的 Agent Skill：**给定 B 站链接，产出视频文件与可信文字稿**（原始转写 → 校订版 → 口述整理稿三层产物）。

工作流首次端到端验证于 2026-11-02（macOS Apple Silicon），方法论沉淀见 Tolaria 笔记 `2026/2026-11-02-bilibili-video-transcript-workflow.md`。

## 安装

本仓库位于 `~/.agents/skills/bilibili-transcript`（skill 发现目录内直接建仓，单一事实源）。新机器迁移：

```bash
git clone <本仓库地址> ~/.agents/skills/bilibili-transcript
```

## 依赖

| 工具 | 安装 | 说明 |
|---|---|---|
| yt-dlp | `brew install yt-dlp` | 视频与字幕下载 |
| ffmpeg | `brew install ffmpeg` | 音视频抽取/合并 |
| uv | `brew install uv` | 运行 mlx-whisper（Apple Silicon） |

whisper-large-v3-turbo 模型约 1.5G，首次转写自动下载至 `~/.cache/huggingface/`，之后复用。

## 使用

交给智能体（推荐）：直接发 B 站链接并说"提取视频/生成文字稿"，skill 自动触发；或显式调用 `/bilibili-transcript <链接>`。

手动跑确定性环节：

```bash
./scripts/extract.sh "https://b23.tv/xxxx" downloads
```

付费视频 / 1080P 以上画质：按 SKILL.md 用 `--cookies-from-browser Edge|Chrome|Firefox` 借浏览器登录态；Cookie 失败时中止并让用户提供可用的浏览器环境（Safari 在 macOS 不可用）。

## 仓库结构

```
SKILL.md            # skill 主体：7 步操作手册（含付费视频规则与校审规范）
scripts/extract.sh  # 确定性流水线：下载 → 字幕优先 → 本地转写
```
