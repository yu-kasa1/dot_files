# レビュー網羅機構（ワークフロー企画案）

## 背景
2026-06-02、別件マルチタスクの片手間でワークフローの使い方を壁打ちしていて派生。発端は2つ:

1. ワークフローを使って**レビュー / 不具合調査を効率化したい**（いずれ自分の手数を判断ポイントだけに絞りたい）
2. **最近レビューが漏れてるかも**という不安 → 網羅的に見る機構が欲しい

## 出発点の気づき（認識のずれを1個潰した）

「3エージェント並列で動かす」だけのワークフローは、**チャットで『3並列でレビューして』と命令するのとほぼ変わらない**。並列そのものには価値がほぼ無い。ワークフローの本体は**並列の"先"にある多段構造**（fan-out → 検証 → ループ → 統合）。リッチさを期待するなら、ここを設計しないと意味がない。

## 2軸を分離する（ここが整理の肝）

レビュー改善は別物の2軸に分かれる。混ぜると設計がぼやける。

- **precision（誤判定の間引き）**: サブエージェントの「要修正」の半分は既存仕様の誤判定。これを人間に届く前に潰す
- **recall（漏れ防止）**: 「網羅的に見たい」。見るべき対象を構造的に取りこぼさない

順番は **recall を上げてから precision で絞る**（広く出す → 固く検証する）。

---

## precision 機構: 「反映前チェック」を検証段に焼く

CLAUDE.md の「サブエージェント指摘の反映前チェック」（既存仕様か / 到達シナリオ書けるか / 類似ケース比較）は、今は指摘が来るたびに**手で1段検証**している。これを**懐疑者の多数決**として自動化する。

```js
pipeline(
  DIMENSIONS,  // [correctness, security, perf, rule準拠]
  d => agent(reviewPrompt, {agentType: d.agent, schema: FINDINGS}),

  review => parallel(review.findings.map(f => () =>
    parallel([
      () => agent(`「${f.title}」は既存仕様か。実コードをgrep/Readし意図的動作なら refuted=true`, {schema: V}),
      () => agent(`「${f.title}」の到達シナリオを1つ書け。書けなければ refuted=true`,        {schema: V}),
      () => agent(`「${f.title}」を類似ケース(他ロール/他テナント)と比較。対称なら refuted=true`, {schema: V}),
    ]).then(votes => ({...f, survives: votes.filter(v => !v.refuted).length >= 2}))
  ))
).flat().filter(f => f.survives)   // 2/3以上が「本物」と認めた指摘だけ親に上げる
```

- 懐疑者は**疑う方向**（default refuted=true、確信なければ棄却）でプロンプトする
- 自分が**ルールとして言語化済み**なので「良い間引き」の定義が既にある＝焼ける

### スキーマ定義

agent() の `schema:` に渡すスキーマ。雛形では FINDINGS と VERDICT の2種。

**FINDINGS**（dimension別レビューの返却）
```
{
  dimension: 'correctness' | 'security' | 'performance',
  findings: [
    { id, title, severity: critical|major|minor|info, file, line, description, suggestedFix }
  ]
}
```

**VERDICT**（懐疑者1票の返却）
```
{
  refuted: boolean,   // true=指摘を棄却、false=指摘は妥当
  reason: string      // 判断根拠。confidence低なら refuted=true（棄却寄り）
}
```

3票のうち **2票以上 `refuted=false`** で finding 生存。1票・0票なら親に上げない。

---

## recall 機構: 「網羅的に見る」の実体

### ① マニフェスト列挙（決定論的・JS側でやる、モデルにやらせない）
「変更ファイル × ルールチェックリスト」の表を**コードで**作る。列挙をコードでやると**マスが構造的に飛ばせない** = 列挙した次元の漏れは原理的に起きない。

```
[UserController.php] × [N+1, $fillable, $e->getMessage()漏れ, FormRequest委譲]
[SendJob.php]        × [$timeout vs retry_after, ...]
```

### ② 各マスを多様レンズの finder で埋める（①の上を pipeline）

### ③ loop-until-dry
開放的な「他に何かある？」枠は **K回連続で新規ゼロになるまで**回す（既出と dedup）。任意の数で止めず**井戸が枯れたら止める**。「漏れてるかも」への直接回答。

### ④ 完遂クリティック
最後に1体、**「何を見てない？どのファイル/ルール/経路が未カバー？」だけ**を仕事にするエージェント。穴が次ラウンドのタスクになる。

### ⑤ サイレント・キャップ禁止
コスト/時間で打ち切ったマスは**必ずログ**（自分のルール）。「全部見た」の誤認が一番危ない。

---

## 「同じエージェント×N を突き合わせ」への結論

**完全な無駄ではないが最低ROI。** 温度ゆらぎで毎回違う指摘は出る（self-consistency）から union は増えるが、増分は細い。同じ枠組みは**系統的な盲点を全員でスルー**する。

→ **冗長（同じレンズ×N）より多様（違うレンズ×N）が recall で圧勝。** 同じ予算なら別々の担当を割る。

## 規格化の置き場（エージェント vs ワークフロー）

