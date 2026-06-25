# 開発ルール React

## コンポーネント設計

### 関数コンポーネント
- クラスコンポーネントではなく関数コンポーネントを使用する。
- コンポーネントファイル名はPascalCaseとする。（例：`UserProfile.tsx`）

### Props定義
- Props型は`type`で定義し、コンポーネント名 + `Props`とする。
- childrenを受け取る場合は`React.ReactNode`を使用する。

```typescript
type UserProfileProps = {
  userId: number;
  name: string;
  children?: React.ReactNode;
};
```

### デフォルト値
- デフォルト値は分割代入のデフォルト値構文を使用する。

## Hooks

### 基本ルール
- Hooksはコンポーネントのトップレベルでのみ呼び出す。
- 条件分岐やループの中でHooksを呼び出さない。
- カスタムHooksは`use`プレフィックスを付ける。

### useEffect
- クリーンアップ関数が必要な場合は必ず実装する。
- 副作用の目的をコメントで説明する。

### useMemo/useCallback
- 過度な最適化は避け、パフォーマンス問題が発生した場合に使用する。

## イベントハンドラ
- イベントハンドラ名は`handle`または`on`プレフィックスを付ける。（例：`handleClick`, `onUsernameBlur`）

## 条件付きレンダリング
- 単純な条件は三項演算子または論理AND（`&&`）を使用する。
- `&&`使用時は左辺が`boolean`になるよう注意する（0が描画されないように）。

## キー
- リスト描画時は一意な`key`を必ず指定する。
- indexの使用は静的なリストに限定する。
