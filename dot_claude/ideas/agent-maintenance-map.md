# agent 保守改革 仕分けマップ（v0 たたき台）

- **作成**: 2026-07-16 セッション
- **目的**: 「保守改革のターン」の初手として、全 agent を「品質強化 / テンプレ厳格化 / 維持保全」の3群に仕分け、以後の改善方向盤を決める
- **前提**: フロー骨格自体は 9合目、これ以上の追加より agent 成果物の質改善の方が投資対効果が高い（2026-07-16 会話結論）
- **決着済み方針**:
  - reviewer 系のライト化は NG（skeptic は false positive 対策で false negative は残るため、前段の質を落とすと全体が崩れる）
  - skeptic pass 導入で findings 統合の判断コストは軽減済み、ここは追加投資不要

---

## 判定軸（4本）

各 agent を以下 4 軸で評価:

| 軸 | 内容 |
|----|------|
| **失敗コスト** | 成果物が誤ってた時の下流被害。high = 直接事故、mid = 手戻り、low = 微修正で済む |
| **成果物の性質** | `判断` / `生成` / `照合` / `統括` のいずれか主体か |
| **改善余地の型** | `深化`（根拠・粒度・見落とし削減）/ `厳格化`（テンプレ・欠落検出）/ `維持保全`（大きな変更不要）/ `縮小・統廃合`（hook 化 / 他 agent 統合 / 削除検討） |
| **skeptic pass 被覆** | adversarial 層で下流補完されるか（○ = される、× = されない） |

---

## 全 agent 仕分けマトリクス

### 群 A: 深化させる（品質強化側）

失敗コスト high or mid、skeptic 未被覆 or 被覆でも false negative リスク残る、根拠・粒度・見落とし削減が投資対象。

