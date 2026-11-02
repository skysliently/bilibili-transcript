#!/usr/bin/env bash
# bilibili-transcript — B站视频提取与转写的确定性流水线
# 用法: extract.sh <B站链接> [输出目录]
# 覆盖 SKILL.md 步骤 1-5（下载 → 字幕优先 → 无字幕时本地转写）；
# 付费/高画质需求与校审为编辑环节，由执行 agent 按 SKILL.md 处理，不在本脚本内。
set -euo pipefail

URL="${1:?用法: extract.sh <B站链接> [输出目录]}"
OUT="${2:-downloads}"
mkdir -p "$OUT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1：$2" >&2; exit 1; }; }
need yt-dlp "brew install yt-dlp"
need ffmpeg "brew install ffmpeg"

echo "[1/3] 下载视频（最佳可得画质）..."
yt-dlp -f "bv*+ba/b" --merge-output-format mp4 -o "$OUT/%(title).80s.%(ext)s" "$URL"
VIDEO=$(ls -t "$OUT"/*.mp4 | head -1)

echo "[2/3] 检查站内字幕（CC/AI 字幕需登录态，登录用户才能取到）..."
yt-dlp --write-subs --write-auto-subs --sub-langs ".*" --skip-download \
       -o "$OUT/%(title).80s" "$URL" || true

if ls "$OUT"/*.srt "$OUT"/*.vtt >/dev/null 2>&1; then
  echo "已获取站内字幕，跳过本地转写。"
  ls "$OUT"/*.srt "$OUT"/*.vtt
  exit 0
fi

echo "[3/3] 无站内字幕，本地 mlx-whisper 转写..."
need uv "brew install uv（或官方安装脚本）"
WAV="$OUT/audio_16k.wav"
ffmpeg -y -v error -i "$VIDEO" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WAV"
uvx --python 3.12 --from mlx-whisper mlx_whisper "$WAV" \
    --model mlx-community/whisper-large-v3-turbo --language zh \
    --output-dir "$OUT/transcripts" --output-format all

echo "完成："
echo "  视频:   $VIDEO"
echo "  转写:   $OUT/transcripts/（txt/srt/vtt/json）"
echo "后续: 按 SKILL.md 步骤 6/7 做智能校审与口述整理稿。"
