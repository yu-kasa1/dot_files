export const meta = {
  name: 'review-coverage',
  description: 'precision機構: dimension別レビュー × 懐疑者3voting で誤判定を間引く。recall機構（マニフェスト/loop-until-dry/完遂クリティック）は次フェーズ',
  whenToUse: '実装フェーズのレビュー連鎖（code/security/performance）の試運転版。フラット並列との差分を観察する目的でも使う',
  phases: [
    { title: 'Collect', detail: 'diff取得専用エージェントが scope の差分を生テキストで収集（基点判断をエージェントから剥がす）' },
    { title: 'Review', detail: 'code/security/performance を pipeline で並列実行（収集済み差分をインライン渡し）' },
    { title: 'Verify', detail: '各findingに懐疑者3voting (既存仕様/到達シナリオ/類似ケース) — 2/3以上が「本物」判定で生存' },
  ],
}

// =====================================================================
// スキーマ定義
// =====================================================================

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    dimension: { type: 'string', description: 'correctness / security / performance のいずれか' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'dimensionプレフィックス + 連番（例: code-001）' },
          title: { type: 'string', description: '短い見出し（30文字以内目安）' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor', 'info'] },
          file: { type: 'string' },
          line: { type: 'number' },
          description: { type: 'string', description: '何が問題か、なぜ問題か' },
          suggestedFix: { type: 'string', description: '修正案（コードスニペット可）' },
        },
        required: ['id', 'title', 'severity', 'description'],
      },
    },
  },
  required: ['dimension', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true=指摘を棄却すべき、false=指摘は妥当' },
    reason: { type: 'string', description: '判断根拠（confidenceが低ければデフォルトrefuted=true）' },
  },
  required: ['refuted', 'reason'],
}

// 前段の diff 取得エージェントの返却型（基点判断をさせず、生の差分だけを収集させる）
const CHANGESET_SCHEMA = {
  type: 'object',
  properties: {
    diffText: { type: 'string', description: 'git diff の生出力をそのまま。差分が無ければ空文字' },
    changedFiles: { type: 'array', items: { type: 'string' }, description: '変更ファイルのパス一覧（--name-only の出力）' },
    untrackedFiles: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          content: { type: 'string', description: '新規ファイルの全文' },
        },
        required: ['path', 'content'],
      },
      description: '未追跡(新規)ファイルとその全文。committed / staged scope では空配列',
    },
  },
  required: ['diffText', 'changedFiles', 'untrackedFiles'],
}

// =====================================================================
// 入力パラメータ: scope（レビュー対象範囲）/ diffRef / repoPath（cross-repo）
// =====================================================================
// args:
//   scope    : 'committed'(既定) | 'staged' | 'working' | 'all'
//              - committed: diffRef のコミット間差分のみ（従来挙動）
//              - staged   : ステージ済みの未コミット変更
//              - working  : 作業ツリーの全未コミット変更（staged + unstaged + 新規）
//              - all      : ベース以降の全変更（コミット済み + 未コミット + 新規）
//   diffRef  : committed / all のベース指定（既定 'HEAD~1..HEAD'）
//   repoPath : 別リポジトリをレビューする場合の絶対パス（cross-repo）

const scope    = args?.scope || 'committed'
const diffRef  = args?.diffRef || 'HEAD~1..HEAD'
const repoPath = args?.repoPath || null

// cross-repo: repoPath があれば全 git を `git -C <path>` 化し、Read も <path> 配下の絶対パスに寄せる
const gitC = repoPath ? `git -C ${repoPath}` : 'git'

// 'all' スコープ用のベース: diffRef のレンジ左辺を抽出（'HEAD~1..HEAD' → 'HEAD~1'、単一refはそのまま）
const baseRef = diffRef.split(/\.\.\.?/)[0] || 'HEAD'

