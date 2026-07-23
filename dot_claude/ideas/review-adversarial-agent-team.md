# レビュー敵対的検証 デチューン設計 — agent team 方式

## 背景
- 既存の review-coverage workflow（dimension別レビュー × 懐疑者3voting）は Workflow tool 依存で、Opus 4.8 の tool_use 不調により運用停止中（agent-collaboration.md「試運転一時停止」）
- Workflow が復活しないと敵対的検証の仕組みが完全に落ちる。従来直列（code → security → performance）は素通しで反証機構なし
- 代替として Workflow tool 非依存・親が Agent tool を並列 spawn する軽量版を用意する
- 設計思想は review-coverage workflow の「Perspective-diverse verify」を継承（同一 skeptic x N ではなく、lens 別 x 3）

## 全体像

```
coder 全タスク完了
   │
   ▼
[従来直列レビュー]
   code-reviewer → security-reviewer → performance-reviewer
   （各 findings を親が保持）
   │
   ▼
[skeptic pass: 3 lens 並列 spawn]
   ├── skeptic-reviewer(lens: 到達性)      ← 全 findings を batch で反証
   ├── skeptic-reviewer(lens: 前段防御)    ← 同上
   └── skeptic-reviewer(lens: 副作用)      ← 同上
   │
   ▼
[親の統合]
   skeptic 3体の反証結果を統合し、findings を「維持 / 格下げ / 取り下げ」に振り分けてユーザーに提示
```

## 新規 agent: skeptic-reviewer

`~/.claude/agents/skeptic-reviewer.md` として新設。

### frontmatter 案
```yaml
---
name: skeptic-reviewer
description: レビュアー（code/security/performance-reviewer）が挙げた findings を、指定 lens の観点から反証しにいく敵対的検証エージェント。findings の取り下げ/格下げを狙って動く（「本当に問題か」を疑う役）。呼び出しは親が3 lens 並列 spawn。
model: sonnet
tools: Read, Glob, Grep, Bash
---
```

### 起動時に受け取る情報
親からのプロンプトで以下をインライン供給:
1. **lens**: `到達性` / `前段防御` / `副作用` のいずれか（1 spawn = 1 lens）
2. **findings リスト**: 反証対象の指摘全件（各 finding に ID / severity / 該当ファイル / 指摘内容 / 提案修正 を含む）
3. **diffRef**: `git diff <merge-base>..HEAD` の基点情報（変更範囲確認用）
4. **技術スタック情報**: 言語 / フレームワーク / ORM 等

### 3 lens の役割

#### lens 1: 到達性 skeptic
- **問い**: 「その経路は実運用で到達するのか？」
- **反証観点**:
  - 該当コードがコメントアウト経路 / dead route / 起動条件不成立で dead code になっていないか
  - コードは存在するが呼び出し元が無い / テスト専用パス
  - リリース済み機能なのか、まだ配備前で表出しないのか
- **典型的な取り下げ判断**: `git grep` で呼び出し元 0 件、feature flag オフ、entry route 未登録

#### lens 2: 前段防御 skeptic
- **問い**: 「上流で既に塞がれてないか？」
- **反証観点**:
  - 上流の FormRequest / middleware / policy / gate ですでに弾かれる
  - フロント側の regex / disabled / readonly 制約で入力自体が来ない
  - DB 制約（NOT NULL / UNIQUE / FK）で二重防御されている
