---
name: review-session
description: セッションの transcript を session-evaluator agent に独立 context で読み込ませて第三者評価する。retrospective の自己評価バイアスを補完するハーネス。**先に /retrospective を回してから本スキルを呼ぶことを強く推奨**。「セッション評価」「第三者レビュー」「自己評価のチェック」等の発話、または `/review-session` で起動。
---

# セッション第三者評価 (review-session)

## 概要
当該セッションの transcript jsonl を `session-evaluator` agent に渡し、独立 context で4軸評価させる。本スキルは**オーケストレーション役**（transcript 特定 → evaluator agent spawn → 結果を Write → サマリ提示）。評価軸の定義と評価ロジックは `agents/session-evaluator.md` 側に焼き付け済み。

## 推奨運用順序（重要・逆転禁止）
1. **`/retrospective`（自己評価）を先に回す** — 自己評価バイアスのない状態で本人の所感を捕捉
2. **`/review-session`（本スキル、独立評価）を続いて回す** — evaluator は retrospective を見ない
3. ユーザーが両者を照合して差分から盲点を抽出

**逆順禁止**: 第三者評価を先にやると、後の retrospective が「指摘を読んだ上での自己評価」になり、自己評価バイアス補完の構造が壊れる。

## なぜ必要か
- retrospective は会話文脈を共有した状態で本人が書くため、自己評価バイアスがある
- 「気づかなかった問題」を retrospective が拾うのは構造的に難しい
- 別 Claude による独立評価で盲点を補完する
- 評価者も Claude なので「同系統のバイアス」（confident hallucination 等）は残るが、当該セッション文脈の引きずりが無い分は確実に独立性が増す

## 引数
- 引数なし: cwd basename から `~/.claude/projects/-{cwd-を-で置換}/` 配下の**最新** `.jsonl` を選択
- 引数 = session-id（UUID、または UUID 先頭 8 文字）: 該当 jsonl を選択
- 引数 = 絶対ファイルパス: 指定 jsonl をそのまま使う

## 実行手順

### 1. transcript の特定
1. cwd を取得（`pwd`）
2. プロジェクト transcript ディレクトリ: `~/.claude/projects/{cwd の / を - で置換}/`（例: `/Users/y.kasai/dot_files/dot_claude` → `~/.claude/projects/-Users-y-kasai-dot-files-dot-claude/`）
3. 引数に従って対象 jsonl を決定:
   - 引数なし → `ls -1t {dir}/*.jsonl | head -n 1`
   - UUID（短縮可）→ glob で前方一致
   - 絶対パス → そのまま
4. 対象 jsonl が存在しなければエラー終了（ユーザーに「対象セッションが見つからない、引数で指定して」と返す）
5. 対象 jsonl のサイズ（行数 + バイト数）を `wc -l -c` で確認し、evaluator へのプロンプトに含める

### 2. 出力先準備
- 出力ディレクトリ: `~/.claude/reviews/{プロジェクト名}/`（プロジェクト名 = cwd basename）
- 出力ファイル名: `{YYYY-MM-DD}_{HHmm}_session-{session-id 先頭 8 文字}.md`
- ディレクトリが存在しなければ `mkdir -p` で作成

### 3. session-evaluator agent の spawn
Agent tool で `session-evaluator` subagent type を起動。プロンプトに含める情報:
- 対象 transcript の絶対パス
- transcript のサイズ（行数・バイト数）
- 対象セッション ID
- 評価日時

**評価軸の詳細プロンプトは agent 定義側（`agents/session-evaluator.md`）にあるため、skill 側で再掲しない**。skill は薄い wrapper として、起動時の固有情報（パス・サイズ・ID・時刻）だけを渡す。

### 4. 評価結果の保存
session-evaluator から返却された Markdown 本文を `~/.claude/reviews/{プロジェクト名}/{YYYY-MM-DD}_{HHmm}_session-{ID}.md` に Write で書き出す。

### 5. ユーザーへのサマリ提示
- 4軸 × severity の件数表
- Critical と Major のみ本文サマリ（タイトル + 1行説明）
- 「詳細は出力ファイル {path} を参照」と案内
- 自己評価（retrospective.md）との照合は**別途ユーザー判断**で実施するよう促す

## 注意事項
- **先に /retrospective を回す順序を厳守**（順序逆転は自己評価バイアス補完の構造を壊す）
- session-evaluator は当該セッション文脈を持たず、retrospective.md / handover.md も見ない
- 評価結果と本人の認識が食い違った場合、初手は人間（ユーザー）が仲裁
- 評価者も Claude なので完全独立ではない（confident hallucination 傾向、同じ訓練データ由来の盲点等）
- 出力ファイルは git 非追跡（`~/.claude/reviews/` は knowledge/ と同じ個人ローカル知識ポリシー）

## 試運転時のチェック
試運転中は評価結果を見た後に自問:
- 評価軸の粒度は適切か（細かすぎ / 粗すぎ）
- severity 分類は妥当か（Critical が過剰 / 不足）
- session-evaluator agent 側のプロンプトに足りない指示はないか
- evaluator の Read 戦略（jsonl 全量 vs 部分）が context 圧迫を起こしていないか

気づきの反映先:
- **評価軸の追加・修正** → `agents/session-evaluator.md`
- **オーケストレーション手順の修正** → 本 SKILL.md

## 関連
- `~/.claude/agents/session-evaluator.md` — 評価軸 4 軸と評価ロジックを焼き込んだ agent 定義
- `~/.claude/skills/retrospective/SKILL.md` — ペアで運用する自己評価 skill（順序: retrospective → review-session）
