# work — AIハーネスの原本

`~/.claude` に置くAIハーネス（CLAUDE.md・ルール・スケジュール済みタスク・設定）の**原本**。
`harness/` が `~/.claude` 直下と 1:1 で対応する。

> **警告: デプロイは、このブランチが `main` にマージされ、`main` を pull した後の
> メインチェックアウトからだけ行うこと。worktree や未マージのブランチからは
> 絶対にデプロイしない。**
> `harness/scheduled-tasks/` と `harness/rules/` 配下のパスは全て
> `C:\Users\nr202\projects\work\harness\`（メインチェックアウト）を指す絶対パスで
> 書かれている。このディレクトリは今回のマージが終わるまで存在しない。
> それより前にデプロイすると、日次タスクは静かに壊れたまま「異常なし」を報告し続ける。
> 例えば `config-health-check` は `stat -c ... 2>/dev/null` が一致しないパスに対して
> 空文字を返すため、差分ゲートがそれを「変化なし」と解釈して点検を一切せずに
> 健全と報告し続ける。`harness-drift-check` は存在しない `scripts/check.sh` を呼ぼうとして失敗する。

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

**`harness/skills/` `agents/` `commands/` `hooks/` は今 `.gitkeep` しか持たない空ディレクトリだが、
削除権限を持つ所有ディレクトリとして意図的に確保してある。**
これらは Claude Code が `~/.claude/skills|agents|commands|hooks` へ書き込む場所と一致する
（UIでスキルやエージェント、コマンドを作るとそこに生成される）。
このリポジトリに存在しないものは所有ディレクトリの中身とみなされ、**次の `deploy.sh` 実行で削除される。**
今は4つとも空なので実害は無いが、UIで何か作った直後にデプロイするとそれが消える
（`backups/harness-deploy/` から復元は可能）。**UIで作ったものを残したいときは、
その実体を `harness/` 側にも追加してコミットすること。**

## テスト

```bash
bash scripts/test-lib.sh && bash scripts/test-deploy.sh && bash scripts/test-check.sh
```

配布先は `HARNESS_TARGET`、原本は `HARNESS_SOURCE` で差し替えられる。
テストは一時ディレクトリに対して動くので `~/.claude` を壊さない。

## 新しいマシンで立ち上げる

`docs/bootstrap.md` を参照。

## 畳む条件

以下のどちらかを満たしたら、この仕組み全体を畳む。

- `harness-drift-check` が **30日連続で異常なしを報告し、かつその間デプロイが1回も無い**
- **複数マシンでのブートストラップ（`docs/bootstrap.md`）が 2027-02-17 までに一度も使われていない**

畳むとは、`harness/` `scripts/` `docs/bootstrap.md` を削除し、`~/.claude` を元の状態
（このリポジトリが取り込む前の、配布物ではない単体のディレクトリ）に戻すことを指す。