- **典型的な取り下げ判断**: 上流経路の grep で validate/authorize が既に効いている
- 関連 pitfalls: [#prtp-782-p1] [#prtp-782-p2] （PRTP-782 の半角カナ迂回が上流 regex で塞がれていた実例）

#### lens 3: 副作用 skeptic
- **問い**: 「指摘の修正案は既存挙動を壊さないか？」
- **反証観点**:
  - 修正で失われる副作用（掃除ジョブ / throttle / ログ / 権限チェック）はないか
  - 修正がフォールバックとして機能していた既存挙動を破らないか
  - 修正案の対象が他機能から共有参照されている場合の波及
- **典型的な格下げ判断**: 修正案採用で回帰リスクが指摘リスクを上回る
- 関連 pitfalls: [#prtp-813-cleanup-regression] [#cbt-684-design-p2]

### 出力フォーマット（全 lens 共通）

各 finding について次の3判定のいずれかを返す:
- **維持 (upheld)**: 反証できず、指摘は妥当と判断
- **格下げ (downgrade)**: 反証は部分的、severity を1段下げるべき（Critical → Major、Major → Minor 等）
- **取り下げ (dismiss)**: 反証成立、この lens の観点では false positive

各判定に「反証根拠」（実コード引用 / grep 結果 / 到達不能理由）を1〜3行で必ず添える。根拠なしの判定は禁止（skeptic 自体の断定を防ぐ）。

## 親の統合ロジック（agent-collaboration.md 追記部分）

親は 3 skeptic の返答を受け取ったのち、findings 単位で以下の集計を行う:

| 3 lens 判定 | 統合判定 |
|-------------|----------|
| 全 lens で維持 | 維持（そのまま採用） |
| 2 lens で維持 / 1 lens で格下げ or 取り下げ | 維持（reasoning を注記） |
| 1 lens 維持 / 2 lens 格下げ or 取り下げ | 格下げ |
| 全 lens で取り下げ | 取り下げ（ユーザーには「skeptic 3 lens 全否定のため取り下げ」と根拠併記で報告） |

「取り下げ / 格下げ」が生じた場合は必ず反証根拠を併記してユーザーに提示。ユーザーが最終判断を下せる形にする（勝手に消さない）。

## agent-collaboration.md への反映内容

「実装フェーズ: coder全タスク完了後」ブロックに追記:

```markdown
### 実装フェーズ: skeptic pass（敵対的検証）
performance-reviewer 完了後、次を **並列** で spawn:
- skeptic-reviewer(lens: 到達性)
- skeptic-reviewer(lens: 前段防御)
- skeptic-reviewer(lens: 副作用)

各 skeptic には 3 reviewer が挙げた findings 全件と diffRef をインライン供給。
返却後、親が 3 lens 判定を統合（維持/格下げ/取り下げ）してユーザーに提示。
判定変更は根拠併記必須、ユーザー最終判断。

- **スキップ条件**: findings が 0 件、または全て Info レベルの場合はスキップ可
- **Workflow 復活時**: review-coverage workflow へ再統合するか継続するか要検討
```

一時停止中の review-coverage 2択提示ブロックは残置（workflow 復活時の再開条件記述を維持）。

## 未決事項 / 要検討

1. **skeptic 発火閾値**: findings が 1 件だけの場合も 3 lens 並列を回すか、それとも「findings ≥ 2 件」等の閾値を設けるか
2. **skeptic 自身の Sonnet 適性**: 敵対的検証は判断負荷が高い。Sonnet で十分か、opus が要るか（実運用で確認）
3. **既存 pitfalls との連携**: skeptic-reviewer の起動プロンプトに関連 pitfall 群のアンカーを渡し「これらの再発チェックも兼ねろ」とするか
4. **CLAUDE.md 敵対的検証ルールとの重複整理**: 本 skeptic pass 実装後は CLAUDE.md「発火トリガー(b) サブエージェントの findings 引用時」は自動化されるので、ルール本文の圧縮検討
5. **workflow 復活後の去就**: workflow が使えるようになったら review-coverage と本デチューンのどちらを主流にするか、比較データが揃った段階で決める

## 実装ステップ（順序）

1. `~/.claude/agents/skeptic-reviewer.md` 新設
2. agent-collaboration.md 「実装フェーズ: skeptic pass」節追加
3. 試運転: 直近の実装セッション 1〜2件で回してみて、取り下げ / 格下げの妥当性をユーザー主観で評価
4. 3件以上の実データが揃ったら CLAUDE.md 敵対的検証ルールの圧縮を検討
