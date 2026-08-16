# 新しいマシンでハーネスを立ち上げる

## 1. リポジトリを取得

```bash
git clone https://github.com/ryo12-n/work.git
cd work
```

配置先は任意だが、`harness/scheduled-tasks/` の各タスク定義が
`C:\Users\nr202\projects\work` を絶対パスで参照している。
別の場所に置く場合は、`harness/scheduled-tasks/` 配下のパスを一括で置き換えること。

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
