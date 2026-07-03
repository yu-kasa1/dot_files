# サブエージェント連携

> 連携の常時必要なルール（並列実行パターン、各エージェント呼び出し固有ルール、仕様書受け渡し鉄則）。
> 詳細リファレンス（フェーズ巻き戻し判断、エージェント定義メンテ、ドキュメント生成系の細則、仕様書受け渡しの特殊ケース、feasibility.md コミット判定）は `~/.claude/knowledge/agent-collab-detail.md` を必要時に Read。

## 並列実行パターン

依存関係がないエージェントは並列実行してよい。以下が主要な並列実行ポイント。

### 設計フェーズ前段（オプショナル）: feasibility-writer

```
ユーザー要求あり
   │
   ▼
親エージェント: 「道筋が立っているか」4項目チェック
   ├── #1 親が初手で具体的なステップ（1-2-3）を書けない
   ├── #2 外部リソース（AWS/API/ライブラリ等）の制約確認が必要
   ├── #3 複数のアーキテクチャ選択肢が初手で浮かぶ
   └── #4 ユーザーが「実現可能性」「壁打ち」「松竹梅」「どっちがいいか」等を発話
   │
   ├── いずれか該当 → ユーザー確認後 feasibility-writer 起動
   │       → feasibility.md 初期ドラフト生成
   │       → ユーザー回答を親エージェントが Edit で追記
   │       → 方針確定後、requirement-definer (省略可) → spec-writer へ
   │
   └── いずれも該当せず → requirement-definer 直行
```

- feasibility-writer は **オプショナル**。要件が明確で選択肢比較不要なら呼ばない
- 「選択肢が松竹梅でメリデメが分かれる吟味」が必要な時に使う
- 「現状整理」「リスク分析」「STRIDE」は別ドキュメント / 別エージェントの責務、ここでは選択肢比較に専念
- 200〜300 行を目安、肥大化させない

### 設計フェーズ: spec-writer完了後
```
spec-writer 完了
  ├── risk-analyzer（FMEA分析）  ← spec.md を読んで独立にリスク分析
  ├── code-reviewer（設計レビュー） ← spec.md を読んで独立にレビュー
  ├── security-reviewer（STRIDE脅威分析） ← spec.md を読んでセキュリティ観点の脅威分析
  └── performance-reviewer（設計リスク確認） ← spec.md を読んで設計起因のパフォーマンスリスクを分析
全エージェント完了後 → task-writer
```
- 4エージェントとも spec.md を入力とし、互いに依存しない
- security-reviewer は設計段階では **STRIDEチェック（ST-01〜06）のみ** 実施。OWASPチェックはコード実装後に実施する
- performance-reviewer は設計段階では **設計起因リスク（PF-D-01〜07）のみ** 実施。実装レビュー（PF-DB / PF-AP / PF-FE）はコード実装後に実施する
- 全エージェントの結果をユーザーが確認した後、必要な修正を spec.md に反映してから task-writer へ進む

### 実装フェーズ: task-writer完了後
```
task-writer 完了
  └── impact-analyzer（影響範囲調査）  ← tasks.md + 既存コードベースを読んで波及範囲を調査
影響分析の結果をユーザーが確認後 → coder
```
- task-writer が作成したタスク一覧に対して、実装着手前に影響範囲を洗い出す
- 影響分析の結果により、タスクの追加・修正が必要な場合は tasks.md を更新してから coder へ進む

