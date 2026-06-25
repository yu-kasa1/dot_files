# 開発ルール Vue.js

## コンポーネント設計

### Options APIの使用
- Composition APIではなくOptions APIを使用する。
- オプションの定義順序は`name` → `components` → `props` → `emits` → `data` → `computed` → `methods`の順とする。

### コンポーネント命名
- コンポーネントファイル名はPascalCaseとする。（例：`UserProfile.vue`）
- `name`オプションは必ず定義し、ファイル名と一致させる。

### Props定義
- Props定義には`type`、`required`、`default`を明示的に指定する。
- 複雑な値の検証には`validator`関数を使用する。

```javascript
props: {
  userId: {
    type: Number,
    required: true,
  },
  status: {
    type: String,
    default: 'active',
    validator: (value) => ['active', 'inactive', 'pending'].includes(value),
  },
},
```

### v-modelの実装
- v-model対応には`modelValue`プロップと`update:modelValue`イベントを使用する。

```javascript
props: {
  modelValue: {
    type: String,
    default: '',
  },
},
emits: ['update:modelValue'],
methods: {
  updateValue(value) {
    this.$emit('update:modelValue', value);
  },
},
```

## テンプレート

### ディレクティブ
- `v-if`と`v-for`を同一要素に併用しない。（`v-if`を親要素またはtemplateタグに移動する）
- リスト描画時は一意な`key`を必ず指定する。（indexの使用は避ける）

### 翻訳
- 表示文字列のハードコードを避け、`$t()`を使用する。

```html
<span>{{ $t('messages.success') }}</span>
```

## スタイル

### Scoped CSS
- コンポーネントのスタイルには`scoped`属性を付与する。
- SCSSを使用する場合は`lang="scss"`を指定する。

```html
<style lang="scss" scoped>
.container {
  // スタイル定義
}
</style>
```

### 変数の使用
- 色やサイズなどの値は共通変数を使用する。直接値のハードコードは避ける。

## 状態管理

### ローカルステート
- コンポーネントのローカル状態は`data()`で定義する。
- `data`は必ず関数として定義し、オブジェクトを返す。

### Props/Emitsによるデータフロー
- 親から子へのデータ受け渡しは`props`を使用する。
- 子から親への通知は`emits`を使用する。
- Propsを直接変更しない。変更が必要な場合は`emit`で親に通知する。

## 非同期処理

### async/awaitの使用
- API通信などの非同期処理には`async/await`を使用する。
- ローディング状態の管理には`loaderMixin`を活用する。

### エラーハンドリング
- 非同期処理は`try-catch`で適切にエラーをハンドリングする。

## API通信

### サービス層の利用
- API通信は`services/api.js`で定義されたメソッドを使用する。
- コンポーネント内で直接axiosを呼び出さない。

## パフォーマンス

### 計算プロパティの活用
- 派生データには`computed`を使用する。`methods`内で都度計算しない。
- 複雑な計算を伴うプロパティはキャッシュの恩恵を受けられる`computed`で定義する。
- `computed`内で副作用（API呼び出し、DOM操作等）を発生させない。
- 元の値を変更するメソッド（`push`、`splice`等）を`computed`内で使用しない。

### コンポーネントの遅延読み込み
- ルートコンポーネントや大きなコンポーネントは遅延読み込みを使用する。
- `defineAsyncComponent`または動的インポートを活用する。

```javascript
// ルーティングでの遅延読み込み
const UserProfile = () => import('@/views/UserProfile.vue')

// コンポーネント内での遅延読み込み
import { defineAsyncComponent } from 'vue'
components: {
  HeavyComponent: defineAsyncComponent(() => import('./HeavyComponent.vue')),
},
```

### 不要な再レンダリングの防止
- 大きなリストには仮想スクロールの導入を検討する。
- 頻繁に更新されないデータには`v-once`の使用を検討する。
