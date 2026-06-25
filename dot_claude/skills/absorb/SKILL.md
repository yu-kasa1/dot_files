---
name: absorb
description: retrospective/handoverからプロジェクト横断の知見を抽出し、GLOBAL_MEMORY.md（鉄則のみ）または memory/ 配下のトピックファイルに吸い上げる。
---

# 知見の吸い上げ (absorb)

## 概要
retrospectiveとhandoverに蓄積されたプロジェクト固有の知見から、
プロジェクト横断で適用可能なものを抽出し、以下のいずれかに反映する:

- **鉄則**（全セッション共通で常時参照が必要）→ `~/.claude/knowledge/GLOBAL_MEMORY.md` 直接追記
- **トピック別蓄積知見**（特定シーンで参照）→ `~/.claude/knowledge/memory/{category}.md` に追記

個別プロジェクトの経験を**汎用ルール**に昇華させる学習ループ。

## なぜ必要か
- retrospective/handoverの知見はプロジェクト別に蓄積されるが、プロジェクトを跨いで使える学びが埋もれている
- プロジェクト固有MEMORY.mdに書いても、他プロジェクトでは参照されない
- CLAUDE.mdに直接書くとコンテキスト負荷が増大する
- 「同じ失敗を別プロジェクトで繰り返す」のを防ぐ仕組みが必要

## 呼び出しタイミング
- **推奨**: `/weekly-report` の前後（週次で知見を棚卸し）
- **任意**: `/retrospective` 直後に「これはグローバルに使える」と判断した場合
- **任意**: 新プロジェクト開始前に過去の知見を整理したい場合

## 実行手順

### 1. ソースファイルの収集
以下のディレクトリからファイルを収集する:

- `~/.claude/retrospectives/*/` — 全プロジェクトのふりかえりレポート
- `~/.claude/handovers/*/` — 全プロジェクトの引き継ぎノート

**対象期間の決定**:
- 引数なし: 前回の `/absorb` 実行以降のファイル（`GLOBAL_MEMORY.md` 末尾の `last_absorbed` を参照）
- 引数あり: ユーザーが指定した期間
- 前回実行日が不明、またはGLOBAL_MEMORY.mdが存在しない場合は全ファイルを対象とする

### 2. 知見の抽出
各ファイルから以下のセクションを読み取る:

#### retrospectiveから
- **Try** セクション: `適用範囲` と `反映先` を確認
- **抽出パターン > 成功パターン**: `適用条件` を確認
- **抽出パターン > 失敗パターン（アンチパターン）**: `回避方法` を確認
- **pitfalls.md 候補エントリ** セクション: ルール反映候補として既に整形済みのもの

#### handoverから
- **学び** セクション: プロセスに関する知見を抽出
- **ハマりどころ** セクション: 再発しうる汎用的な落とし穴を抽出

### 3. 昇格判定
抽出した知見に対して、以下の基準で判定する。**反映先は組み合わせ可能**（鉄則昇格、topic 追記、pitfalls + ルール反映、保留）。