// scope ごとの実行コマンド（前段の diff 取得エージェントに「この通り実行せよ」と渡す）
// listUntracked: 未追跡ファイルを収集する scope のみ設定（committed / staged は対象外 → null）
const SCOPE_COMMANDS = {
  committed: { diff: `${gitC} diff ${diffRef}`, label: `コミット済み差分（${diffRef}）`, listUntracked: null },
  staged:    { diff: `${gitC} diff --staged`, label: 'ステージ済みの未コミット変更', listUntracked: null },
  working:   { diff: `${gitC} diff HEAD`, label: '作業ツリーの全未コミット変更（staged + unstaged + 新規）', listUntracked: `${gitC} ls-files --others --exclude-standard` },
  all:       { diff: `${gitC} diff ${baseRef}`, label: `ベース以降の全変更（${baseRef} → 作業ツリー、未コミット含む）`, listUntracked: `${gitC} ls-files --others --exclude-standard` },
}

// 未知の scope はサイレントに committed へ落とさず明示する（cf. 本ファイル TODO[recall-5]「サイレント・キャップ禁止」）
const VALID_SCOPES = ['committed', 'staged', 'working', 'all']
if (args?.scope && !VALID_SCOPES.includes(args.scope)) {
  log(`[warn] 未知の scope='${args.scope}'。'committed' にフォールバックします（有効値: ${VALID_SCOPES.join(' / ')}）`)
}

const cmds = SCOPE_COMMANDS[scope] || SCOPE_COMMANDS.committed

// cross-repo 時の共通注意（reviewer / verifier の末尾に付与）
const repoNote = repoPath
  ? `\n\n【対象リポジトリ】${repoPath}\n- git は全て \`${gitC}\` を使用（このセッションの cwd とは別リポジトリのため）\n- Read / Grep は ${repoPath} 配下の絶対パスで行う\n- finding の file は ${repoPath} からの相対パスで記載`
  : ''

// =====================================================================
// Collect: diff取得専用エージェントが scope の差分を生テキストで収集する
//   - reviewer に基点(ベース)判断をさせると merge-base / 起点ブランチ最新へ自走し、
//     先行コミットを巻き込む（prompt 抑止では覆らないことを実測で確認済み）。
//   - そこで中立エージェント（agentType未指定）に「指定コマンドの出力をそのまま返す」だけを
//     させ、確定した差分テキストを後段 reviewer にインライン渡しする。基点判断の余地を消す。
// =====================================================================

phase('Collect')

const collectPrompt = `あなたは diff 取得専用です。レビューや良し悪しの判断、基点(ベース)の選択は一切しないでください。指定コマンドの出力をそのまま収集して返すのが唯一の仕事です。

対象範囲: ${cmds.label}

実行すること（この通りに。git merge-base / 別ブランチとの比較 / fetch は禁止）:
1. 差分を取得: \`${cmds.diff}\`
2. 変更ファイル一覧: \`${cmds.diff} --name-only\`
${cmds.listUntracked
  ? `3. 未追跡(新規)ファイル一覧: \`${cmds.listUntracked}\`\n   → 一覧の各ファイルを Read ツールで全文取得（cat ではなく Read を使う）`
  : '（この scope では未追跡ファイルの収集は不要。untrackedFiles は空配列で返す）'}

