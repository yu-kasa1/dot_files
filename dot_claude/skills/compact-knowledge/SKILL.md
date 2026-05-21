---
name: compact-knowledge
description: GLOBAL_MEMORY.md / pitfalls.md / CLAUDE.md / agents/*.md / rules/*.md を走査し、ルールの重複・未参照アンカー・統合候補を検出する。修正は実施せず候補レポートのみ出力する。週次バンドル経由（absorb直後）または「ルール圧縮」「重複検出」「pitfalls整理」「コンパクション」等の発話で起動する。
---

# ルール群コンパクション走査 (compact-knowledge)

## 概要
absorb で蓄積されたルール群（GLOBAL_MEMORY.md / pitfalls.md / CLAUDE.md / agents/*.md / rules/*.md）を定期的に走査し、肥大化・重複・陳腐化の兆候を検出する。

**検出のみ・修正なし**。候補レポートを出力し、実際の統合・削除はユーザーが手動承認のうえ実施する。

## 呼び出しタイミング
- weekly-bundle 経由（absorb の直後）
- 「ルール圧縮」「重複ルール検出」「pitfalls 整理」「コンパクション」等の発話で単独起動

## 走査対象
- `~/.claude/knowledge/GLOBAL_MEMORY.md`
- `~/.claude/knowledge/pitfalls.md`
- `~/.claude/CLAUDE.md`
- `~/.claude/agents/*.md`
- `~/.claude/rules/*.md`

## 検出パターン

### パターン A: 未参照 pitfalls アンカー
`pitfalls.md` に登録されているが、CLAUDE.md / agents/*.md / rules/*.md のどこからも `[#anchor]` 形式で参照されていないエントリを検出する。

参照されていないエントリは「ルール本文に紐づかない孤立した経緯ログ」になっており、削除候補 または ルール本文への昇格候補。

検出コマンド:
```bash
pf=$(grep -E '^## [a-z0-9-]+' ~/.claude/knowledge/pitfalls.md | sed 's/^## //' | awk '{print $1}' | sort -u)
refs=$(grep -rEho '\[#[a-z0-9-]+\]' ~/.claude/CLAUDE.md ~/.claude/agents/ ~/.claude/rules/ 2>/dev/null | sed 's/\[#//;s/\]//' | sort -u)
comm -23 <(echo "$pf") <(echo "$refs")
```

### パターン B: GLOBAL_MEMORY 内の重複候補
`GLOBAL_MEMORY.md` の同一カテゴリ内で、本文先頭の主要語が重複する行ペアを抽出する。

完全自動判定は困難なので、以下の手順で候補を列挙する:
1. 各カテゴリ（`## 設計`, `## エージェント運用`, `## プロセス` 等）配下の箇条書きを抽出
2. 各行から先頭の主要キーワード（最初の名詞句、5〜10文字）を切り出す
3. 同一カテゴリ内でキーワード重複する行ペアを列挙

検出は Claude が行を読んで判定する。grep で先頭一致が出るペアを優先的に拾い、内容類似性は Claude が文脈で確認する。

### パターン C: 単一 pitfalls アンカーへの複数参照
同じ `[#anchor]` が CLAUDE.md / agents/*.md / rules/*.md で 2 箇所以上から参照されているケースを検出する。

意図的に複数箇所で参照しているケース（同じ pitfall が複数エージェントに関連）と、ルール本文が重複しているケース（統合余地あり）が混在するので、人間が判断する素材として列挙する。

検出コマンド:
```bash
grep -rEoh '\[#[a-z0-9-]+\]' ~/.claude/CLAUDE.md ~/.claude/agents/ ~/.claude/rules/ 2>/dev/null \
  | sort | uniq -c | awk '$1 > 1 {print $2 " (" $1 "回参照)"}'
```

参照箇所の特定:
```bash
grep -rn '\[#anchor-name\]' ~/.claude/CLAUDE.md ~/.claude/agents/ ~/.claude/rules/
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
