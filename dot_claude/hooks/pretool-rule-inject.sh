#!/usr/bin/env bash
# posttool-rule-inject.sh — PostToolUse(Edit|Write|MultiEdit) hook
#
# 編集対象ファイルの拡張子に応じて、言語別開発ルール（rule-snippets/）への
# 参照パスを just-in-time でコンテキストに注入する。
# 非マッチ・jq 不在・想定外は全て無音 exit 0 で素通し。
#
# 由来: rules/ 配下を Claude Code が全自動 include する仕様により、言語別ルールが
#   常時ロードされ context を圧迫していたのを是正する。本 hook で「触る言語のルールだけ」
#   必要時に注入する引き出し型に切り替える。
#
# 履歴: 元は PreToolUse で運用していたが、PreToolUse hook の stdout/stderr/permissionDecisionReason
#   のいずれもモデルに届かないことが実測で判明した (2026-07-03 監査)。PostToolUse の
#   hookSpecificOutput.additionalContext で通知する形に移設。編集「後」通知になるが、
#   次回の同種ファイル編集までにルールを把握してもらう狙い。
#
# 安全方針: ユーザーの編集フローを止めないため、判定不能は全て no-op (exit 0)。

set -u

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
case "$tool" in
  Edit|Write|MultiEdit) : ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && exit 0

base_lc="$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')"

emit=""
add() { emit="${emit}- ${1}"$'\n'; }

# .blade.php は .php より先に判定する必要があるため case の順序に注意
case "$base_lc" in
  *.blade.php)
    add "Laravel/Blade: ~/.claude/rule-snippets/development-rule-laravel.md"
    ;;
  *.php)
    add "Laravel/PHP: ~/.claude/rule-snippets/development-rule-laravel.md"
    ;;
  *.vue)
    add "Vue: ~/.claude/rule-snippets/development-rule-vue.md"
    add "JavaScript: ~/.claude/rule-snippets/development-rule-javascript.md"
    ;;
  *.tsx)
    add "TypeScript: ~/.claude/rule-snippets/development-rule-typescript.md"
    add "React: ~/.claude/rule-snippets/development-rule-react.md"
    ;;
  *.ts)
    add "TypeScript: ~/.claude/rule-snippets/development-rule-typescript.md"
    ;;
  *.jsx)
    add "React: ~/.claude/rule-snippets/development-rule-react.md"
    add "JavaScript: ~/.claude/rule-snippets/development-rule-javascript.md"
    ;;
  *.js|*.mjs|*.cjs)
    add "JavaScript: ~/.claude/rule-snippets/development-rule-javascript.md"
    ;;
esac

[ -z "$emit" ] && exit 0

# PostToolUse の hookSpecificOutput.additionalContext でモデルに情報を届ける。
message="[harness 言語ルール参照（拡張子から自動注入）— 未読のルールは Read で読んでから次の編集に入る]"$'\n'"${emit}"
jq -cn --arg m "$message" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $m
  }
}'
exit 0
