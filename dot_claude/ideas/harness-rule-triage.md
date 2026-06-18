# ハーネスルール棚卸し（A/B/C 三分類）

> 散文ルールを「強制/自動化（hook・code・schema）へ降ろせるか」で仕分け、hook 化ロードマップを出すための監査ドキュメント。
> 初版 2026-06-09。対象: `CLAUDE.md` / `rules/agent-collaboration.md` / `knowledge/GLOBAL_MEMORY.md` / `settings.json`（agents/*.md は別途）。
> 発端: 2026-06-09 の Claude Code Insights レポート（摩擦の主因＝協働でなくインフラ）→ `[#insight-20260609]`。

## 分類定義

| バケツ | 条件 | 打ち手 | 散文の扱い |
|---|---|---|---|
| **A** | 機械判定可＋ツールイベントに紐づく | 強制 hook（block / 自動実行） | **削除可** |
| **B** | 中身は判断だが「発火条件」はキーワード/コマンドで機械検知できる | 注入 hook（該当時だけ just-in-time 注入） | **常時ONから外せる**（CLAUDE.md/GLOBAL_MEMORY → hook へ移動） |
| **C** | 意味理解が要り発火点も機械検知できない | 散文のまま | **不可分コア** |

原則: **A を削り切る → B で常時ON文脈を減らす → C を研ぐ**。「全部 hook 化」はゴールでない。

## 全体所見（数で見る）

- 操作系ルール ~120 件のうち、**A ≈ 6 / B ≈ 8 / C ≈ 100+**。**機械化可能なのは全体の約1割**。
  → 「hook でハーネスを縛り切る」は構造的に不可能。コアは判断であり、そこは散文 ＋ モデル品質に依存し続ける。
- **enforcement hook 面（PreToolUse / PostToolUse / UserPromptSubmit）は現状ゼロ稼働**。A・B はすべて新規。最大の未開拓レバー。
- **常時ON文脈の肥大**が別軸の課題: `CLAUDE.md`（大）＋ `GLOBAL_MEMORY.md`（157行、SessionStart で毎回注入）＋ handover。B 化はこの文脈ダイエットと同義で、malformed リスク（長コンテキスト悪化要因）低減にも効く。

---

## 現状すでに hard 化済み（settings.json）— 再提案しない

- **permissions.deny**: `git commit/push/merge/rebase/reset --hard`、`rm`、`sed -i`、`mv`、`cp -f`、`sudo`、`Read(.env*)`、`cat .env*`
  → CLAUDE.md「Git は必ず確認」「.env は環境変数管理」等の散文は**既にツール層で強制済み**。理想形。
- **permissions.allow（無確認 read）**: `grep` `rg` `find` `ls` `git diff` `git log`
- **hooks**: `SessionStart`（handover/GLOBAL_MEMORY 注入）、`Notification`/`PermissionRequest`/`Stop`（デスクトップ通知）
- 含意: **書込・削除の破壊系と機密 read は片付いている**。残る A/B は「読み取り様式」「書込前チェック」「判断ルールの just-in-time 配信」の領域。

---

## A: 強制 hook 化候補（機械判定可・ツール連動）

| # | ルール（現在の散文位置） | hook 種別 / matcher | 実装メモ | 削除/縮約できる散文 |
|---|---|---|---|---|
| A-1 | **`cat`/`head`/`tail` で大ファイル全文ダンプ禁止**（CLAUDE.md 作業スタイル `[#env-opus48-toolcall-p1]`） | PreToolUse(Bash) | コマンドが `cat/head/tail` を含み対象が実ファイルなら、行数を測り N 超で deny＋「Read を使え」。`.env*` は既に deny 済みなので汎用版 | 作業スタイルの cat 禁止節を1行 hook 参照に縮約 |
| A-2 | **`docker compose exec` + パイプは `-T` 必須**（GLOBAL_MEMORY トラブルシューティング） | PreToolUse(Bash) | `docker compose exec` かつ `\|` ありで `-T` 無し → deny＋自動修正提案 | GLOBAL_MEMORY 1行を hook へ |
| A-3 | **サブエージェント返送の HTML エンティティ混入チェック**（agent-collaboration「返送内容の検査」） | PreToolUse(Write) | 書込 content に `&lt;`/`&gt;`/`&amp;` を検知したら ask（誤検知あるので block でなく確認） | 検査節を「hook が一次検知」に縮約 |
| A-4 | **プロジェクト lint の自動実行**（rules/development-rule-js/ts/vue/react: `var`禁止/`===`/`any`禁止/eslint-disable禁止 等） | PostToolUse(Edit\|Write) | `package.json` に lint があれば対象拡張子で実行。**本来はプロジェクトの eslint/tsconfig 側で強制すべき**。harness 側は「lint があれば回す」薄いラッパに留める | language ルールの一部を「lint が機械強制」に委譲 |
| A-5 *(低ROI)* | **bash 定番事故**（`--include='*.php'` クォート / `for id in $ids` マルチID 壊れ）（GLOBAL_MEMORY PRTP-813） | PreToolUse(Bash) lint | 誤検知が高くつく。pattern が固いものだけ警告に留める | 据え置き推奨（hook 化の費用対効果低い） |

注: A-1 と「malformed/cat 回避」は **scaffolding でもある**（後述）。hook 化は安い保険だが、モデル更新時にルールごと剥がせるようタグ付けする。

---

## B: 注入 hook 候補（判断要・発火条件は機械検知可）★最もうまみ

機構: `UserPromptSubmit` hook がプロンプトを grep → 該当時だけ関連ルールを context 注入。あるいは `PreToolUse(Bash)` がコマンドを検知 → チェックリスト注入。
**常時 CLAUDE.md/GLOBAL_MEMORY に置く必要がなくなる**＝文脈ダイエットと両取り。

| # | ルール（現在位置） | トリガー（機械検知） | 注入内容 |
|---|---|---|---|
| B-1 | **DB 書込前チェックリスト**（CLAUDE.md ビルド検証 / GLOBAL_MEMORY CBT-684） | PreToolUse(Bash) が `INSERT\|UPDATE\|DELETE\|psql\|mysql.*-e` | DB名/接続ユーザー/コンテナ・ポート/全カラム/重複・FK の5点チェックリスト |
| B-2 | **「別の〇〇」場所確認**（CLAUDE.md 1段検証 `[#sakumon-20260518-p1]`） | UserPromptSubmit が `別テンプレ\|別ファイル\|別シート\|別プロジェクト\|別の` | 「同一ファイル内？別ファイル？を1行確認してから方針を出す」 |
| B-3 | **重い表現の到達性確認**（CLAUDE.md / GLOBAL_MEMORY PRTP-782） | UserPromptSubmit が `脆弱性\|セキュリティ\|迂回\|致命的\|サイレント.*破壊` | 「到達可能シナリオを1つ書けなければ中立表現に落とす」 |
| B-4 | **壁打ち→feasibility-writer 発動**（agent-collaboration 前段） | UserPromptSubmit が `実現可能性\|壁打ち\|松竹梅\|どっちがいい\|方向性` | feasibility-writer 発動条件チェックを提示 |
| B-5 | **CVE/Release Notes 調査の初手**（GLOBAL_MEMORY INFO-57） | UserPromptSubmit が `CVE\|GHSA\|Release Notes\|脆弱性チェック` | `curl api.github.com/.../releases` 初手。※ `cve-triage` skill と一部重複、棲み分け要 |
| B-6 | **ブランチ全体レビューは merge-base 基点**（CLAUDE.md コードレビュー） | UserPromptSubmit が `ブランチ全体\|全体レビュー` | `git merge-base` 基点の明示。※ review-coverage workflow の Collect フェーズ（code 化）が本筋、hook は補助 |
| B-7 | **調査初手のゴール要約確認**（CLAUDE.md 1段検証 `[#cbt-684-design-p1]`） | UserPromptSubmit が Backlog URL / `調査して\|不具合\|バグ` | 「ゴール = X で合ってる？を1行確認してからコード/DB調査」 |
| B-8 | **実機調査セッションの初手3点**（GLOBAL_MEMORY INFO-57） | プロンプトが `本番\|STG\|EC2\|ssh\|実機` | 台数/接続手段/直列か並列か の3点を一問一答で |

含意: 1段検証 family の**大半は B 化できる**。CLAUDE.md「断定する前の1段検証」節を、キーワード gated な注入へ移せば、常時ON の地の文が大幅に減る。

---

## C: 散文のまま（不可分コア、~100+ 件）

機械検知も機械判定もできない純判断。**ここは縛れない＝モデル品質と散文に依存し続ける領域**。hook 化を試みない。代表カテゴリ:

- **設計判断**（GLOBAL_MEMORY 設計 ~40件）: MoSCoW 必須、Won't 根拠先出し、削除波及の洗い出し、副作用列挙、参考実装の無条件踏襲禁止 等。意味理解が本体。
- **1段検証コア**（CLAUDE.md）: 「grep 単独で関数挙動を断定しない」「机上推測で強表現を使わない」「仮説評価が3回揺れたら実機ピボット」。**発火点が"自分の出力生成時"でフック不能**。
- **サブエージェント指摘の反映前チェック**（CLAUDE.md）: 既存仕様か/到達シナリオ/類似ケース比較 — 判断の塊。
- **フェーズ巻き戻し判断**（agent-collaboration）: 判定表はあるが適用は判断。
- **エージェント運用**（GLOBAL_MEMORY ~20件）: サブエージェント起動プロンプトの作法。←一部は「親の Agent 呼び出し作法」で、`PreToolUse(Agent)` 余地はあるが ROI 低、当面 C。
- **コミュニケーション/プロセス**: スコープ外は報告して判断仰ぐ、AskUserQuestion の使い所、`[推奨]/[任意]/[参考]` ラベル 等。

> 注: 今日足した「主張に検証済み/仮説ラベル」`[#insight-20260609]` も発火点が出力生成時のため **C**（hook 化不能）。散文で研ぐしかない。

---

## scaffolding タグ（モデル更新時に剥がす候補）

現行ルールの一定割合は **Opus 4.8 期の足場**。次モデルで死荷重化するので「建築」と区別し、モデル切替時に再評価:

- malformed 回避 / 大ファイル丸読み回避（`[#env-opus48-toolcall-p1]`）→ A-1 で hook 化するが、**hook ごと剥がせる**よう由来を明記
- 並列サブエージェント stall 回避（`[#cbt-644-design-p1]`）の並列度・プロンプト長軽量化
- 「Write を宣言したターンで実行」（呼び忘れ防止）系

運用: これらの散文・hook には `(scaffold: opus-4.8)` 等の印を付け、モデル更新の節目に棚卸しする。

---

## ロードマップ（ROI 順）

1. **B-1（DB 書込前チェックリスト）＋ B-2/B-3/B-7（キーワード注入）を1本の hook 基盤で**
   - `UserPromptSubmit` + `PreToolUse(Bash)` の薄い dispatcher を作り、キーワード表→注入文の対応を1ファイル化。最初の1本で B 機構の型を作る。
   - 効果: 1段検証 family を常時ONから外し、CLAUDE.md/GLOBAL_MEMORY をダイエット。
2. **A-1（cat 大ファイル block）** — 高頻度摩擦の直接根治。insight レポートの筆頭 friction。
3. **A-3（HTML エンティティ）/ A-2（docker -T）** — 局所・低リスク・誤検知少。
4. **A-4（lint 自動実行）** — プロジェクト eslint 側が本筋。harness は薄いラッパのみ。
5. **C の文脈ダイエット**（hook と独立）: GLOBAL_MEMORY の always-on 注入は本当に全件必要か再評価。B 化した分を削り、残りも「pitfalls 方式（参照 on-demand）」へ移せる候補を選別。

## 実装上の注意

- **hook も過剰は禁物**: PostToolUse(test) を毎 Edit は遅い／煩い。high-frequency・mechanically-clear・high-cost のものだけ hook 化（ルールと同じ "縛りすぎ negative" 原則）。過去に Stop hook エラーも踏んでいる。
- **新規 hook 着手前に `claude-code-guide` で出力仕様を確認**（GLOBAL_MEMORY dot_files 20260310 と整合）。PreToolUse の decision/additionalContext、UserPromptSubmit の context 注入の正確な I/F を裏取りしてから書く。
- **誤検知コスト**: block 系（A-1/A-2）は false-positive が作業を止める。最初は `ask` / warn で出して挙動を観察し、安定したら block へ昇格。

## 試運転ログ

### 2026-06-09 B機構プロトタイプ1本目（稼働中）
- **実装**: `~/.claude/hooks/prompt-rule-inject.sh`（UserPromptSubmit hook）。settings.json に配線済み（JSON妥当性確認済）。
- **搭載ルール（4本）**: B-2「別の〇〇」場所確認 / B-3 重い表現の到達性確認 / B-4 壁打ち→feasibility判定 / B-7（実験的）調査初手のゴール要約。
- **文言は active 版**: 単なるリマインダ（読み流せる）でなく「**着手前に1行で確認/表明してから進む**」ディレクティブにした。初版の `…無視可` 表現は焼き付けを殺すので撤去。
- **設計上の気づき**: per-prompt 注入は SessionStart 焼き付けより**強い**（関連した瞬間に直近ターンへ新鮮に載る＝recency 勝ち）。「序盤に保つ」でなく「**発火ターンで実行されたか**」を観る。
- **観察 KPI（重要）**: 注入の成功（機械）でなく**行動が変わったか**。復唱は proxy に過ぎず、"効いた"判定は「実際にその確認を実行したか／行動が変わったか」で行う。cargo-cult な唱和（復唱するが行動不変）に注意。
- **検証済み**: standalone でマッチ/複数マッチ/非マッチ/空/壊れJSON すべて exit 0、誤発火でもプロンプト送信は止めない（block には exit 2 が必要だが未使用）。
- **未着手（次フェーズ）**: ①数セッション観察して過剰発火（特にB-7）/取りこぼしをチューニング ②信頼できたら CLAUDE.md の該当散文を hook 参照に縮約（常時ON文脈ダイエット＝本来の目的） ③型が固まったら PreToolUse 系（A-1 cat block / B-1 DB書込チェックリスト）へ展開。
- **有効化タイミング**: hook 登録は新セッション開始時に読まれるため、観察は次の新規セッションから。

### 2026-06-11 観察1件＋方針転換（B機構は据え置き、投資先を A-1 / review-coverage へ）
- **発火サンプル #1（false positive）**: CBT-638 調査ログを貼った際、参照資料内の「脆弱性」（xmlseclibs GHSA 記述）に B-3 が反応。自分が重い表現で断定する場面ではなく、**引用・貼付資料への誤発火**。トリガーが「プロンプト内のどこかにキーワード」のため資料に反応する precision の穴。
- **誤発火への正しい対応＝非適用と判定してスルー**（律儀な唱和は cargo-cult）。焼き付けの観察は「発火したか」でなく「**適用すべき場面で適用し、不要な場面でスルーできたか**」で見る、が実物で確認できた。
- **長さゲート案は保留**: 「N字超で発火抑止」は誤発火を消すが、初手の長文貼付が本物の依頼のケースを見逃す（false negative）。**n=1 で設計しない**（GLOBAL_MEMORY「エッジケースは最低3件サンプル確認してから設計」と整合）。発火を3件以上溜め、長さ/引用内/初手のどれが true/false を分けるか見てから判断。
- **構造的結論（重要）**: B機構（UserPromptSubmit のトピック注入）は**現在の主戦場（レビュー/調査/単純修正。横展開は終息）に構造的に届かない**。理由＝そこで効く判断ルールは大半がバケツC（発火点が「自分がデスク分析の主張を出す瞬間」でユーザーのキーワードでない）＝UserPromptSubmit では原理的に拾えない。
- **方針**: B hook は **passive で据え置き・追加投資しない**（維持コスト≒0、横展開復活/モデル更新/道具箱流用の実オプション価値で寝かせる）。ハーネス投資は **(1) A-1 cat block（ツール単位＝全セッション種に被覆）** と **(2) review-coverage の地固め（レビュー規律の機械化本体）** へ振る。

### 2026-06-11 A機構1本目: cat ガード（稼働中）
- **実装**: `~/.claude/hooks/bash-cat-guard.sh`（PreToolUse / matcher `"Bash"`）。settings.json 配線済み（JSON妥当性確認済）。
- **判定**: 単純な `cat [flags] file...`（パイプ/リダイレクト/連結なし）で対象が **800行 or 40KB 超**なら **exit 2 でブロック**＋Read/grep 誘導。しきい値はスクリプト冒頭の `LINE_MAX`/`BYTE_MAX` で調整可。
- **設計判断**: 複雑コマンド（`|` `>` `<` `;` `&` `$()` `` ` `` 等）・非cat・ファイル不在・非Bash は全て no-op で素通し（誤ブロック面を最小化）。ブロックは permissionDecision JSON でなく **exit 2+stderr** を採用（より確実な enforcement、hook 出力 API の不確実性に対して堅い）。
- **検証済み**: 9ケース（絶対/相対パスの大ファイル=ブロック、小ファイル/パイプ/リダイレクト/grep/不在/Read/`cat -n`）すべて期待通り。
- **B機構との違い（要点）**: トピック非依存・**全セッション種に効く**＝今の主作業（レビュー/調査/単純修正）に乗る。insight 筆頭 friction（malformed/cat）の直撃。これが「今の自分に効く投資」の本命。
- **有効化**: 次の新規セッションから。**今後の観察**: 誤ブロック（本当に全文が要る正当な cat）の頻度。出たらしきい値か除外条件を調整。

## 関連

- `[#insight-20260609]`（pitfalls）— 発端の insight レポート
- `~/.claude/ideas/review-coverage-workflow.md` — workflow 側の決定論化（Collect フェーズ＝B-6 の本筋）
- `settings.json` — hook/permission の現状
