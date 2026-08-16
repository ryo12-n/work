# work — AIハーネスの原本

`~/.claude` に置くAIハーネス（CLAUDE.md・ルール・スケジュール済みタスク・設定）の**原本**。
`harness/` が `~/.claude` 直下と 1:1 で対応する。

## 使い方

差分を見る（書き込まない）:

```bash
bash scripts/check.sh
```

反映する:

```bash
bash scripts/deploy.sh
```

反映せず差分だけ見る:

```bash
bash scripts/deploy.sh --dry-run
```

## 原則

**同期は一方向（このリポジトリ → `~/.claude`）。**
`~/.claude` は配布物であり原本ではない。**編集は必ず `harness/` で行う。**

`~/.claude` を直接直しても、次のデプロイで巻き戻る。
`settings.json` は Claude Code 自身が書き換えるため、UIでのテーマ変更やプラグイン
有効化も同様に巻き戻る。設定変更は `harness/settings.json` に対して行うこと。

## 配布の規則

| 対象 | 挙動 |
|---|---|
| `harness/` 直下のディレクトリ（`rules/` `scheduled-tasks/` 等） | 丸ごと所有。リポジトリから消したファイルは配布先からも削除する |
| `harness/` 直下のファイル（`CLAUDE.md` `settings.json`） | 上書きのみ。削除しない |
| 配布先のその他（`sessions/` `cache/` `.credentials.json` 等） | 一切触れない |

配布も削除もしない名前: `state.md` / `実行ログ.md` / `.gitkeep`（実行時状態と枠確保用）。

## テスト

```bash
bash scripts/test-lib.sh && bash scripts/test-deploy.sh && bash scripts/test-check.sh
```

配布先は `HARNESS_TARGET`、原本は `HARNESS_SOURCE` で差し替えられる。
テストは一時ディレクトリに対して動くので `~/.claude` を壊さない。

## 新しいマシンで立ち上げる

`docs/bootstrap.md` を参照。
