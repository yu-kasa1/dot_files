#!/usr/bin/env bash
# bash-cat-guard.sh — PreToolUse(Bash) hook（A-1）
#
# 大ファイルの `cat` 全文ダンプを止め、Read(offset/limit) / grep -n へ誘導する。
# malformed tool call / persisted-output 退避の主因（[#env-opus48-toolcall-p1]）を物理的に抑止する。
# 由来: ~/.claude/ideas/harness-rule-triage.md（A-1）
#
# 判定: 単純な `cat [flags] file...`（パイプ/リダイレクト/連結/置換なし）で、
#       対象ファイルが LINE_MAX 行超 または BYTE_MAX バイト超なら exit 2 でブロック。
# 安全方針: 解釈できない複雑コマンド・jq不在・ファイル不在・非Bashは全て no-op（exit 0）で素通し。
#           ブロックは exit 2 + stderr（Claude へのフィードバックになり、Read/grep へ切り替えられる）。

LINE_MAX=800      # この行数を超える cat をブロック（要調整時はここ）
BYTE_MAX=40000    # このバイト数を超える cat をブロック

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

# 複雑なコマンドは触らない（パイプ/リダイレクト/連結/コマンド置換 → 出力は加工/小さい想定）
case "$cmd" in
  *'|'* | *'>'* | *'<'* | *';'* | *'&'* | *'$('* | *'`'* ) exit 0 ;;
esac

# グロブ展開を止めて単語分割（解釈できなければ no-op に倒れる）
set -f
set -- $cmd
[ "$1" = "cat" ] || exit 0
shift

big=""
for tok in "$@"; do
  case "$tok" in
    -*) continue ;;  # フラグはスキップ
  esac
  f="$tok"
  case "$f" in
    /*) : ;;                              # 絶対パスはそのまま
    *)  [ -n "$cwd" ] && f="$cwd/$f" ;;   # 相対は cwd 起点で解決
  esac
  [ -f "$f" ] || continue
  lines="$(wc -l < "$f" 2>/dev/null | tr -d ' ')"
  bytes="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
  [ -z "$lines" ] && lines=0
  [ -z "$bytes" ] && bytes=0
  case "$lines$bytes" in *[!0-9]*) continue ;; esac  # 数値でなければスキップ
  if [ "$lines" -gt "$LINE_MAX" ] || [ "$bytes" -gt "$BYTE_MAX" ]; then
    big="${tok}（${lines}行/${bytes}B）"
    break
  fi
done

[ -z "$big" ] && exit 0

echo "大ファイルの cat 全文ダンプをブロック: ${big}。Read を offset/limit で範囲指定するか、grep -n でピンポイント抽出してください（malformed / persisted-output 退避の回避 [#env-opus48-toolcall-p1]）。" >&2
exit 2
