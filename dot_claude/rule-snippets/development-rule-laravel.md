# 開発ルール Laravel

## 単一責任の原則
- クラスとメソッドは1つの責任だけを持つ。
- 複雑なロジックは小さな専用メソッドに分割する。

## ファットモデル・スキニーコントローラ
- Controllerはリクエストの受付とレスポンスの返却に専念させる。
- ビジネスロジックはServiceクラスに実装する。
- DB操作はModelまたはRepositoryクラスで行う。(ControllerやServiceで直接行わない)
    - DB操作ロジックをModelに記載するかRepositoryに記載するかは既存実装を参考に判断する。
- FormRequestでバリデーションを行う。
- FormRequest の `field.*` バリデーションルールは array の **value** に適用される (key ではない)。例: `weak_keys.* => ['string', 'max:10']` は value が string であることを要求する。key の長さ・形式を検証したい場合は Custom rule (`function($attr, $value, $fail) { foreach (array_keys($value) as $k) if (strlen($k) > 10) $fail(...) }`) で実装する。バリデーションルール追加時は境界値 4 ケース (正規通過 / 上限超過 / 型違反 / 範囲外) を必ず curl/script で実機確認する [#prtp-834-impl-p3]

## Eloquent
- N+1問題やオーバーフェッチを避けること。
- リレーション使用時は`with()`でEager Loadingを行うこと。
- `with('relation')`の relation 名と、整形メソッド（`toArray` / `toSimpleArray` / `toResourceArray` 等）が参照する `$this->xxx` の名前一致を必ず確認する。同テーブルへの BelongsToMany を pivot フィルタ違いで複数持つモデル（`orgs()` (`wherePivot('is_enabled', 1)`) と `orgsWithDisabled()` の組等）では特に dead eager が起きやすい [#cbt-638-impl-p3]
- N+1 観察は `DB::enableQueryLog → DB::getQueryLog → DB::flushQueryLog → DB::disableQueryLog` の 4 点セットを `try/finally` で包む方式を使う。観察範囲は `map` 等の lazy load 発火元まで try 内に取り込み、finally で disable する前に lazy load を完了させる。`DB::listen` は PHP-FPM / 長寿命プロセス環境でリスナー累積→無関係エンドポイント巻き込みのリスクがあるため request handler 内では使わない [#cbt-638-impl-p1]
- `$fillable`を必ず定義すること。(`$guarded = []`は禁止)

## 翻訳・設定
- 表示文字列のハードコードを避け、`__()`ヘルパーを使用する。
- 翻訳ファイル(messages.php)内の定義は適切なPrefixで階層分けを行う。
- 環境依存の値は`.env`と`config/`で管理する。
- マジックナンバー、マジックストリングを避ける。
- 共通パッケージ（common 等）が `useLangPath` / `useConfigPath` で設定したパスは、アプリ側 `AppServiceProvider::boot()` でさらに後勝ち上書きされうる。spec / 設計ドキュメントに「common 1 ファイル追記で各アプリに解決される」等の挙動を書く際は、対象アプリ全ての `AppServiceProvider::register/boot` を Read で確認すること。`register` だけ読んで `boot` 層の再上書きを見落とすと spec と実コードが矛盾する [#prtp-834-design-p3]

## Blade
- `{{ }}`（エスケープあり）をデフォルトで使用する
- `{!! !!}`は信頼できるデータのみに使用する
- テンプレート内にPHPロジックを書かない

## セキュリティ
- フォームには`@csrf`を必ず含めること。
- 生SQLを使用する場合は必ずバインディングを使用する。
- 生 SQL の bindings 配列に `?` プレースホルダが 3 つ以上 or 重複値（同じ値を複数回渡す）が含まれる場合、bindings 配列の直前に「何個目の `?` に何の値が当たるか」をコメントで明記する。CTE で同じ日付条件を複数回使うケース等で対応関係が読み取れないと、レビュー時に「これ何」となり Edit 往復が増える。

## マイグレーション
- 一度実行されたマイグレーションは変更しない。
- 変更が必要な場合は新しいマイグレーションを作成する。