返却（CHANGESET_SCHEMA に従う）:
- diffText: 手順1の生出力を要約・整形せずそのまま（空なら空文字）
- changedFiles: 手順2のファイルパス配列
- untrackedFiles: ${cmds.listUntracked ? '手順3の各ファイルの {path, content}' : '空配列'}
${repoPath ? `\n対象リポジトリは ${repoPath}。git は全て \`${gitC}\`、Read も ${repoPath} 配下の絶対パスで行う。` : ''}`

const changeset = await agent(collectPrompt, {
  label: 'collect-diff',
  phase: 'Collect',
  schema: CHANGESET_SCHEMA,
})

if (!changeset) {
  log('[error] diff 収集に失敗しました（changeset=null）。中断します。')
  return { confirmed: [], dropped: [], all: [], error: 'collect-failed' }
}

const untrackedCount = changeset.untrackedFiles.length
log(`収集完了: diff ${changeset.diffText.length} 文字 / 変更ファイル ${changeset.changedFiles.length} 件 / 新規 ${untrackedCount} 件`)

// 変更が空なら後段をスキップ（レビュー対象なし）
if (!changeset.diffText.trim() && untrackedCount === 0) {
  log('変更差分が空のためレビューをスキップします。')
  return { confirmed: [], dropped: [], all: [], empty: true }
}

// reviewer に渡す変更差分ブロック（インライン埋め込み）。これが「レビュー範囲の唯一の正」
const untrackedBlock = untrackedCount
  ? '\n\n## 新規(未追跡)ファイル（全文）\n' + changeset.untrackedFiles.map(f =>
      `### ${f.path}\n\`\`\`\n${f.content}\n\`\`\``).join('\n\n')
  : ''

const changesetBlock = `## レビュー対象の変更差分（${cmds.label}）
変更ファイル: ${changeset.changedFiles.join(', ') || '(なし)'}

\`\`\`diff
${changeset.diffText || '(テキスト差分なし)'}
\`\`\`${untrackedBlock}`

// reviewer が git で差分を取り直して基点判断に自走するのを封じる固定指示
const reviewFreeze = `【レビュー範囲の固定・厳守】
- レビュー対象は上記「レビュー対象の変更差分」「新規(未追跡)ファイル」に示された変更のみ。これがレビュー範囲の唯一の正
- git を実行して差分を取り直さないこと。git diff / git merge-base / 別ブランチ比較 / fetch は行わない（基点は確定済み）
- 上記に含まれない変更（先行する他課題のコミット等）は一切レビューしない
- 文脈把握のためのファイル Read / Grep は可。ただし指摘してよいのは上記差分の範囲内に限る`

// =====================================================================
// dimension定義（既存レビューエージェントを利用。差分はインライン渡し済み）
// =====================================================================

const DIMENSIONS = [
  {
    key: 'correctness',
    agentType: 'code-reviewer',
    prompt: `以下の変更差分をコード品質・規約準拠の観点でレビューし、findingsを抽出してください。

${changesetBlock}

${reviewFreeze}

各findingにはid（"code-NNN"形式）、title、severity、file、line、description、suggestedFixを含めてください。
StructuredOutputツール経由でJSON Schemaに従って返してください。修正の自動適用は行わないでください。${repoNote}`,
  },
  {
    key: 'security',
    agentType: 'security-reviewer',
    prompt: `以下の変更差分をSTRIDE + OWASP Top 10観点でレビューし、findingsを抽出してください。

${changesetBlock}

${reviewFreeze}

各findingにはid（"sec-NNN"形式）、title、severity、file、line、description、suggestedFixを含めてください。
StructuredOutputツール経由でJSON Schemaに従って返してください。${repoNote}`,
  },
  {
    key: 'performance',
    agentType: 'performance-reviewer',
    prompt: `以下の変更差分をパフォーマンス観点（N+1、計算量、無駄な処理、フロント描画効率）でレビューし、findingsを抽出してください。

${changesetBlock}

${reviewFreeze}

各findingにはid（"perf-NNN"形式）、title、severity、file、line、description、suggestedFixを含めてください。
パフォーマンスに無関係な変更の場合はfindingsを空配列で返してください。
StructuredOutputツール経由でJSON Schemaに従って返してください。${repoNote}`,
  },
]

// =====================================================================
// 本体: dimension別レビュー → 各findingに懐疑者3voting → 2/3以上で生存
// =====================================================================

phase('Review')