| agent | model | 失敗コスト | 主体 | 改善方向 | skeptic被覆 |
|-------|-------|-----------|------|---------|------------|
| **code-reviewer** | opus | high | 判断 | 深化: 根拠必須・file:line 引用強化・reviewer 間重複削減・scope 誤解対策 [#cbt-644-impl-p1] | ○ (下流) |
| **security-reviewer** | opus | high | 判断 | 深化: STRIDE/OWASP チェックリスト明示化・上流防御確認の徹底 | ○ (下流) |
| **performance-reviewer** | opus | high | 判断 | 深化: 「構造で報告、断定しない」の徹底・N+1 判定の grep 根拠必須化 | ○ (下流) |
| **risk-analyzer** | opus | mid | 判断 | 深化: FMEA 網羅性の底上げ・spec 変更時の差分 FMEA 対応 | ○ (下流、設計L) |
| **impact-analyzer** | sonnet | high | 照合 | **深化必須**: pattern 見落とし [#prtp-849-design-p2] 再発防止、safety net として機能させる。model を opus に格上げ検討 | × |
| **investigator** | sonnet | mid | 照合 | 深化: 発火経路網羅の徹底・「該当なし」報告の裏取り [#cbt-940-design-p2] | × |
| **skeptic-reviewer** | sonnet | mid | 判断 | 深化: 根拠なし判定の禁止徹底・lens 越権の抑止 | 自身がskeptic |
| **spec-writer** | opus | **highest** | 生成 | 深化: 既存 return envelope / method binding 等の pattern 見落とし対策、事前 skeptic の適用範囲拡張検討 | ○ (設計Lのみ) |
| **session-evaluator** | opus | mid | 判断 | 深化: 4軸判定の網羅性・claim grounding の裏取り厳格化 | × |

**共通改善方向**:
- **根拠必須ルール**: 全 finding に file:line 引用 or grep 結果を強制
- **粒度統一**: severity 定義の共通化、reviewer 間の粒度ばらつき削減
- **見落とし削減**: 各 reviewer に checklist / patterns の明示化
- **重複削減**: reviewer 間で同一箇所を別 ID で報告するノイズを削る

### 群 B: 厳格化させる（テンプレ・欠落検出）

失敗コスト mid、生成物のテンプレ化余地あり、欠落検出を強化することで下流の手戻り削減。

| agent | model | 失敗コスト | 主体 | 改善方向 |
|-------|-------|-----------|------|---------|
| **requirement-definer** | opus | mid | 生成 | 厳格化: 要件テンプレ欠落項目の検出・仕様曖昧領域の flag |
| **feasibility-writer** | opus | mid | 生成 | 厳格化: 選択肢比較の型（メリデメ・棄却理由・不採用案の明示）強化 |
| **task-writer** | opus | mid | 生成 | 厳格化: 依存関係・完了条件の欠落検出、粒度統一 |
| **test-writer** | sonnet | mid | 生成 | 厳格化: 正常/異常/境界の網羅テンプレ・spec との対応表明示 |
| **doc-updater** | sonnet | low | 生成 | **温存 + 呼び出しトリガー再設計** (2026-07-16 判定): grep 結果から「呼び忘れ」寄りと判定、削除・統合はしない。改修方向は (1) レビューチェーンに組み込み: `coder 完了 → 3 reviewer + doc-updater を並列 spawn`、(2) doc-updater 側に早期リターン判定: 「diff が spec サンプル完全転記型なら追加価値なしでスキップ」（CBT-463 型対策）、(3) 厳格化: 更新提案の根拠必須化・実装/仕様乖離の検出粒度向上 |

**共通改善方向**:
- **成果物テンプレ厳格化**: 欠落しがちな項目を必須化
- **spec との対応**: 生成物が spec.md のどこ由来かを明示
- **柔軟性とのトレードオフ**: 厳格化しすぎると壁打ちフェーズが窮屈になる、feasibility-writer / requirement-definer は "軽さ" とのバランス要注意

### 群 C: 維持保全（大きな変更不要）

失敗コスト low、既に確立、または特殊用途で改修コスト >> リターン。

| agent | model | 主体 | 現状評価 |
|-------|-------|------|---------|
| **coder** | sonnet | 生成 | 実装本体、既に確立。タスク単位承認の集約検討は "フロー改善" 側で別建て |
| **db-analyzer** | sonnet | 照合 | 用途限定 (Docker DB のみ)、現状で機能十分 |
| **investigation-coordinator** | sonnet | 統括 | investigator 統括役、統括ロジックは skeptic 型に近い設計で完成度高 |

---

## 全体観

- **17 agent 中 9つ (群A) が深化対象** = 保守改革の主戦場
- **群A の中でも投資優先度が高い候補**:
  1. **impact-analyzer** — safety net として機能してない再発 [#prtp-849-design-p2] が具体的、model 格上げ + pattern テンプレ強化で効きが早い
  2. **spec-writer** — 失敗コストが全 agent 中最大 (spec 品質が全体を規定)、事前 skeptic 適用範囲拡張の設計判断が要る
  3. **reviewer 3体** (code/security/performance) — 3体まとめて "根拠必須ルール + reviewer 間重複削減" を1回で入れると効率よい

- **skeptic pass 被覆有無で優先度が変わる**: skeptic 下流補完がある reviewer 群より、被覆されない照合系 (impact-analyzer / investigator / session-evaluator) の方が単体品質のインパクトが大きい

- **model 見直し余地**:
  - impact-analyzer: sonnet → opus 格上げ候補（safety net 責務に対して sonnet は軽い）
  - test-writer: 現状 sonnet で妥当、テンプレ厳格化なら sonnet 維持でOK
  - skeptic-reviewer: sonnet 維持推奨（Opus だと過剰慎重で「反証不可」に倒れる体感）

---

## 次のアクション候補（本マップ承認後）

1. **群A から1体選んで深化改修に着手**（impact-analyzer 推奨）
2. **群A の共通改善方向**（根拠必須ルール / 粒度統一）を横串テンプレとして各 agent 定義に注入する規約作り
3. **群B の中で1体選んで厳格化**（task-writer あたりが下流影響大きい）
4. **retrospective / pitfalls / memory を agent 別に集約**して各 agent の "溜まってる痛み" を可視化（=「入り口」の2番目候補だった棚卸しを、マップ作った後の続きとしてやる）
5. **doc-updater をレビューチェーンに組み込む改修** (2026-07-16 追加): `agent-collaboration.md` の「実装フェーズ: coder全タスク完了後」ブロックに doc-updater を並列 spawn として追加、`agents/doc-updater.md` に「spec サンプル完全転記型は早期リターン」判定を追加。auto mode 運用で "呼び忘れ" ていた doc-updater を復権させる小規模改修

---

## 判定軸のブレ候補（レビュー時に議論したい）

- 「**失敗コスト**」の high/mid/low 線引きは主観に寄る。spec-writer を highest にしたが、impact-analyzer も見落とし時の下流被害は同等かもしれない
- 「**改善余地の型**」は 深化 / 厳格化 / 維持保全 の3種に絞ったが、「**縮小・統廃合**」候補があるかは別途検討 (例: doc-updater は hook で自動化できないか)
- 群Cの3体は "手を入れない" 判定だが、coder のタスク単位承認集約は「agent 保守」ではなく「フロー保守」側で扱うべきかもしれない (境界線の議論)
