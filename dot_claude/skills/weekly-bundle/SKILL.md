---
name: weekly-bundle
description: 金曜朝に回す週次レポート4点セット（absorb → compact-knowledge → weekly-report → notion-weekly-report）を順次自動実行する。
---

# 週次レポート4点セット (weekly-bundle)

## 概要
週次で回す4つのスキルをまとめて順次実行するバンドルスキル。
個別実行の手間を省き、忘れるリスクを下げる。

## 呼び出しタイミング
- 金曜朝（手動 or launchd等の自動実行）
- 週次レポート作成タイミング

## 実行手順

### 1. 各スキルを順次実行
ユーザー確認を待たず、4スキルを連続で実行する:

1. **/absorb**
   - retrospective/handoverから知見を抽出
   - GLOBAL_MEMORY.md（鉄則昇格）または `~/.claude/knowledge/memory/{category}.md`（topic 追記）に反映
   - 昇格判定の迷いがある知見は「保留」扱い

2. **/compact-knowledge**
   - absorb 直後の状態に対してルール群を走査
   - 未参照 pitfalls アンカー / GLOBAL_MEMORY・memory/*.md 重複候補 / 複数参照アンカーを検出
   - 候補レポートを `~/.claude/weekly-reports/run-log/YYYY-MM-DD-compaction.md` に出力
   - 修正は実施しない（検出のみ）

3. **/weekly-report**
   - 集計期間: 直近木曜終了の7日間
   - 出力先: `~/.claude/weekly-reports/YYYY-MM-DD.md`
   - retrospective/handoverが0件なら最小限レポート

4. **/notion-weekly-report**
   - Notion「日報自分用」ページから今週分の日報を取得
   - 会社提出用フォーマットで本文を生成
   - Notionの同ページ先頭に「N月M週目」トグルとして書き戻す

### 2. 実行ログの出力
全スキル実行後、`~/.claude/weekly-reports/run-log/YYYY-MM-DD.md` にサマリを書き出す（ディレクトリが無ければ作成）:

```markdown
# 週次レポート実行ログ YYYY-MM-DD

## /absorb
- 実行: 成功 / 失敗
- 昇格件数: N（鉄則: N / topic: N）/ 保留件数: N
- GLOBAL_MEMORY.md 更新: あり / なし
- memory/*.md 更新: あり / なし（更新ファイル名）
- エラー: （あれば）

## /compact-knowledge
- 実行: 成功 / 失敗
- 候補レポート: ~/.claude/weekly-reports/run-log/YYYY-MM-DD-compaction.md
- 未参照 pitfalls アンカー: N件
- GLOBAL_MEMORY / memory/*.md 重複候補: N件
- pitfalls 複数参照アンカー: N件
- エラー: （あれば）

## /weekly-report
- 実行: 成功 / 失敗
- 出力ファイル: パス
- 集計期間: YYYY-MM-DD 〜 YYYY-MM-DD
- 対応チケット数: N
- エラー: （あれば）

## /notion-weekly-report
- 実行: 成功 / 失敗
- Notion取得: 成功 / 失敗
- Notion書き戻し: 成功 / 失敗
- 書き戻し先トグル名: N月M週目
- エラー: （あれば）
```

### 3. 最終出力での勧告
全スキル実行後、ユーザー向けの最終メッセージに以下を含める:

- run-log のパス（クリック可能なリンク形式）
- **compact-knowledge の候補件数サマリ**
- **候補が 1 件以上ある場合**: 「⚠️ コンパクション候補 N 件あり。`~/.claude/weekly-reports/run-log/YYYY-MM-DD-compaction.md` を確認のうえ、ルール統合・削除を手動で検討してください」と勧告する
- 候補が 0 件の場合: 「コンパクション候補なし」とだけ表示

勧告は run-log に埋もれさせず、必ずチャット出力に表示する。ユーザーが見落とすと肥大化に気づけないため。

## 注意事項
- 各スキルは元来「ユーザー確認」ステップを含むが、このバンドル経由では**確認を待たず素通り運用**
- ただし **compact-knowledge は検出のみで修正なし**なので素通りでも安全
- 各スキルでエラーが出ても止めず、次のスキルに進む。エラー内容は run-log に記録
- 実行中の出力は最小限に。run-log を見れば結果がわかるようにする
- ユーザー側で問題があれば事後対応（GLOBAL_MEMORY.md / memory/*.md は git で巻き戻し可能、Notionトグルは手動削除）
