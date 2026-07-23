# サブエージェント連携

> 連携の常時必要なルール（並列実行パターン、各エージェント呼び出し固有ルール、仕様書受け渡し鉄則）。
> 詳細リファレンス（フェーズ巻き戻し判断、エージェント定義メンテ、ドキュメント生成系の細則、仕様書受け渡しの特殊ケース、feasibility.md コミット判定）は `~/.claude/knowledge/agent-collab-detail.md` を必要時に Read。

## レビューチェーン運用の基本方針（ノンストップ実行）

- **複数レビュアーを連鎖起動する場合（設計フェーズの 4 並列 + skeptic / 実装フェーズの 3 並列 + skeptic / Mサイズ実装フェーズの 2 並列 + skeptic / その他レビュー系）、途中でユーザー確認を挟まず全 reviewer を走らせ切ってから最後に統合レポートを 1 回だけ提示する**
- 各 reviewer の findings は「案」として蓄積するだけで、修正はチェーン完了後に統合判断でまとめて適用
- **例外的な中断条件**: reviewer が本番影響級の Critical（実行時破壊 / データロス / 重大な認可漏れ等）を出し、後続レビューを止めてでも先に判断が必要な場合のみ中断。それ以外は素通しで完走
- 「chain 途中で 1 reviewer 完了ごとに『どうしますか？』と聞く」動作はやらない。ユーザーの認知負荷を無駄に増やし、統合視点での判断機会を奪うため
- **auto mode state に押されない**: レビューチェーン実行中に auto mode が exit した場合でも、「clarifying question を挟むべし」の誘導に押されて中断報告しない。チェーン実行中は auto mode の on/off に関わらず本節ルールを最優先する [#info145-review-p1]
- サブエージェント側の「修正案はユーザー確認後に適用（勝手に修正しない）」記述は **サブエージェント自身が Edit しない** ことを言っている（親経由の safety guard）。「reviewer 間で親が止まる」意味ではない

## サブエージェント共通契約

以下は全 subagent に適用される契約。個別 agent 定義に同義記述があるものは、本節への参照 1 行（`共通契約 C-N に従う`）に置き換える。集約先を 1 箇所に固定することで、ルール改訂時の更新漏れを防ぐ。

### C-1: 修正・変更は勝手に適用しない（親経由でユーザー承認）
subagent は Edit/Write の提案までを担い、実際の適用は **親エージェント経由でユーザー承認を得てから** 行う。「勝手に修正・追加・更新しない」の禁止事項が全 subagent に効く。適用対象例:
- **生成系** (spec-writer / task-writer / feasibility-writer / requirement-definer / doc-updater): 生成物・更新案の提示止まり
- **レビュー系** (code / security / performance / skeptic-reviewer): findings の提示止まり
- **coder**: タスク単位でユーザー承認を待ってから次へ進む
- **分析系** (impact-analyzer / risk-analyzer / investigator / investigation-coordinator / db-analyzer / session-evaluator): 分析結果の提示止まり

本規約は **subagent 自身が Edit しない** ことを言う（親経由の safety guard）。レビューチェーン中の親側の停止/継続判断は本ファイル冒頭「レビューチェーン運用の基本方針」を参照（reviewer 間で親が止まる意味ではない）。

### C-2: 不明点は勝手に補完せず親経由で確認
情報不足 / 判断保留 / 曖昧領域を検出したら、subagent の主観で補完せず親に質問を返す。親が AskUserQuestion 等でユーザー確認を経て subagent に再入力する。

### C-3: スコープ外の発見は「報告+判断を仰ぐ」
subagent の役割スコープ外で発見した問題は、findings / 分析結果とは分離して報告する。スコープ拡張の判断は親経由でユーザー確認。GLOBAL_MEMORY.md INFO-81「スコープ外の発見は『報告+判断を仰ぐ』」の subagent 適用系。

### C-4: 机上推測で強表現を使わない
「主犯確定 / 最有力 / ボトルネック確定 / サイレントデータ破壊バグ」等の強表現は、実機検証 / grep 裏取り等の根拠がある場合のみ使う。机上推測段階では「〜の可能性がある」「〜の構造」等の中立表現に留める。詳細は `~/.claude/knowledge/verify-rules.md` [#prtp-804-investigate-p1]。

### C-5: レビュー系エージェントの全項目判定ルール
code-reviewer / security-reviewer / performance-reviewer のチェックリスト実施時（skeptic-reviewer は反証結果の出力形式が別なので本項の対象外）:
- 全項目に **PASS / FAIL / N/A** のいずれかを判定、省略禁止
- 該当なしは N/A
- FAIL のみ詳細（問題箇所・影響・修正案）記載、問題なしに無理に指摘を作らない
- severity ラベル粒度: Critical / Major / Minor / Info（各 agent 定義の詳細ルーブリックに準ずる）

---

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

### 設計フェーズ: spec-writer完了後（Lサイズ）
```
spec-writer 完了
  ├─(1) risk-analyzer（FMEA分析）           ─┐
  ├─(2) code-reviewer（設計レビュー）        ─┼─ 4 並列、spec.md を独立入力
  ├─(3) security-reviewer（STRIDE脅威分析）  ─┤
  └─(4) performance-reviewer（設計リスク確認）─┘
   ↓
(5) skeptic pass（findings 0 件や全 Info ならスキップ）
     ├── skeptic-reviewer(lens: 到達性)   ─┐
     ├── skeptic-reviewer(lens: 前段防御) ─┼─ 3 lens 並列 spawn
     └── skeptic-reviewer(lens: 副作用)   ─┘
   ↓
(1)〜(5) 完了後、親が統合レポートを組み立てて一括ユーザー提示 → 採用 findings を spec.md に反映 → task-writer
```
- (1)〜(4) は spec.md を入力とし互いに依存しない。(5) skeptic pass は (1)〜(4) の findings を集約してから走らせるので直列
- **並列実行はノンストップ**（各エージェント完了ごとに親がユーザー確認を挟まない）。(5) 完了時点で親が統合レポートを組み立て、**1 回だけ**ユーザー提示する
- security-reviewer は設計段階では **STRIDEチェック（ST-01〜06）のみ** 実施。OWASPチェックはコード実装後に実施する
- performance-reviewer は設計段階では **設計起因リスク（PF-D-01〜07）のみ** 実施。実装レビュー（PF-DB / PF-AP / PF-FE）はコード実装後に実施する
- **skeptic pass の入力**: (1)〜(4) の findings 全件 + spec.md 全文 + feasibility.md（あれば）。実装フェーズの skeptic pass と同じ 3 lens で反証（「到達性 = その設計フローは実運用で通るのか」「前段防御 = 上流設計で既に塞がれてないか」「副作用 = 設計変更案は他仕様を壊さないか」）
- 統合レポートに対してユーザーが採用 findings を選択後、必要な修正を spec.md に反映してから task-writer へ進む

### 実装フェーズ: task-writer完了後
```
task-writer 完了
  └── impact-analyzer（影響範囲調査）  ← tasks.md + 既存コードベースを読んで波及範囲を調査
影響分析の結果をユーザーが確認後 → coder
```
- task-writer が作成したタスク一覧に対して、実装着手前に影響範囲を洗い出す
- 影響分析の結果により、タスクの追加・修正が必要な場合は tasks.md を更新してから coder へ進む

### 実装フェーズ: coder全タスク完了後（ノンストップ実行 → 最後に一括提示）
```
coder 全タスク完了
  ├─(1) code-reviewer(コードレビュー)         ─┐
  ├─(2) security-reviewer(セキュリティレビュー) ─┼─ 3 並列 spawn（1メッセージ内 3 tool_use ブロック）
  └─(3) performance-reviewer(パフォーマンス)   ─┘
   ↓ 3 reviewer 全完了後、findings を集約
(4) skeptic pass（findings 0 件や全 Info ならスキップ）
    ├── skeptic-reviewer(lens: 到達性)   ─┐
    ├── skeptic-reviewer(lens: 前段防御) ─┼─ 3 lens 並列 spawn
    └── skeptic-reviewer(lens: 副作用)   ─┘
   ↓
(1)〜(4) すべて完了後、親が統合レポートを組み立てて一括ユーザー提示
   ↓ ユーザー判断
修正対応（採用 findings のみ Edit 適用）→ doc-updater
```

**ノンストップ実行の運用ルール**:
- (1)〜(4) は **途中でユーザー確認を挟まず一気に走らせる**。3 reviewer を 1 メッセージ内 3 tool_use ブロックで並列 spawn → 3 reviewer 全完了後、findings を集約して skeptic pass を 3 lens 並列で spawn、を親が自動で連鎖する
- 各 reviewer の findings は「案」として蓄積するだけで、この段階では修正を適用しない（コードは coder 完了時点の状態のまま各 reviewer に見せる。3 reviewer は同一スナップショットに対して独立に別観点で indict する構図なので、findings 受け渡しの必要はなく並列で問題ない）
- **一括提示のタイミング**: skeptic pass 完了 → 親が統合判定 → **1回だけ**ユーザーに findings 一覧を提示（各 finding に 3 reviewer の指摘 + skeptic 3 lens 判定 + 統合判定 + 反証根拠を併記）
- ユーザーは統合レポートに対して「採用する finding」を選択、修正は選択された findings のみ Edit で適用
- **例外的に途中で止める場合**: reviewer が明らかに致命的な発見（本番影響級の Critical / 実行時破壊リスク）を出し、後続レビューを走らせる前にユーザー判断が必要な場合のみ中断。それ以外は素通しで完走する
- test-writer はこのフローとは独立。ユーザーが任意のタイミングで呼び出す

#### skeptic pass（敵対的検証）
3 reviewer（code / security / performance、Mサイズは code / security の 2 reviewer）並列完了後、findings を集約して敵対的に検証する。review-coverage workflow の「Perspective-diverse verify」を Workflow tool 非依存で実装したもの。設計詳細は `~/.claude/ideas/review-adversarial-agent-team.md` 参照。

- **呼び出し規約**: 親エージェントが Agent tool を **3 並列コール**（1メッセージ内に 3 tool_use ブロック）で `skeptic-reviewer` を spawn する:
  - `skeptic-reviewer(lens: 到達性)` — 「その経路は実運用で到達するのか」を反証
  - `skeptic-reviewer(lens: 前段防御)` — 「上流で既に塞がれてないか」を反証
  - `skeptic-reviewer(lens: 副作用)` — 「修正案は既存挙動を壊さないか」を反証
- **各 skeptic への入力（インライン供給必須）**: (1) 担当 lens 指定、(2) 3 reviewer の findings 全件（ID / severity / 元エージェント / 該当ファイル・行 / 指摘内容 / 提案修正）、(3) diffRef（`git diff <merge-base>..HEAD` 相当）、(4) 技術スタック情報
- **スキップ条件**: findings 0 件、または全て Info レベルの場合はスキップ可。ただしスキップ判断はユーザー確認せず親が実施してよい（軽量最適化）
- **統合判定（親の責務）**: 3 skeptic の判定を finding 単位で以下ルールで集計:
  - 全 lens で維持 → **維持**
  - 2 lens 維持 / 1 lens 格下げ or 取り下げ → **維持**（reasoning 注記）
  - 1 lens 維持 / 2 lens 格下げ or 取り下げ → **格下げ**
  - 全 lens で取り下げ → **取り下げ**
- **ユーザー提示**: skeptic pass 完了後、親が統合レポートを組み立てて**1回だけ**ユーザーに提示（3 reviewer findings + 3 lens 判定 + 統合判定 + 反証根拠を併記）。「取り下げ / 格下げ」判定は親が勝手に確定せず、ユーザー最終判断を待つ
- **試運転扱い**: 2026-07-09 に実装フェーズ Lサイズで新規導入。2026-07-13 に **設計フェーズ Lサイズ / 実装フェーズ Mサイズ** にも拡張（データ収集のため頻度多めで運用）。取り下げ/格下げの妥当性は運用しながら検証。手応えが乏しければ設計見直し
- **review-coverage workflow 試運転は一時停止中（2026-07-03〜）**: Opus 4.8 の tool_use 不調により workflow 実行が安定しないため、当面は従来フロー（code → security → performance 直列）のみ使用し、**2択提示は行わない**。モデル状況が安定したら（Opus の tool_use 問題解消 or 安定モデルでの workflow 運用確立）2択提示を再開する:
  - A. 従来フロー（code → security → performance 直列、親が逐次呼び出し）
  - B. review-coverage workflow（`Workflow({ name: 'review-coverage', args: { diffRef: '<base-sha>..HEAD' }})`）— dimension別レビュー × 懐疑者3voting で誤判定を間引く試運転版

  再開後は比較データ蓄積のためユーザー指定がない限り 2択提示を必須とする。手応えが固まったら slash command 化を経て従来フローを置き換える可能性あり。詳細は `~/.claude/ideas/review-coverage-workflow.md` 参照
  - **レビュースコープは散文でなく明示指定で固定**: review系 workflow / 並列レビューに渡すレビュー対象は、散文の指示でなく明示ファイルリストまたは `diffRef`（`<base-sha>..HEAD`）で固定する。subagent の scope 引数解釈に依存すると別チケットを誤レビューする（4回連続誤レビューの実例と Collect フェーズによる解消: [#cbt-644-impl-p1]）

### 並列実行時の注意事項
- 並列実行するエージェントの結果はそれぞれ独立してユーザーに提示する
- 修正の適用順序はユーザーが判断する
- 並列実行はあくまで効率化手段。ユーザーが順次実行を希望する場合はそれに従う
- **「該当なし」報告のうち他 agent の報告領域と観点重複するものは 30 秒 grep で裏取り**: 並列 Explore 等で「該当なし」報告を受けたら、他 agent の報告領域と観点重複する項目に限り自分で grep 裏取りする。「該当なし」には「調査済みで存在しない」と「調査範囲外で気づけなかった」の 2 種があり報告文だけでは区別できない。全項目やる必要はないが、他 agent が触れている領域は誤報告リスクが高い [#cbt-940-design-p2]
- **API エラーで sub-agent が早期終了した場合の fallback**: 並列レビュー中 (risk / code / security / performance) に "Connection closed mid-response" 等の API エラーで sub-agent が失敗したら、無闇に再実行せず、影響度で判断する。M サイズ + バグ修正案件で security-STRIDE / performance-PF-D が N/A 想定なら、親側が該当観点を 30 秒 spot check（grep + 差分観点整理）で補完し「API エラーで未完了、親側スポットチェックで補完」と統合レポートに明記する。L サイズや複雑タスクは再実行を検討。ノンストップ運用中の中間報告は「エラー発生と対処方針」の可視化目的で 1 行だけ許容する [#prtp-849-design-p3]

---

## 派生パイプライン: 小規模タスク（S/Mサイズ）

上記「並列実行パターン」節は **Lサイズ（新機能・複数レイヤー・DB変更あり）** を前提としたフル構成。小規模タスクは以下の派生パイプラインを適用する。

### サイズ判定

ユーザー発話直後、親が主観で `S / M / L` を1行宣言 → ユーザー確認。異論あれば補正。判定と最終差分の乖離は retrospective のスコープ乖離チェックで蓄積し、判定精度を改善する。

粗い目安（機械判定はせず、親の主観 + ユーザー承認で決定）:

| サイズ | 目安 |
|--------|------|
| **S** | バグ修正 / 命名変更 / 局所リファクタ / 数行〜数十行 / 単一ファイル |
| **M** | 既存機能変更 / パターン踏襲 / DB変更なし or 軽微 / 数ファイル |
| **L** | 新機能 / 複数レイヤー / DB変更あり / 影響広い |

### Sサイズパイプライン

```
親直接Edit → code-reviewer 単独
```

- spec.md / tasks.md / feasibility.md 一切不要。CLAUDE.md「例外（バイブコーディング）」の実質統合先
- 親直接Edit の対象例:
  - spec.md のサンプル実装を完全コピーするだけのタスク
  - 既存ファイルへの単純 diff 挿入（挿入位置 + 内容が明確なケース）
  - sitemap / config 等への定型エントリ追加（1〜数行、既存形式踏襲のみ）
- 以下は M へ格上げ検討: ロジック設計や既存コード整合調整が必要 / エラーハンドリング判断が仕様未明記 / 既存実装パターンの踏襲先選択判断が必要
- **handover 指示との整合確認**: handover に `@coder` 起動指示があっても、修正規模が Sサイズ相当なら「S 適用 / L 適用」を 2 択でユーザー確認してから進む。盲従で coder 起動すると SendMessage 5 往復のオーバーヘッドが過大 [#cbt-463-impl-p2]

### Mサイズパイプライン

```
spec軽版（MoSCoW + スコープのみ）→ coder → (code-reviewer / security-reviewer 2 並列 spawn) → skeptic pass
```

- spec-writer は起動するが軽版扱い: MoSCoW / 対象範囲・対象外 / データフロー概略のみ。AC 詳細 / UI 詳細 / エラーコード一覧は省略可
- performance-reviewer は N/A 許容（起動しない、または全項目 N/A で簡潔終了）
- **skeptic pass は必須**（Lサイズと同じ 3 lens 並列 spawn）。findings 0 件 or 全 Info ならスキップ可（ユーザー確認不要、親判断）
- 設計フェーズは spec 軽版のためレビュー並列自体を実施しない → skeptic pass も設計段階では走らせない（実装フェーズのみ）
- risk-analyzer は省略可（ユーザー判断）
- **impact-analyzer は条件付き必須**: API 契約変更（追加フィールド含む）/ 既存関数 signature 変更 / DB schema 変更を含む場合は起動を必須とする。spec-writer の pattern 見落とし（既存 return envelope / method binding / 呼び出し元経路等）を検出する唯一の safety net として機能する。これらを含まないタスク（純粋な UI 変更 / 局所リファクタ等）のみユーザー判断で省略可 [#prtp-849-design-p2]
- feasibility-writer は「4項目チェック」に照らして必要なら起動

### Lサイズパイプライン

前述「並列実行パターン」節を参照。省略なし。

---

## サブエージェントへの仕様書受け渡し（鉄則）

- **プロジェクト内に仕様書がある場合**（`docs/plans/` または作業中の `.claude-task/` 等）: ファイルパスを指示すればサブエージェントが自分で読める。追加対応不要
- **プロジェクト外に仕様書がある場合**（`~/.claude/plans/` 等）: 親エージェントが仕様書の内容を読み取り、**サブエージェント起動時のプロンプトにインラインで全文を含めて渡す**
- **要約・抜粋は原則禁止**（情報欠落による手戻りリスク）。レビュー系エージェントへも要約版禁止
- **依頼の意図・背景を併記する**: 仕様書全文だけでなく「このサブエージェントの出力で親側が何を判断する予定か」「上流タスクの全体像と本サブタスクの位置付け」「関連する制約・先行決定」を 1〜3 行で簡潔に添える
- **subagent 返却 Markdown / コード blob の HTML entities チェック**: spec-writer / task-writer / doc-updater 等が返す本文を Write する前に `grep -cE '&lt;|&gt;|&amp;'` で HTML entities 混入をチェック。ヒットあれば `sed` 等で手デコード（`&lt;` → `<` / `&gt;` → `>` / `&amp;` → `&`）してから Write する。subagent 側 Markdown レンダリング副作用で `Map<...>` 等が `Map&lt;...&gt;` になるケースが実在 [#prtp-848-design-p2]

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
- 設計段階（Lサイズ）: spec-writer 完了後、risk-analyzer 等と並列。**4 並列完了後は親が自動で skeptic pass を連鎖起動**（ノンストップ運用）。
- 実装段階: coder 全タスク完了後、**security-reviewer / performance-reviewer と 3 並列 spawn**（Mサイズは security-reviewer と 2 並列）。**完了後はユーザー確認を挟まず親が自動で skeptic pass を連鎖起動**（ノンストップ運用）。findings は「案」として蓄積のみ、修正は最後の統合提示後にユーザー判断で適用。

### security-reviewer
- **設計段階**（spec-writer 完了後、並列）: **STRIDE チェック（ST-01〜06）のみ**実施。findings は skeptic pass 経由でユーザー提示。
- **実装段階**（code-reviewer / performance-reviewer と並列 spawn / ノンストップ）: **STRIDE + OWASP 全項目**を実施。同一コードスナップショットに対して 3 reviewer が独立に別観点で indict する構図（findings 受け渡しの必要はないため並列で問題なし）。**Mサイズ実装フェーズでも必須**（skeptic pass 前段として、code-reviewer と 2 並列 spawn）。
- **code-reviewer との棲み分け**: code-reviewer は品質・規約・設計総合（セキュリティは観点の一つ）。security-reviewer は STRIDE + OWASP Top 10 を軸にしたセキュリティ特化の深掘り。
- findings は蓄積のみ、修正適用は skeptic pass 完了後の統合提示でユーザー判断。

### performance-reviewer
- **設計段階**（spec-writer 完了後、並列）: **設計起因リスク（PF-D-01〜07）のみ**実施。findings は skeptic pass 経由でユーザー提示。
- **実装段階**（code-reviewer / security-reviewer と並列 spawn / ノンストップ、Lサイズのみ必須）: **PF-DB / PF-AP / PF-FE 全項目**を実施。security-reviewer と同格の**必須ステップ**。パフォーマンスに無関係なタスクでも起動し、その場合は全項目 N/A で簡潔に終える。**Mサイズ実装フェーズでは N/A 許容**（起動しないため、実質 2 並列 spawn = code / security のみ）。
- **棲み分け**: code-reviewer（広く浅く検知）/ security-reviewer（セキュリティ特化）に対し、本エージェントは実行効率（N+1 / 計算量 / 無駄な処理 / デッドコード / フロント描画）を深掘り。
- **机上推測の扱い**: 静的推定であり実測プロファイルではない。「ボトルネック確定」等の断定を避け「N+1 が発生する構造」のように構造ベースで報告（CLAUDE.md「机上推測で強い表現を使わない」と整合）。
- findings は蓄積のみ、修正適用は skeptic pass 完了後の統合提示でユーザー判断。

### skeptic-reviewer
- **発火範囲（試運転中は頻度多めで運用、2026-07-13〜）**:
  - **設計フェーズ Lサイズ**: spec-writer 完了 → 4 並列レビュー（risk / code / security / performance） → skeptic pass。入力は 4 findings + spec.md（+ feasibility.md）
  - **実装フェーズ Lサイズ**: coder 全タスク完了 → 3 並列レビュー（code / security / performance） → skeptic pass。入力は 3 findings + diffRef
  - **実装フェーズ Mサイズ**: coder 全タスク完了 → 2 並列レビュー（code / security） → skeptic pass。入力は 2 findings + diffRef（performance は N/A 許容のため 2 reviewer 前提）
  - **設計フェーズ Mサイズ / Sサイズ全般**: 対象外。設計 M は spec 軽版でレビュー並列自体を実施しないため。S は code-reviewer 単独で完結
- **呼び出し規約**（設計 / 実装共通）: 親が Agent tool を 3 並列コール（1メッセージ内 3 tool_use ブロック）で `skeptic-reviewer` を spawn。lens は `到達性 / 前段防御 / 副作用` の 3 種で固定。詳細な入力仕様・統合判定は「実装フェーズ: coder全タスク完了後 → skeptic pass」節および「設計フェーズ: spec-writer完了後」節を参照。
- **宣言と実行の同一メッセージ化**: 「3 並列で起動します」等の宣言をしたら、そのメッセージ内で 3 個の Agent tool_use ブロックを並べて送信する。宣言だけで次ターンに tool_use を回すと 1 lens だけ実行され並列規約が崩れる。CLAUDE.md [#info-33]（宣言と実行を同じレスポンスに収める）の並列 subagent 版として厳守 [#prtp-848-design-p1]
- **棲み分け**: code/security/performance-reviewer / risk-analyzer が「問題を探す」役なのに対し、skeptic-reviewer は「本当に問題か疑う」役。同じ findings を逆向きに検証する。
- **スキップ判断**: findings 0 件 or 全 Info の場合は親判断でスキップ可（ユーザー確認不要）。
- **単独利用**: 過去のレビュー結果に対して後日 skeptic pass だけかけたい場合も単独 spawn 可。その際も lens 別 3 spawn の並列規約は維持する。
- **@skeptic-reviewer 単独指名 + 生 diff レビュー依頼の解釈**: findings 前提のため「skeptic-reviewer は単独で生 diff を見られない」と機能不整合を返すのではなく、「敵対検証込みで厳選 findings が欲しい = フル flow + skeptic pass のショートカット表現」として第一候補で解釈する。初手で「フル flow + skeptic pass で回します」と宣言し、必要なら「フル / findings 持ち込み型」の 2 択で確認する [#info145-review-p2]
- skeptic pass 完了後、親が統合レポートを組み立ててユーザーに一括提示。判定変更（取り下げ/格下げ）はユーザー最終判断待ち。

### coder
- 設計レビュー完了後、ユーザーが実装を希望する場合に呼び出し。仕様設計のみが目的なら自動呼び出しスキップ。
- **タスクごとにユーザー承認**を待ちながら順次実装。全タスク完了後、code-reviewer → security-reviewer → performance-reviewer を直列で呼び出し。
- **サイズ別扱い**: S/M サイズ判定時は「派生パイプライン: 小規模タスク」節を参照。Sサイズは親直接Edit（coder 起動しない）、Mサイズは spec軽版経由で起動。coder 起動省略の判定基準・handover との整合確認も同節に集約。

### doc-updater
- 実装完了後 or PR マージ前にドキュメント整合性を確認。
- 仕様書の更新案は**ユーザー承認後**に適用（勝手に適用しない）。
