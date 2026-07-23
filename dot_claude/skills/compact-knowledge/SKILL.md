---
name: compact-knowledge
description: GLOBAL_MEMORY.md / memory/*.md / pitfalls.md / CLAUDE.md / agents/*.md / rules/*.md を走査し、ルールの重複・未参照アンカー・統合候補を検出する。修正は実施せず候補レポートのみ出力する。週次バンドル経由（absorb直後）または「ルール圧縮」「重複検出」「pitfalls整理」「コンパクション」等の発話で起動する。
---

# ルール群コンパクション走査 (compact-knowledge)

## 概要
absorb で蓄積されたルール群（GLOBAL_MEMORY.md / memory/*.md / pitfalls.md / CLAUDE.md / agents/*.md / rules/*.md）を定期的に走査し、肥大化・重複・陳腐化の兆候を検出する。

**検出のみ・修正なし**。候補レポートを出力し、実際の統合・削除はユーザーが手動承認のうえ実施する。

## 呼び出しタイミング
- weekly-bundle 経由（absorb の直後）
- 「ルール圧縮」「重複ルール検出」「pitfalls 整理」「コンパクション」等の発話で単独起動

## 走査対象
- `~/.claude/knowledge/GLOBAL_MEMORY.md`（鉄則 + 索引）
- `~/.claude/knowledge/memory/*.md`（topic 別蓄積、設計/エージェント運用/AWS/トラブルシューティング/プロセス/ビルド検証）
- `~/.claude/knowledge/pitfalls.md`
- `~/.claude/knowledge/verify-rules.md`（断定前の 1 段検証ルール集、`[#anchor]` 参照多数）
- `~/.claude/knowledge/session-operation.md`（セッション運用ルール、`[#anchor]` 参照あり）
- `~/.claude/knowledge/agent-collab-detail.md`（agent 連携詳細、`[#anchor]` 参照あり）
- `~/.claude/knowledge/build-verification.md`（ビルド検証コマンド集）
- `~/.claude/knowledge/ssg-checklist.md`（SSG 実装前チェックリスト）
- `~/.claude/CLAUDE.md`
- `~/.claude/agents/*.md`
- `~/.claude/rules/*.md`

## 検出パターン

### パターン A: 未参照 pitfalls アンカー
`pitfalls.md` に登録されているが、GLOBAL_MEMORY.md / memory/*.md / CLAUDE.md / agents/*.md / rules/*.md のどこからも `[#anchor]` 形式で参照されていないエントリを検出する。

参照されていないエントリは「ルール本文に紐づかない孤立した経緯ログ」になっており、削除候補 または ルール本文への昇格候補。

GLOBAL_MEMORY.md / memory/*.md からの参照も検出対象に含める（鉄則・topic 知見の 1 行ルール末尾に `[#anchor]` で経緯参照を付ける運用があるため、含めないと偽陽性が出る）。

検出コマンド:
```bash
pf=$(grep -E '^## [a-z0-9-]+' ~/.claude/knowledge/pitfalls.md | sed 's/^## //' | awk '{print $1}' | sort -u)
# grep パターンは複数アンカー並記 `[#a, #b, #c]` にも対応するため `[^]]*` で `]` まで許容
refs=$(grep -rEho '\[#[a-z0-9-]+[^]]*\]' \
  ~/.claude/knowledge/GLOBAL_MEMORY.md \
  ~/.claude/knowledge/memory/ \
  ~/.claude/knowledge/verify-rules.md \
  ~/.claude/knowledge/session-operation.md \
  ~/.claude/knowledge/agent-collab-detail.md \
  ~/.claude/knowledge/build-verification.md \
  ~/.claude/knowledge/ssg-checklist.md \
  ~/.claude/CLAUDE.md \
  ~/.claude/agents/ \
  ~/.claude/rules/ 2>/dev/null \
  | grep -oE '#[a-z0-9-]+' | sed 's/^#//' | sort -u)
comm -23 <(echo "$pf") <(echo "$refs")
```

### パターン B: GLOBAL_MEMORY / memory/*.md 内の重複候補
`GLOBAL_MEMORY.md` の鉄則セクション、および `memory/*.md` 各 topic ファイル内で、本文先頭の主要語が重複する行ペアを抽出する。**topic ファイル間の横断重複（design.md と process.md に同義エントリ等）も検出対象**。

完全自動判定は困難なので、以下の手順で候補を列挙する:
1. GLOBAL_MEMORY.md 鉄則セクションの箇条書きを抽出
2. memory/*.md 各 topic ファイル配下の箇条書きを抽出
3. 各行から先頭の主要キーワード（最初の名詞句、5〜10文字）を切り出す
4. 同一ファイル内およびファイル横断でキーワード重複する行ペアを列挙

**キーワード抽出例**:
- `「spec.md は feasibility.md に依存せず…」` → キーワード `spec.md 依存`
- `「曖昧な短質問（「直せる？」等）は…意図確認」` → キーワード `曖昧 質問 意図確認`
- `「Grepの行番号だけで内容推測しない」` → キーワード `Grep 推測`

検出は Claude が行を読んで判定する。grep で先頭一致が出るペアを優先的に拾い、内容類似性は Claude が文脈で確認する。

### パターン C: 単一 pitfalls アンカーへの複数参照
同じ `[#anchor]` が GLOBAL_MEMORY.md / memory/*.md / CLAUDE.md / agents/*.md / rules/*.md で 2 箇所以上から参照されているケースを検出する。

**閾値の判定**:
- **2 箇所参照**: 参考表示のみ（意図的な複数エージェント参照のケースが多い）
- **3 箇所以上**: 警告表示（同じルール本文が分散している可能性、統合余地ありの確度が上がる）

意図的に複数箇所で参照しているケース（同じ pitfall が複数エージェントに関連）と、ルール本文が重複しているケース（統合余地あり）が混在するので、人間が判断する素材として列挙する。

検出コマンド:
```bash
# 複数アンカー並記 `[#a, #b, #c]` にも対応するため 2 段 grep で個別分解
grep -rEoh '\[#[a-z0-9-]+[^]]*\]' \
  ~/.claude/knowledge/GLOBAL_MEMORY.md \
  ~/.claude/knowledge/memory/ \
  ~/.claude/knowledge/verify-rules.md \
  ~/.claude/knowledge/session-operation.md \
  ~/.claude/knowledge/agent-collab-detail.md \
  ~/.claude/knowledge/build-verification.md \
  ~/.claude/knowledge/ssg-checklist.md \
  ~/.claude/CLAUDE.md \
  ~/.claude/agents/ \
  ~/.claude/rules/ 2>/dev/null \
  | grep -oE '#[a-z0-9-]+' \
  | sort | uniq -c | awk '$1 > 1 {print $2 " (" $1 "回参照)"}'
```

参照箇所の特定（`#anchor-name` は探したいアンカー名に置換）:
```bash
grep -rn "#anchor-name" \
  ~/.claude/knowledge/GLOBAL_MEMORY.md \
  ~/.claude/knowledge/memory/ \
  ~/.claude/knowledge/verify-rules.md \
  ~/.claude/knowledge/session-operation.md \
  ~/.claude/knowledge/agent-collab-detail.md \
  ~/.claude/CLAUDE.md \
  ~/.claude/agents/ \
  ~/.claude/rules/
```

## 実行手順

1. **3パターンを順次実行**して候補を抽出する
2. **各候補について Claude が補助情報を付与**（該当ファイル位置、本文抜粋など）
3. **レポートを生成**して `~/.claude/weekly-reports/run-log/YYYY-MM-DD-compaction.md` に保存
4. **標準出力にサマリ**を表示（候補件数）

## 出力フォーマット

```markdown
# コンパクション候補レポート YYYY-MM-DD

## サマリ
- 未参照 pitfalls アンカー: N件
- GLOBAL_MEMORY 重複候補: N件
- pitfalls 複数参照アンカー: N件

## A. 未参照 pitfalls アンカー
| アンカー | エントリ要約 | 判断材料 |
|---------|-------------|----------|
| #xxx-p1 | 短い結論 | 経緯ログのみ・ルール反映候補 or 削除候補 |

## B. GLOBAL_MEMORY 重複候補
| カテゴリ | 行1 | 行2 | 重複キーワード |
|---------|-----|-----|---------------|
| 設計 | ... | ... | ... |

## C. pitfalls 複数参照アンカー
| アンカー | 参照箇所 | 内容 |
|---------|---------|------|
| #xxx-p1 | CLAUDE.md:42, agents/coder.md:18 | （pitfalls.md からの抜粋） |

## 推奨アクション
- 未参照 N 件: 削除 or ルール反映を検討
- 重複候補 N 件: 統合可否を確認
- 複数参照 N 件: 統合余地ありか確認

修正は手動で実施してください。本スキルは候補列挙のみで自動更新は行いません。
```

## 注意事項
- **修正は実施しない**: 検出のみ。自動でルールを統合・削除しない
- **候補は完全ではない**: パターン B（GLOBAL_MEMORY 重複）は単純な文字列マッチで判定するため、見逃しがある。決定的な判定材料ではなく「人間が確認する素材」として扱う
- **候補が 0 件の場合もレポートは出力する**: 「コンパクション候補なし」と明記して run-log に保存し、weekly-bundle 側で確認できるようにする
- **既存ルールの意図を尊重する**: 検出された候補をすべて統合すべきとは限らない。複数箇所参照は意図的なケースもある（CLAUDE.md「サブエージェント指摘の反映前チェック」と同じ判断原則）
- **シンボリックリンクに注意**: `~/.claude/` と `dot_files/dot_claude/` はシンボリックリンク済みなので、どちら経由で走査しても同じファイルを指す
- **シェル前提**: 検出コマンドは zsh/bash 前提（プロセス置換 `<(...)` 等を使用）。fish 等で実行する場合は事前に bash サブシェルへ入る
- **ファイル名衝突**: 単独起動時も同名 `YYYY-MM-DD-compaction.md` で書き出す。同日に複数回起動した場合は上書き運用（最新のスナップショットを採用、履歴が必要なら git で管理）
- **複数アンカー並記形式に対応済み**: `[#a, #b, #c 再発記録]` のように 1 個の `[]` に複数アンカーを詰めた形式（CLAUDE.md `[#cbt-622-recon-p3, #prtp-825-investigate-p8, #prtp-834-impl-p4]` 等）も検出コマンドで拾える。以前は単一アンカー前提の `\[#[a-z0-9-]+\]` パターンで複数並記行を丸ごと取りこぼしていた（2026-07-03 発見、2026-07-23 修正）