| 対象 | 規格化の手段 | 理由 |
|---|---|---|
| **固定の連鎖**（レビュー: 常にこの観点を並列→verify） | **保存済みワークフロー** `.claude/workflows/review.js`（meta.name で命名、名前で再利用、resume 可、決定論的） | 並列数・順序が固定 |
| **動的 fan-out**（調査: 論点数が読めない・findings次第で枝分かれ） | **コーディネータ・エージェント**（= `investigation-coordinator`）or ワークフローの loop | 分岐にモデル判断が要る |

「3並列を新しいエージェントに畳む」は不可（サブエージェント=1コンテキスト・1ワーカー）。固定型は**エージェントでなくワークフローに規格化**するのが筋。動的型は investigation-coordinator が既にその答え。

## 自分固有の強み（他人には作れない理由）
CLAUDE.md のレビュールール（キュー `$timeout` vs `retry_after`、ブランチ全体レビューは merge-base 基点、`$fillable` 必須、N+1、`$e->getMessage()` 露出 等）が**そのままマニフェストの列 / 検証基準**になる。チェックリストを書き切っている人間だから列挙が即できる。他人がこの機構を作っても「何を網羅すべきか」の表が無くて機能しない。

## コスト注意（workflow-cost-awareness メモと整合）
マニフェスト × 多様レンズ × loop-until-dry は**エージェント数が膨張**し5時間枠を食う。
- verify / 単純判定 → **haiku**、find系 → **sonnet** に落とす
- ルール列挙で**ラウンド上限**を決める
- 打ち切ったマスは**ログ**（サイレント・キャップ禁止）

## 試運転計画
1. **レビュー1本から**（最も決定論的・低リスク、全 Read 専用で事故らん）。実装フェーズのレビュー連鎖（code → security → performance）を**適当な diff 1本**に回す最小版
2. **フラット並列との差を体感**してから、設計フェーズの4並列に拡張
3. 調査は2番手。論点抽出＋並列調査までを巻き、**実機検証ピボットは手元に残す**前提で設計（机上の限界を"検出して停止"はできる、が実機は触れない）

### 試運転対象 diff の選定基準

「適当な diff 1本」を具体化:

- **規模**: 5〜20ファイル / 数百〜千行程度の中規模。小さすぎるとフラット並列との差が出ず、大きすぎると5時間枠＆エージェント1000体制限を圧迫
- **種類**: 実装ロジックを含む diff（リファクタ / ドキュメント変更のみは precision の効果も recall の効果も出にくい）
- **基点**: ブランチ全体レビュー時は `git merge-base develop HEAD`（CLAUDE.md「ブランチ全体レビュー時の基点選定」と整合）
- **書き込みリスク**: workflow 内のエージェントは全 Read 専用前提。書き込み発生はしない
- **最初の1本のおすすめ**: 自分が把握済みのコミット / PR を選ぶと「指摘の妥当性」を自分で評価でき、precision機構の効き目を判定しやすい。例: dot_files の `6b2f291`（performance-reviewer 新設）は規模・既知度ともに手頃

呼び出し方:
```
Workflow({ name: 'review-coverage', args: { diffRef: '<base-sha>..HEAD' } })
```

## 実装の現状（2026-06-04）

- **雛形配置済み**: [`dot_claude/workflows/review-coverage.js`](../workflows/review-coverage.js)
  - precision機構のみ実装（dimension別レビュー × 懐疑者3voting、2/3生存ルール）
  - recall機構は同ファイル末尾にTODOコメント＋次フェーズ構造案を残置
- **試運転**: 未実施。雛形は配置直後にスキル一覧へ自動認識される（`.claude/workflows/` 配下を Claude Code が自動拾い）
- **次の一手**: 試運転対象 diff を選んで Workflow 経由で実走 → フラット並列との差を観察 → 結果を articles/ 配下に下書き

## insight レポート（2026-06-09）からの補強材料

Claude Code Insights レポート（`dot_claude/usage-data/report-2026-06-09-113428.html`）の "On the Horizon: Self-Verifying Parallel Code Review Pipeline" が本案の precision 機構（懐疑者3voting）と方向一致していた。次フェーズ実装時に取り込む具体案:

- **scope は prose でなく file/JSON で渡す**: Collect フェーズで `git diff` の変更ファイル・hunk を `review_scope.json` に書き出し、reviewer には散文でなくこのファイルを読ませる（誤スコープレビューの根治。`[#cbt-644-impl-p1]` と整合）
- **Verify gate を VERIFIED/REFUTED/UNCERTAIN の3値に**: 現状の懐疑者 voting は refuted の2値だが、HIGH/MEDIUM finding を「独立に再 Read し可能なら再現を構築 → VERIFIED / REFUTED / UNCERTAIN」で判定して REFUTED を破棄、UNCERTAIN は人間に残す（机上の限界を"検出して停止"する既存方針と整合）
- **finding の検証ステータスを成果物に明示**: 親へ上げる summary で各 finding に検証ラベルを付ける（CLAUDE.md「主張に検証済み/仮説を明示」と同根）

## 関連
- `~/.claude/ideas/investigation-coordinator.md` — 調査側の動的並列（本案と二刀流で完成）
- `~/.claude/articles/backlog.md` — 勉強会 / 記事ネタ。本案は「レビュー/調査をワークフローに巻き取り始めた（現在進行形）」として**勉強会の次の弾**に使える
- メモリ: `workflow-cost-awareness`（5時間枠とモデル振り分け）
