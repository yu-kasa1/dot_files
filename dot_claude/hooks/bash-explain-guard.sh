#!/usr/bin/env bash
# bash-explain-guard.sh — PreToolUse(Bash) hook
#
# 破壊的 Bash コマンドが、直近 assistant 発話で「対象 or 影響」を説明されているかチェックする。
# 説明が見つからなければ stderr に警告を出す（実行はブロックしない＝permission ダイアログでの判断材料）。
#
# 由来: zenn.dev/nttdata_tech d2edb6a9fe5d7f を参考に、deny 回避経路を含めて広めに検出。
# 既存 bash-cat-guard.sh と並列で動作。
#
# 安全方針: jq 不在・transcript 不在・非 Bash・解釈不能は全て no-op (exit 0)。

set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# 破壊的パターン: deny 済みコマンド + deny 回避経路 (xargs/find -delete/subshell) + 強制系フラグ
# 注: ノイズ抑制のため、安全側に倒すパターンは含めない（cp 通常 / mkdir / touch 等）
danger_re='(\brm[[:space:]]+|\bmv[[:space:]]+|\bcp[[:space:]]+-[a-zA-Z]*f|\bsed[[:space:]]+-i\b|\bgit[[:space:]]+reset[[:space:]]+--hard\b|\bgit[[:space:]]+(push|p)[[:space:]]+.*(--force|-f\b)|\bgit[[:space:]]+commit\b.*--no-verify\b|\bgit[[:space:]]+clean[[:space:]]+.*-[a-zA-Z]*f|\bxargs[[:space:]]+.*\brm\b|\bfind\b[^|;&]*-delete\b|\bchmod[[:space:]]+|\bchown[[:space:]]+|\btruncate[[:space:]]+|\bdd[[:space:]]+.*of=|[[:space:]]>[[:space:]]*/[A-Za-z]|\bdrop[[:space:]]+(table|database|schema)\b|\bdelete[[:space:]]+from\b|\bupdate[[:space:]]+[^|]*[[:space:]]set\b|\bshred[[:space:]]+|\bdocker[[:space:]]+(rm|kill|system[[:space:]]+prune)\b)'

if ! printf '%s' "$cmd" | grep -Eiq "$danger_re"; then
  exit 0
fi

# 直近 assistant 発話を取得 (transcript jsonl 末尾から逆順に集める)
last_text=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # macOS の tail -r で逆順、直近 200 行から assistant の text を集める
  last_text="$(tail -r "$transcript" 2>/dev/null | head -200 \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
    | head -200)"
fi

# 説明判定: 影響キーワード (日英) または破壊系コマンド名の言及があれば「説明あり」とみなす
explain_re='(削除|消去|消す|上書き|移動|破壊|リセット|強制|destructive|delete|remove|removing|deleting|moving|overwrite|overwriting|force[[:space:]]*push|reset[[:space:]]+--hard|\brm[[:space:]]|\bmv[[:space:]]|chmod|chown|drop[[:space:]]+table)'

if printf '%s' "$last_text" | grep -Eiq "$explain_re"; then
  exit 0
fi

# 説明見つからず → stderr 警告 (実行は続行、permission ダイアログで判断)
{
  echo "──────────────────────────────────────────"
  echo "[explain-guard] 破壊的コマンドの実行直前に、対象・影響の説明が直近 assistant 発話で見つかりませんでした。"
  echo "[explain-guard] command: ${cmd}"
  echo "[explain-guard] CLAUDE.md「破壊的または大規模なファイル操作を自律的に実行しない」を再確認してください。"
  echo "──────────────────────────────────────────"
} >&2

exit 0
