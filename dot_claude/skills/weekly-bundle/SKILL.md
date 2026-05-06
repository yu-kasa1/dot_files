---
name: weekly-bundle
description: 金曜朝に回す週次レポート3点セット（absorb → weekly-report → notion-weekly-report）を順次自動実行する。
---

# 週次レポート3点セット (weekly-bundle)

## 概要
週次で回す3つのレポートスキルをまとめて順次実行するバンドルスキル。
個別実行の手間を省き、忘れるリスクを下げる。

## 呼び出しタイミング
- 金曜朝（手動 or launchd等の自動実行）
- 週次レポート作成タイミング

## 実行手順

### 1. 各スキルを順次実行
ユーザー確認を待たず、3スキルを連続で実行する:

1. **/absorb**
   - retrospective/handoverから知見を抽出
   - GLOBAL_MEMORY.md に反映
   - 昇格判定の迷いがある知見は「保留」扱い

2. **/weekly-report**
   - 集計期間: 直近木曜終了の7日間
   - 出力先: `~/.claude/weekly-reports/YYYY-MM-DD.md`
   - retrospective/handoverが0件なら最小限レポート

3. **/notion-weekly-report**
   - Notion「日報自分用」ページから今週分の日報を取得
   - 会社提出用フォーマットで本文を生成
   - Notionの同ページ先頭に「N月M週目」トグルとして書き戻す

### 2. 実行ログの出力
全スキル実行後、`~/.claude/weekly-reports/run-log/YYYY-MM-DD.md` にサマリを書き出す（ディレクトリが無ければ作成）:

```markdown
# 週次レポート実行ログ YYYY-MM-DD

## /absorb
- 実行: 成功 / 失敗
- 昇格件数: N / 保留件数: N
- GLOBAL_MEMORY.md 更新: あり / なし
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

## 注意事項
- 各スキルは元来「ユーザー確認」ステップを含むが、このバンドル経由では**確認を待たず素通り運用**
- 各スキルでエラーが出ても止めず、次のスキルに進む。エラー内容は run-log に記録
- 実行中の出力は最小限に。run-log を見れば結果がわかるようにする
- ユーザー側で問題があれば事後対応（GLOBAL_MEMORYは git で巻き戻し可能、Notionトグルは手動削除）
