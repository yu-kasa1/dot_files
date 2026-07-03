#!/usr/bin/env bash
# edit-retry-guard.sh — Edit 連続失敗ガード hook (PostToolUse only)
#
# PostToolUse(Edit): tool_response の error 状態を見て、成功なら 0 リセット / 失敗ならインクリメント。
#   失敗後のカウントが 2 以上（＝2 連続失敗）なら hookSpecificOutput.additionalContext で警告注入。
#
# 状態ファイル: /tmp/claude-edit-fails.json
# 状態形式: {"<file_path>": {"count": N, "last_update": <unix_timestamp>}}
# 30 分以上古いエントリは期限切れとして無視（実質リセット）。
#
# 履歴: 元は PreToolUse でも警告注入していたが、PreToolUse hook 出力がモデルに届かないことが
#   実測で判明した (2026-07-03 監査)。PostToolUse 側で additionalContext 経由で警告するよう統合。
#
# 由来: review-session 試運転で発覚した RA-001
#   （compact-knowledge SKILL.md への Edit 8 連続呼び出し、CLAUDE.md「2 連続失敗で即別経路にピボット」未遵守）。
#   構造的に塞ぐための補助 hook。

set -u

STATE_FILE="/tmp/claude-edit-fails.json"
EXPIRY_SEC=1800  # 30 分

input="$(cat)"

# jq が無ければ何もしない
command -v jq >/dev/null 2>&1 || exit 0

# hook_event_name から PreToolUse / PostToolUse を判定
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"

# Edit 以外は素通し
[ "$tool" = "Edit" ] || exit 0

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && exit 0

# 状態ファイル初期化（存在しない or 不正 JSON なら空 {} で開始）
if [ ! -f "$STATE_FILE" ] || ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  echo '{}' > "$STATE_FILE"
fi

now_ts="$(date +%s)"

read_count_and_age() {
  count="$(jq -r --arg fp "$file_path" '.[$fp].count // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  last="$(jq -r --arg fp "$file_path" '.[$fp].last_update // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  age=$((now_ts - last))
  # 期限切れなら count を 0 として扱う
  if [ "$age" -gt "$EXPIRY_SEC" ]; then
    count=0
  fi
}

if [ "$event" = "PreToolUse" ]; then
  # PreToolUse は無音素通し（PreToolUse hook 出力はモデルに届かないため）。
  # 警告は PostToolUse 側で additionalContext 経由に統合済み。
  exit 0
fi

if [ "$event" = "PostToolUse" ]; then
  # 失敗判定（Claude Code バージョン差を吸収するため複数フィールドをチェック）
  is_error="$(printf '%s' "$input" | jq -r '.tool_response.is_error // empty' 2>/dev/null || true)"
  err_msg="$(printf '%s' "$input" | jq -r '.tool_response.error.message // empty' 2>/dev/null || true)"
  success="$(printf '%s' "$input" | jq -r '.tool_response.success // empty' 2>/dev/null || true)"

  if [ "$is_error" = "true" ] || [ -n "$err_msg" ] || [ "$success" = "false" ]; then
    # 失敗: カウント +1
    read_count_and_age
    new_count=$((count + 1))
    tmp="$(mktemp)"
    jq --arg fp "$file_path" --argjson c "$new_count" --argjson t "$now_ts" \
      '.[$fp] = {count: $c, last_update: $t}' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    # 2 連続失敗以降は additionalContext で警告
    if [ "$new_count" -ge 2 ]; then
      base="$(basename "$file_path")"
      msg="[harness] Edit 連続失敗 ${new_count} 回目 (file: ${base})。CLAUDE.md「2 連続失敗で即別経路にピボット」に従い、Write 全体書き直し or Bash heredoc 追記に切替を検討してください [#cbt-622-recon-p3]"
      jq -cn --arg m "$msg" '{
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: $m
        }
      }'
    fi
  else
    # 成功: 該当エントリを削除
    tmp="$(mktemp)"
    jq --arg fp "$file_path" 'del(.[$fp])' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
  exit 0
fi

exit 0