| 判定 | 基準 | 反映先 |
|------|------|--------|
| **鉄則昇格**（最強格） | 全セッション共通で常時参照が必要、特定シーン非依存（例: 「Grep行番号だけで推測せずRead」「memory claim 記載時の検証済み/未検証推論明示」等） | GLOBAL_MEMORY.md 「鉄則」セクション直接追記。**必ずユーザー確認** |
| **topic 追記** | 適用範囲が「全プロジェクト」だが特定シーン（spec設計時 / agent運用時 / DB調査時 等）で参照されるもの | `memory/{category}.md` のうち該当カテゴリファイル |
| **topic 追記** | 複数プロジェクトで同じ問題が出現（2回以上） | `memory/{category}.md` |
| **topic 追記** | エージェントパイプラインやワークフローの改善 | `memory/agent-ops.md` |
| **pitfalls 集約 + ルール反映** | CLAUDE.md / agents/*.md にルール本文を追加すべき再発リスク（行動指針が明確、具体的なシナリオ説明が必要） | pitfalls.md + CLAUDE.md / agents/*.md |
| **両方** | 汎用ルールで検索可能性も必要 かつ ルール本文反映も必要 | `memory/{category}.md` + pitfalls.md + CLAUDE.md / agents/*.md |
| **保留** | 適用範囲がプロジェクト固有 | (反映なし) |
| **保留** | 技術スタック固有の詳細知識 | (反映なし) |
| **既存** | GLOBAL_MEMORY.md / memory/*.md / pitfalls.md に同等の知見が既にある | 重複排除 |

**カテゴリ → topic ファイル対応**:
| カテゴリ | 反映先ファイル |
|---|---|
| 設計 | `~/.claude/knowledge/memory/design.md` |
| エージェント運用 | `~/.claude/knowledge/memory/agent-ops.md` |
| AWS / インフラ | `~/.claude/knowledge/memory/aws-infra.md` |
| トラブルシューティング | `~/.claude/knowledge/memory/troubleshooting.md` |
| プロセス | `~/.claude/knowledge/memory/process.md` |
| ビルド・検証 | `~/.claude/knowledge/memory/build-verify.md` |
| （新カテゴリ） | 新規 `~/.claude/knowledge/memory/{name}.md` を作成 + `GLOBAL_MEMORY.md` のトピック索引に追加 |

**反映先の使い分け**:
- **GLOBAL_MEMORY.md 鉄則セクション**: 「全セッション共通の鉄則、SessionStart 自動注入、シーン非依存」。**増殖を厳しく抑制**（推奨上限: ~15エントリ）
- **memory/{category}.md**: 「シーン別の1行ルール集、必要時に Read、検索向き」
- **pitfalls.md**: 「retrospective ID 別の経緯アーカイブ、非ロード、ルール反映時の参照元」。CLAUDE.md / agents/*.md のルール本文に `[#xxx]` で参照される

**判断に迷う場合はユーザーに確認する。勝手に判定しない。特に「鉄則昇格」は必ずユーザー確認。**

### 4. ファイル更新
判定結果に従って以下を更新する:

**鉄則昇格の場合** (`~/.claude/knowledge/GLOBAL_MEMORY.md`):
- 「鉄則（全セッション共通）」セクションに1行追記
- ユーザー確認必須。鉄則は常時注入されるため増殖を抑制する

**topic 追記の場合** (`~/.claude/knowledge/memory/{category}.md`):
- ディレクトリ・ファイルが存在しない場合は作成する
- 既存の知見と重複する場合は、より具体的・正確な記述に更新する
- 同カテゴリファイル内に1行追記。サブセクションがあれば該当箇所へ
- 新カテゴリが必要な場合は新規ファイル作成 + `GLOBAL_MEMORY.md` のトピック索引に1行追加

### 5. pitfalls.md の更新 + ルール反映
「pitfalls 集約 + ルール反映」「両方」と判定された知見について、以下を実施:

1. **pitfalls.md にエントリ追加** (`~/.claude/knowledge/pitfalls.md`):
   - アンカー命名規則: `{project-id}-{phase}-{p-num}`（例: `cbt-541-impl-p1`、retrospective ID と一致させる）
   - 内容: 短い結論 + 状況 + 原因 + 教訓（5〜10行）
   - 索引にも追加（ファイル冒頭の一覧）
2. **反映先ファイルへの追記**: CLAUDE.md / agents/*.md に短いルール本文 + `[#xxx]` 参照を追記
   - ルール本文は1〜3行に圧縮
   - 経緯詳細は書かず `[#xxx]` だけで pitfalls.md にリンク
3. **反映先候補の判定基準**:
   - 全エージェント横断、根本的な作業姿勢 → CLAUDE.md
   - 特定エージェントの観点 → 該当 agents/*.md
   - 同時に複数エージェントが該当 → それぞれに追記

### 6. ユーザーへの報告
以下の形式で報告する:

```
## absorb 結果

### GLOBAL_MEMORY 昇格（N件）
| No | 知見 | 出所 | カテゴリ |
|----|------|------|----------|
| 1 | ... | retrospective: {project}/{file} | 設計 |

### pitfalls 集約 + ルール反映（N件）
| No | アンカー | 反映先 | ルール本文（要約） | 出所 |
|----|---------|--------|-------------------|------|
| 1 | #xxx-p1 | agents/spec-writer.md | 〜する前に〜を確認 | retrospective: {project}/{file} |

### 保留した知見（N件）
| No | 知見 | 出所 | 理由 |
|----|------|------|------|
| 1 | ... | retrospective: {project}/{file} | プロジェクト固有 |

### 重複排除した知見（N件）
| No | 知見 | 既存の記載 |
|----|------|-----------|
| 1 | ... | GLOBAL_MEMORY.md の XXX / pitfalls.md の #xxx |
```

ユーザーに確認し、保留した知見の昇格や、昇格した知見の取り消しがあれば反映する。

### 7. メタデータの更新
`GLOBAL_MEMORY.md` 末尾の `last_absorbed` を現在日時に更新する。

## GLOBAL_MEMORY.md / memory/*.md のフォーマット

### GLOBAL_MEMORY.md（鉄則 + 索引のみ）

```markdown
# GLOBAL MEMORY

> プロジェクト横断で適用される鉄則のみ常時注入。トピック別の蓄積知見は `~/.claude/knowledge/memory/` 配下を必要時に Read。

## 鉄則（全セッション共通）

- 知見の記述（出所チケット/プロジェクト）

## トピック別引き出し（必要時に Read）

- 仕様設計・spec-writer 関連 → `~/.claude/knowledge/memory/design.md`
- エージェント運用 → `~/.claude/knowledge/memory/agent-ops.md`
- AWS / インフラ → `~/.claude/knowledge/memory/aws-infra.md`
- トラブルシューティング → `~/.claude/knowledge/memory/troubleshooting.md`
- プロセス → `~/.claude/knowledge/memory/process.md`
- ビルド・検証 → `~/.claude/knowledge/memory/build-verify.md`

_last_absorbed: YYYY-MM-DD_
```

### memory/{category}.md（topic 知見蓄積）

```markdown
# {カテゴリ名}（topic memory）

> {このカテゴリを Read すべきシーンの説明}

- 知見の記述（出所チケット/プロジェクト）
```

**フォーマットルール**:
- 箇条書き中心。1知見1行
- 末尾に出所（チケット名/プロジェクト名）を括弧書きで記載し、「なぜこのルールがあるか」を遡れるようにする
- 鉄則はGLOBAL_MEMORY.mdに、topic 知見は `memory/{category}.md` に配置
- `last_absorbed` は GLOBAL_MEMORY.md 末尾のみに記録し、差分吸い上げの基準点とする（topic ファイル個別の記録は不要）

## pitfalls.md のフォーマット

```markdown
## {project-id}-{phase}-{p-num}

{状況の1段落（何が起きたか）}。**教訓**: {次回の指針 1〜2文}。
```

**フォーマットルール**:
- 見出しは `## {anchor}` 形式。アンカーは retrospective ID と一致させる（例: `cbt-541-impl-p1`）
- 本文は 1段落（5〜10行）。状況・原因・教訓を簡潔に
- ファイル冒頭の「## 索引」にも追記する（`- [#anchor](#anchor) — 一言説明`）
- CLAUDE.md / agents/*.md 側からは `[#anchor]` 形式で参照される（リンク表記ではなく短いタグ表記）

## 注意事項
- **シンプルに保つ**: 箇条書き中心。長文の説明は書かない
- **具体的であること**: 「注意する」のような抽象的な記述は不可。「〜時は〜を確認する」のように行動に落とし込む
- **重複排除を徹底**: 同じ知見が異なる表現で重複しないよう、追記前に既存内容を全文確認する
- **プロジェクト固有知見は昇格しない**: 特定プロジェクトでしか使えない知識はプロジェクトMEMORY.mdに留める
- **ユーザー確認を必ず挟む**: 昇格判定の結果を提示し、ユーザーの承認を得てからGLOBAL_MEMORY.md / pitfalls.md を更新する
- **GLOBAL_MEMORY と pitfalls の役割分担を意識する**: 検索向きの1行ルールは GLOBAL_MEMORY、ルール本文反映の参照元は pitfalls。両方が必要なケースもある
