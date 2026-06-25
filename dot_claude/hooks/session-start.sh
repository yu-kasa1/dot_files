#!/usr/bin/env bash
# SessionStart hook: 前回の引き継ぎノートとグローバル知見をコンテキストへ注入する
# CLAUDE.md の「セッション開始時の必須手順」を機械的に強制するための自動化。

set -u

PROJECT_NAME="$(basename "$PWD")"
HANDOVER_DIR="$HOME/.claude/handovers/$PROJECT_NAME"
GLOBAL_MEMORY="$HOME/.claude/knowledge/GLOBAL_MEMORY.md"

printed_any=0

# 前回の引き継ぎノート（最新1件のみ）
# `<!-- /summary -->` マーカーがある handover は冒頭の常時参照セクションのみ注入し、
# 詳細セクション（今回やったこと/捨てた選択肢/ハマりどころ/学び等）は
# 必要時に Read させる。マーカーがない既存 handover は全文注入で後方互換。
# （`---` を境界に使うと本文中のセクション区切り用 `---` と衝突するため専用マーカーを採用）
if [ -d "$HANDOVER_DIR" ]; then
  latest_handover="$(ls -1t "$HANDOVER_DIR"/*.md 2>/dev/null | head -n 1)"
  if [ -n "${latest_handover:-}" ]; then
    echo "## 前回の引き継ぎノート ($(basename "$latest_handover"))"
    echo ""
    if grep -q '<!-- /summary -->' "$latest_handover"; then
      # マーカーあり: マーカー直前までを注入（常時参照セクション）
      awk '/<!-- \/summary -->/{exit} {print}' "$latest_handover"
      echo ""
      echo "_詳細セクション（今回やったこと/捨てた選択肢/ハマりどころ/学び/次にやること/関連ファイル）は必要時に Read: \`$latest_handover\`_"
    else
      # マーカーなし: 全文注入（後方互換）
      cat "$latest_handover"
    fi
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
