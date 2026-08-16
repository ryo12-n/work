# 新しいマシンでハーネスを立ち上げる

## 1. リポジトリを取得

```bash
git clone https://github.com/ryo12-n/work.git
cd work
```

**パスはハードコードされている。ユーザー名やリポジトリの配置場所が変わると壊れる。**
移植可能にはしていない — 以下がそのまま書き換えを必要とする箇所。

- `harness/scheduled-tasks/` 配下の各 `SKILL.md` は全て
  `C:\Users\nr202\projects\work\harness\...` を絶対パスで参照している
- `harness/rules/` 配下の各ファイルも同様に `C:\Users\nr202\projects\work\harness\...` を参照している
- `harness/scheduled-tasks/link-integrity-check/linkcheck.sh` と
  `harness/scheduled-tasks/config-health-check/fix-index.sh` は
  Obsidian の保管庫パス `/c/Users/nr202/iCloudDrive/iCloud~md~obsidian/...` を直書きしている

ユーザー名が `nr202` と異なる場合、このリポジトリを `C:\Users\nr202\projects\work` 以外に置く場合、
または保管庫の場所が異なる場合は、上記のファイル群を手動で一括置換すること。
自動化・変数化は行っていない。

## 2. 配布する

```bash
bash scripts/deploy.sh --dry-run   # 何が入るか確認
bash scripts/deploy.sh             # 反映
```

## 3. プラグインを入れる

**プラグインの導入状態はリポジトリで配布できない。**
`~/.claude/plugins/installed_plugins.json` と `known_marketplaces.json` は
絶対パスとタイムスタンプを含むため、別マシンへコピーすると存在しないパスを指す。

`harness/settings.json` の `enabledPlugins` が「何を有効にするか」の宣言を持つ。
実体の導入は Claude Code の対話セッションで行う。

1. マーケットプレイスを追加する

   ```
   /plugin marketplace add anthropics/claude-plugins-official
   ```

2. `harness/settings.json` の `enabledPlugins` に挙がっているものを入れる

   ```
   /plugin install context7@claude-plugins-official
   /plugin install superpowers@claude-plugins-official
   ```

導入後、`enabledPlugins` の記述と実際に入ったものが一致しているか確認する。

## 4. スケジュール済みタスクを登録する

`harness/scheduled-tasks/` の各 `SKILL.md` は配布されるが、
**cron 登録そのものは配布されない。** Claude Code の対話セッションで登録する。

| タスク | cron |
|---|---|
| `obsidian-daily-extraction` | `0 17 * * *` |
| `config-health-check` | `35 17 * * *` |
| `link-integrity-check` | `40 17 * * *` |
| `memory-health-check` | `50 17 * * *` |
| `harness-drift-check` | `55 17 * * *` |

## 5. 確認

```bash
bash scripts/check.sh
```

期待: `異常なし`。
