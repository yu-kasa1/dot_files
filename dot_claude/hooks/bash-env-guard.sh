#!/usr/bin/env bash
# bash-env-guard.sh — PreToolUse(Bash) hook
#
# Bash 経由での .env / .env.<env_name> ファイル参照を block する。
# 既存 deny ルール `Bash(cat .env*)` を補完し、cat 以外の read-only 経路
# (head / tail / grep / awk / less / more / sed -n 等) も網羅する。
#
# 設計:
#   - jq で Bash コマンド文字列を取得し、.env / .env.<word> token を抽出
#   - .env.example / .env.sample / .env.template / .env.dist は例外として通す
#   - 一つでも危険 token があれば exit 2 + stderr で block
#   - .envrc (direnv) は前後文字制限で誤検知しない設計
#
# 安全方針: jq 不在・非 Bash・抽出失敗は no-op (exit 0) で素通し。

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# .env または .env.<word> を含む token を抽出
# 前: 行頭 / 空白 / 引用符 / = / / / : / , / ; / { / } / ( / ) / [ / ]
# 後: 行末 / 同上 (拡張子継続を許さない -> .envrc を誤検知しない)
matches="$(printf '%s' "$cmd" \
  | grep -oE '(^|[][[:space:]"=/:,;{}()'\''])\.env(\.[A-Za-z0-9_-]+)?([][[:space:]"=/:,;{}()'\'']|$)' \
  | grep -oE '\.env(\.[A-Za-z0-9_-]+)?' \
  || true)"

[ -z "$matches" ] && exit 0

denied=""
while IFS= read -r m; do
  [ -z "$m" ] && continue
  case "$m" in
    .env.example|.env.sample|.env.template|.env.dist) continue ;;
    *) denied="$m" ; break ;;
  esac
done <<EOF
$matches
EOF

[ -z "$denied" ] && exit 0

echo "Bash 経由での '${denied}' アクセスをブロック。秘密情報を含む可能性があるため、内容を読む必要があるなら user に明示確認してください (例外: .env.example / .env.sample / .env.template / .env.dist は通過)。" >&2
exit 2