const results = await pipeline(
  DIMENSIONS,

  // Stage 1: dimension別レビュー
  d => agent(d.prompt, {
    label: `review:${d.key}`,
    phase: 'Review',
    agentType: d.agentType,
    schema: FINDINGS_SCHEMA,
  }),

  // Stage 2: 各findingに懐疑者3voting（dimensionごとに即verifyへ流す pipeline）
  (review, dimension) => parallel(review.findings.map(f => () =>
    parallel([
      () => agent(
        `次の指摘が既存仕様/意図的動作かを判定してください。

指摘: 「${f.title}」
詳細: ${f.description}
ファイル: ${f.file}:${f.line}

判定手順:
1. 該当ファイル/周辺コードをRead/Grepで確認
2. コミット履歴やコメントから意図的動作か推定
3. 既存仕様の意図的動作なら refuted=true
4. 確信が持てなければデフォルトで refuted=true（棄却寄り判定）

VERDICT_SCHEMAに従って返してください。${repoNote}`,
        { label: `verify-spec:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      ),
      () => agent(
        `次の指摘が通常運用で到達可能なシナリオを持つか判定してください。

指摘: 「${f.title}」
詳細: ${f.description}

判定手順:
1. 通常運用で発生する具体的なリクエスト/操作シナリオを1つ書き出せるか試みる
2. シナリオを書き出せれば refuted=false
3. 攻撃者/異常入力前提でしか起きない、または書き出せなければ refuted=true

VERDICT_SCHEMAに従って返してください。`,
        { label: `verify-reach:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      ),
      () => agent(
        `次の指摘について、同システム内の類似ケースと挙動を比較してください。

指摘: 「${f.title}」
詳細: ${f.description}
ファイル: ${f.file}

判定手順:
1. 類似機能（他ロール/他テナント/他Controller/他Job等）をGrepで探す
2. 類似ケースで同様の挙動なら「対称」= refuted=true
3. 当該箇所だけ異常な挙動なら refuted=false
4. 類似ケースが見つからなければ confidence低 → refuted=true

VERDICT_SCHEMAに従って返してください。${repoNote}`,
        { label: `verify-symmetry:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      ),
    ]).then(votes => {
      const valid = votes.filter(Boolean)
      const survives = valid.filter(v => !v.refuted).length >= 2
      return { ...f, dimension: review.dimension, votes: valid, survives }
    })
  )),
)

const all = results.flat().filter(Boolean)
const confirmed = all.filter(f => f.survives)
const dropped = all.filter(f => !f.survives)

log(`confirmed: ${confirmed.length} / dropped: ${dropped.length} / total: ${all.length}`)

// =====================================================================
// recall機構の置き場（次フェーズで実装、現在は枠のみ）
// =====================================================================
// TODO[recall-1]: マニフェスト列挙 — 変更ファイル × ルールチェックリストの表をJSで構築
//                 列挙をコード側でやることでマスの取りこぼしを構造的に防ぐ
// TODO[recall-2]: 各マスを多様レンズの finder で埋める（dimension別 finder を pipeline）
// TODO[recall-3]: loop-until-dry — K=2連続で新規finding=0になるまで finder ラウンドを回す
// TODO[recall-4]: 完遂クリティック — 「何を見てない？どのファイル/ルール/経路が未カバー？」専用エージェント
// TODO[recall-5]: サイレント・キャップ禁止 — コスト打ち切りしたマスを log() で必ず明示
//
// 次フェーズの構造案:
//   const manifest = buildManifest(changedFiles, RULE_CHECKLIST)  // 決定論的にJS側で
//   let dryRounds = 0
//   while (dryRounds < 2) {
//     const fresh = await parallel(manifest.map(cell => () => finderAgent(cell)))
//                     .then(rs => rs.flat().filter(novel(seen)))
//     if (!fresh.length) { dryRounds++; continue }
//     dryRounds = 0
//     fresh.forEach(f => seen.add(key(f)))
//     // 既存precision機構に流す
//   }
//   // 最後に完遂クリティック
//   const gaps = await agent('What is not covered?', {schema: GAPS_SCHEMA})

return { confirmed, dropped, all }
