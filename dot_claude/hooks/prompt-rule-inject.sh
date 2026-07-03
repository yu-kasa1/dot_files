#!/usr/bin/env bash
# prompt-rule-inject.sh — UserPromptSubmit hook（B機構プロトタイプ / active版）
#
# 入力プロンプトをキーワード照合し、該当する「1段検証」系ルールを
# just-in-time でコンテキスト注入する。非マッチ時は無音 exit 0（no-op）。
#
# active版の狙い: 単なるリマインダ（読み流せる）でなく「着手前に1行で確認/表明せよ」という
#   ディレクティブにし、可視の確認（復唱）を強制する。焼き付け（行動変化）の観察可能性を上げる。
#   ※ "効いた" の判定は復唱の有無でなく、実際にその確認を実行したか／行動が変わったかで見る。
# 由来: ~/.claude/ideas/harness-rule-triage.md（B-2/B-3/B-4/B-7）, pitfalls [#insight-20260609]
#
# 安全方針: ユーザーのプロンプト送信フローを絶対に止めないため、
#           jq 不在・空入力・想定外は全て無音 exit 0 で素通しする。

input="$(cat)"

# jq が無ければ何もしない（statusLine 等で利用済みのため通常は存在）
command -v jq >/dev/null 2>&1 || exit 0

prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -z "$prompt" ] && exit 0

emit=""
add() { emit="${emit}- ${1}"$'\n'; }

# B-2: 「別の〇〇」場所確認（具体名詞のみで誤発火を抑制）
if printf '%s' "$prompt" | grep -qiE '別[の]?(テンプレ|テンプレート|ファイル|シート|スプレッドシート|ブック|タブ|画面|プロジェクト|リポジトリ)'; then
  add "着手前に1行で確認してから進む: その『別の〇〇』は同一ファイル内か、別ファイルか？ [#sakumon-20260518-p1]"
fi

# B-3: 重い表現の到達性確認
if printf '%s' "$prompt" | grep -qiE '脆弱性|迂回|致命的|サイレント.{0,4}破壊|セキュリティホール'; then
  add "重い表現（脆弱性/致命的等）を使う前に、到達可能な攻撃/誤動作シナリオを1つ明記する。書けなければ中立表現に落としてから進む [#prtp-782-p2]"
fi

# B-4: 壁打ち → feasibility-writer 発動条件チェック
if printf '%s' "$prompt" | grep -qiE '壁打ち|実現可能性|松竹梅|どっち(がいい|にする|が良い)|方向性'; then
  add "実装方針に入る前に feasibility-writer 発動条件を1行で表明する: 複数アーキ案/外部リソース制約/松竹梅比較に該当するか？"
fi

# B-7（実験的・過剰発火しやすいので要チューニング）: 調査依頼の初手ゴール要約
if printf '%s' "$prompt" | grep -qiE '調査して|原因(を|は|究明)|なぜ.{0,20}(落ち|失敗|エラー|出ない|動かな)'; then
  add "コード/DB調査に入る前に『ゴール = X できるようにする、で合ってる？』を1行で確認する [#cbt-684-design-p1]"
fi

[ -z "$emit" ] && exit 0

printf '%s\n%s' "[harness 着手前チェック（キーワード検知による自動注入）— 本題の作業に入る前に、以下の該当項目を1行で確認/表明してから進むこと]" "$emit"
exit 0