### 実装フェーズ: coder全タスク完了後
```
coder 全タスク完了
  └── code-reviewer(コードレビュー)  ← コード + spec.md を読んで品質チェック
code-reviewer 完了・修正反映後
  └── security-reviewer(セキュリティレビュー) ← コードを読んでセキュリティ特化チェック
security-reviewer 完了・修正反映後
  └── performance-reviewer(パフォーマンスレビュー) ← コードを読んで効率特化チェック
全完了後 → 修正対応 → doc-updater
```
- code-reviewer → security-reviewer は直列実行。品質レビューの修正を反映した状態でセキュリティチェックを行い、観点のブレを防ぐ
- security-reviewer → performance-reviewer も直列実行。security-reviewer と同格の必須ステップ。パフォーマンスに無関係なタスク（DB/描画/ループ/大量データを含まない）でも起動し、その場合は全項目 N/A で簡潔に終える
- test-writer はこのフローとは独立。ユーザーが任意のタイミングで呼び出す
- レビューで修正が発生した場合、修正後に該当チェック項目のみ再判定すればよい（全部やり直し不要）
- **review-coverage workflow 試運転は一時停止中（2026-07-03〜）**: Opus 4.8 の tool_use 不調により workflow 実行が安定しないため、当面は従来フロー（code → security → performance 直列）のみ使用し、**2択提示は行わない**。モデル状況が安定したら（Opus の tool_use 問題解消 or 安定モデルでの workflow 運用確立）2択提示を再開する:
  - A. 従来フロー（code → security → performance 直列、親が逐次呼び出し）
  - B. review-coverage workflow（`Workflow({ name: 'review-coverage', args: { diffRef: '<base-sha>..HEAD' }})`）— dimension別レビュー × 懐疑者3voting で誤判定を間引く試運転版

  再開後は比較データ蓄積のためユーザー指定がない限り 2択提示を必須とする。手応えが固まったら slash command 化を経て従来フローを置き換える可能性あり。詳細は `~/.claude/ideas/review-coverage-workflow.md` 参照
  - **レビュースコープは散文でなく明示指定で固定**: review系 workflow / 並列レビューに渡すレビュー対象は、散文の指示でなく明示ファイルリストまたは `diffRef`（`<base-sha>..HEAD`）で固定する。subagent の scope 引数解釈に依存すると別チケットを誤レビューする（4回連続誤レビューの実例と Collect フェーズによる解消: [#cbt-644-impl-p1]）

### 並列実行時の注意事項
- 並列実行するエージェントの結果はそれぞれ独立してユーザーに提示する
- 修正の適用順序はユーザーが判断する
- 並列実行はあくまで効率化手段。ユーザーが順次実行を希望する場合はそれに従う

---

## サブエージェントへの仕様書受け渡し（鉄則）

- **プロジェクト内に仕様書がある場合**（`docs/plans/` または作業中の `.claude-task/` 等）: ファイルパスを指示すればサブエージェントが自分で読める。追加対応不要
- **プロジェクト外に仕様書がある場合**（`~/.claude/plans/` 等）: 親エージェントが仕様書の内容を読み取り、**サブエージェント起動時のプロンプトにインラインで全文を含めて渡す**
- **要約・抜粋は原則禁止**（情報欠落による手戻りリスク）。レビュー系エージェントへも要約版禁止
- **依頼の意図・背景を併記する**: 仕様書全文だけでなく「このサブエージェントの出力で親側が何を判断する予定か」「上流タスクの全体像と本サブタスクの位置付け」「関連する制約・先行決定」を 1〜3 行で簡潔に添える

特殊ケース（800行超分割、cwd 外リポジトリ、範囲限定レビュー時の渡し方等）は `~/.claude/knowledge/agent-collab-detail.md` の「サブエージェントへの仕様書受け渡し（詳細）」を Read。

---

## 各エージェントの連携固有ルール

各エージェントの責務・対応フロー・必須観点は `~/.claude/agents/*.md` を参照。ここには連携固有のルール（呼び出しタイミング、棲み分け、直列/並列の例外）のみ記載する。

### db-analyzer
- `@spec-writer` の DB 設計時 / `@coder` のマイグレーション・モデル実装時に必要なら呼び出し。単独呼び出しも可。
- **制約**: Docker コンテナ上の DB のみ参照可（本番・ステージング環境は絶対禁止）

### risk-analyzer
- spec-writer 完了後、code-reviewer / security-reviewer / performance-reviewer と並列。既に仕様があれば単独呼び出し可。

### impact-analyzer
- task-writer 完了後、coder 着手前。リファクタリング前にも有効。
- 影響分析結果でタスク追加・修正が必要なら tasks.md を更新してから coder へ。

### feasibility-writer
- 壁打ちフェーズ（requirement-definer / spec-writer の前段）で複数案比較が必要な場合に使用。発動条件・呼び出さない条件・対応フローは前半「設計フェーズ前段」と `~/.claude/agents/feasibility-writer.md` を参照。
- **配置**: `docs/plans/{YYYYMMDD}_{ブランチキー}/feasibility.md`（CLAUDE.md 配置ルール準拠）、200〜300 行目安
- コミット要否判定は `~/.claude/knowledge/agent-collab-detail.md` の「feasibility.md のコミット要否判定」参照

### requirement-definer
- 新機能開発時、`feasibility-writer` の発動条件に該当しないことを確認のうえ呼び出し。該当する場合は feasibility-writer → 方針確定後に requirement-definer。
- 完了・ユーザー承認後に spec-writer を自動呼び出し。

### spec-writer
- requirement-definer 完了後に自動呼び出し。要件が明確なら単独呼び出し可。
- ユーザー承認後、設計レビュー並列フェーズ（risk / code / security / performance）→ task-writer の順。

### task-writer
- 設計レビュー並列フェーズ完了後に呼び出し。仕様が明確なら単独呼び出し可。
- 完了後は impact-analyzer → coder の順。

### test-writer
- このフローから独立。ユーザーが任意のタイミングで呼び出す（テストファースト / 実装後どちらも可）。

### code-reviewer
- 設計段階: spec-writer 完了後、risk-analyzer 等と並列。
- 実装段階: coder 全タスク完了後に単独実行（その後 security-reviewer → performance-reviewer の順）。
- 修正案は**ユーザー確認後**に適用（勝手に適用しない）。

### security-reviewer
- **設計段階**（spec-writer 完了後、並列）: **STRIDE チェック（ST-01〜06）のみ**実施。
- **実装段階**（code-reviewer 完了・修正反映後、直列）: **STRIDE + OWASP 全項目**を実施。品質レビュー修正反映後に行うことで観点のブレを防ぐ。
- **code-reviewer との棲み分け**: code-reviewer は品質・規約・設計総合（セキュリティは観点の一つ）。security-reviewer は STRIDE + OWASP Top 10 を軸にしたセキュリティ特化の深掘り。
- 修正案は**ユーザー確認後**に適用。

### performance-reviewer
- **設計段階**（spec-writer 完了後、並列）: **設計起因リスク（PF-D-01〜07）のみ**実施。
- **実装段階**（security-reviewer 完了・修正反映後、直列）: **PF-DB / PF-AP / PF-FE 全項目**を実施。security-reviewer と同格の**必須ステップ**。パフォーマンスに無関係なタスクでも起動し、その場合は全項目 N/A で簡潔に終える。
- **棲み分け**: code-reviewer（広く浅く検知）/ security-reviewer（セキュリティ特化）に対し、本エージェントは実行効率（N+1 / 計算量 / 無駄な処理 / デッドコード / フロント描画）を深掘り。
- **机上推測の扱い**: 静的推定であり実測プロファイルではない。「ボトルネック確定」等の断定を避け「N+1 が発生する構造」のように構造ベースで報告（CLAUDE.md「机上推測で強い表現を使わない」と整合）。
- 修正案は**ユーザー確認後**に適用。

### coder
- 設計レビュー完了後、ユーザーが実装を希望する場合に呼び出し。仕様設計のみが目的なら自動呼び出しスキップ。
- **タスクごとにユーザー承認**を待ちながら順次実装。全タスク完了後、code-reviewer → security-reviewer → performance-reviewer を直列で呼び出し。
- **coder 起動を省略してよいタスク（親直接実施可）**: エージェント呼び出しオーバーヘッド（1 回 2-5 分）を避けるため親が直接実施してよい。
  - spec.md のサンプル実装を完全コピーするだけのタスク
  - 既存ファイルへの単純 diff 挿入（挿入位置 + 内容が spec.md / tasks.md に完全明記されているケース）
  - sitemap / config 等への定型エントリ追加（1〜数行、既存形式踏襲のみ）

  以下は coder 経由を維持: ロジック設計や既存コード整合調整が必要 / エラーハンドリング判断が仕様未明記 / 既存実装パターンの踏襲先選択判断が必要
- **handover 指示と現状差分の整合確認**: handover に `@coder` 起動指示があっても、修正規模が「spec.md サンプル実装完全焼き込み + 100 行未満 + 1-2 ファイル」なら**coder 経由/親直接 Edit を 2 択でユーザー確認**してから起動。盲従で coder 起動すると SendMessage 5 往復のオーバーヘッドが過大 [#cbt-463-impl-p2]

### doc-updater
- 実装完了後 or PR マージ前にドキュメント整合性を確認。
- 仕様書の更新案は**ユーザー承認後**に適用（勝手に適用しない）。
