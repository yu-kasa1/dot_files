# 開発ルール TypeScript

## 型定義
- `any`の直接使用は避け、適切な型を定義する。
- やむを得ず`any`を使用する場合は理由を明確にする。
- `unknown`を`any`より優先し、型ガードで絞り込む。
- Union型やIntersection型を活用し、型安全性を確保する。

## 型アサーション
- `as`による型アサーションは最小限に抑える。
- Non-null assertion (`!`) の使用は避け、適切なnullチェックを行う。
- **例外**: 翻訳キーの動的指定など、ライブラリの型定義上必要な場合は`as any`を許容する。

## interface vs type
- オブジェクトの型定義には`interface`または`type`のどちらを使用しても良い。
- プロジェクト内で一貫性を保つ。

## Enum
- 文字列リテラル型のUnionまたは`as const`を優先する。
- 数値Enumは原則使用しない。

## Null/Undefined
- `null`と`undefined`を明確に区別して使用する。
- Optional chaining (`?.`) と Nullish coalescing (`??`) を活用する。
