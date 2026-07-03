#!/usr/bin/env bash
# bash-db-dml-guard.sh — PreToolUse(Bash) hook
#
# `docker (compose) exec ... mysql|psql|mariadb` 経由の DML/DDL 実行を block する。
# db-analyzer エージェントの「本番・STG DB は絶対禁止 / SELECT のみ」を prompt 遵守から
# ハーネス側の決定的な検査に置き換える補助 hook（全エージェント・親からの直接実行にも効く）。
#
# 検出パターン:
#   docker (compose|<compose>) exec/run ... (mysql|psql|mariadb) ...
#   の command 全体に (INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE) が含まれる
#
# 検出したら exit 2 + stderr で block。SELECT のみは通す。
# 誤検知（文字列 payload にキーワードが含まれるケース）は安全側で block する方針。
# 意図的に DML を投げたい場合は user 承認プロセスに載せる。
#
# 安全方針: jq 不在・非 Bash・非 docker+mysql の呼び出しは no-op (exit 0)。

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# docker (compose|-compose)? ... (exec|run) ... (mysql|psql|mariadb) の連鎖を含むか
printf '%s' "$cmd" | grep -qiE 'docker([[:space:]]+compose|-compose)?[[:space:]].*\b(exec|run)\b.*\b(mysql|psql|mariadb)\b' || exit 0

# DML/DDL キーワード検出（単語境界）
detected="$(printf '%s' "$cmd" | grep -oiE '\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b' | head -1 || true)"
[ -z "$detected" ] && exit 0

kw_upper="$(printf '%s' "$detected" | tr '[:lower:]' '[:upper:]')"
echo "docker 経由の DB 実行に DML/DDL キーワード '${kw_upper}' を検出したためブロック。db-analyzer 制約（SELECT のみ、書き込み禁止）に基づく安全ガードです。書き込みが必要な場合はユーザーに明示確認してから、hook を一時的に迂回する承認済みコマンドで実行してください。" >&2
exit 2
