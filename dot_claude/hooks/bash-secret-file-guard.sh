#!/usr/bin/env bash
# bash-secret-file-guard.sh — PreToolUse(Bash) hook
#
# Bash 経由での秘密情報ファイル（証明書・秘密鍵・credentials 系）参照を block する。
# .env 系は別 hook (bash-env-guard.sh) がカバーするため対象外。
#
# 検出対象:
#   - 拡張子系: *.pem / *.key / *.p12 / *.pfx （証明書・秘密鍵）
#   - SSH 秘密鍵ファイル名: id_rsa / id_ed25519 / id_ecdsa / id_dsa
#   - credentials 系: credentials.json / .credentials / .pgpass / .netrc
#   - パス系: .aws/credentials / .ssh/id_*
#
# 設計:
#   - jq で Bash コマンド文字列を取得
#   - grep -iE で危険パターンを検出（case-insensitive）
#   - 一つでも検出したら exit 2 + stderr で block
#
# 安全方針: jq 不在・非 Bash・抽出失敗は no-op (exit 0) で素通し。

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# パターン(A): 拡張子系。単語境界的な前後文字で囲まれた *.pem/.key/.p12/.pfx
# 前: 行頭 / 空白 / 引用符 / = / / / : / , / ; / { / } / ( / ) / [ / ]
# 後: 行末 / 同上
ext_match="$(printf '%s' "$cmd" \
  | grep -oiE '([][[:space:]"=/:,;{}()'\''])[[:alnum:]._-]+\.(pem|key|p12|pfx)([][[:space:]"=/:,;{}()'\'']|$)' \
  | head -1 || true)"

# パターン(B): SSH 秘密鍵 (id_rsa/id_ed25519/id_ecdsa/id_dsa)。公開鍵 *.pub は除外
ssh_match="$(printf '%s' "$cmd" \
  | grep -oE '(^|[][[:space:]"=/:,;{}()'\''])id_(rsa|ed25519|ecdsa|dsa)([][[:space:]"=/:,;{}()'\'']|$)' \
  | head -1 || true)"

# パターン(C): credentials 系ファイル
cred_match="$(printf '%s' "$cmd" \
  | grep -oiE '(^|[][[:space:]"=/:,;{}()'\''])(credentials\.json|\.credentials|\.pgpass|\.netrc)([][[:space:]"=/:,;{}()'\'']|$)' \
  | head -1 || true)"

# パターン(D): パス系 (.aws/credentials, .ssh/id_*)
path_match="$(printf '%s' "$cmd" \
  | grep -oE '\.aws/credentials|\.ssh/id_[[:alnum:]_]+' \
  | grep -v '\.pub$' \
  | head -1 || true)"

detected="${ext_match}${ssh_match}${cred_match}${path_match}"
[ -z "$detected" ] && exit 0

# 表示用に検出内容の要約を作る
summary="$(printf '%s\n%s\n%s\n%s' "$ext_match" "$ssh_match" "$cred_match" "$path_match" | grep -v '^$' | head -1 | sed 's/^[][[:space:]"=/:,;{}()'\'']*//;s/[][[:space:]"=/:,;{}()'\'']*$//')"

echo "Bash 経由での秘密情報ファイル（$summary 等）アクセスをブロック。証明書・秘密鍵・credentials 系ファイルは cat/head/tail/grep 経由で読まず、内容確認が必要なら user に明示確認してください。" >&2
exit 2
