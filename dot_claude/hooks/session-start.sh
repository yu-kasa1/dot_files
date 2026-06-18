#!/usr/bin/env bash
# SessionStart hook: 前回の引き継ぎノートとグローバル知見をコンテキストへ注入する
# CLAUDE.md の「セッション開始時の必須手順」を機械的に強制するための自動化。

set -u

PROJECT_NAME="$(basename "$PWD")"
HANDOVER_DIR="$HOME/.claude/handovers/$PROJECT_NAME"
GLOBAL_MEMORY="$HOME/.claude/knowledge/GLOBAL_MEMORY.md"

printed_any=0

# 前回の引き継ぎノート（最新1件のみ）
if [ -d "$HANDOVER_DIR" ]; then
  latest_handover="$(ls -1t "$HANDOVER_DIR"/*.md 2>/dev/null | head -n 1)"
  if [ -n "${latest_handover:-}" ]; then
    echo "## 前回の引き継ぎノート ($(basename "$latest_handover"))"
    echo ""
    cat "$latest_handover"
    echo ""
    printed_any=1
  fi
fi

# プロジェクト横断の知見
if [ -f "$GLOBAL_MEMORY" ]; then
  [ "$printed_any" -eq 1 ] && echo "---" && echo ""
  echo "## GLOBAL_MEMORY"
  echo ""
  cat "$GLOBAL_MEMORY"
  echo ""
  printed_any=1
fi

# どちらもなければ無音で終了（ノイズを出さない）
exit 0
