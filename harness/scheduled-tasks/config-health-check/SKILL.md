---
name: config-health-check
description: Claude Code の設定・スキル・ルールが公式のベストプラクティスに沿っているかを毎日点検し、機械的に直せるものは直す
---

Claude Code の設定・スケジュール済みタスク・ルールファイルが、公式ドキュメントのベストプラクティスに沿って保たれているかを点検する。

**点検対象はリポジトリの原本（`C:\Users\nr202\projects\work\harness\`）である。**
`~/.claude` は配布物であり、直接直しても次のデプロイで巻き戻る。
直したら `bash "C:/Users/nr202/projects/work/scripts/deploy.sh" --yes` まで実行すること。

**この点検は毎日走るが、対象はほとんど変化しない。差分ゲートを最初に通し、変化がなければ即終了すること。**
毎日フル点検すると必ず空洞化する（この保管庫の持ち主には「新しい生活習慣は空洞化して停止する」という
自己傾向が記録されている）。

## 1. 差分ゲート（最初に必ずやる）

`C:\Users\nr202\.claude\scheduled-tasks\config-health-check\state.md` を読む。
前回の点検日時、各対象ファイルの mtime、空振り連続日数が記録されている。
ファイルが無ければ初回。全対象をフル点検して state.md を新規作成する。

対象ファイルの現在の mtime を取る。

```bash
cd "C:/Users/nr202/iCloudDrive/iCloud~md~obsidian" && stat -c '%Y %n' "C:/Users/nr202/projects/work/harness/settings.json" "C:/Users/nr202/projects/work/harness/rules/"*.md "C:/Users/nr202/projects/work/harness/scheduled-tasks/"*/SKILL.md "C:/Users/nr202/projects/work/harness/CLAUDE.md" "C:/Users/nr202/.claude/rules/保管庫索引.md" $(grep -oP '\]\(\K[^)]+' "C:/Users/nr202/.claude/rules/保管庫索引.md") 2>/dev/null
```

**索引の正本は保管庫の外**（`C:\Users\nr202\.claude\rules\保管庫索引.md`・2026-08-18〜）。
保管庫側の `personal\AIメモリ\MEMORY.md` は移転先を指すポインタなので、**そこから対象を取らない。**
取ると対象リストが空になり、エラーを出さずにこの点検が空回りする。

**保管庫側の対象は索引から動的に取る。**保管庫は再編の途中で、
ルールや進捗の実パスがセッション単位で動く。ここにパスを直書きすると、
このタスク自身が「参照先が実在しない」状態になる。

- **前回から mtime が変わったファイルが1つも無ければ**、第2〜4節を飛ばして第5節（整合性チェック）だけ実行し、
  「変化なし」と1行で報告して終了する。空振り連続日数を +1 して state.md を更新する
- 変わったファイルがあれば、**そのファイルだけ**を第3節の観点で精査する
- ただし**月に1回（毎月1日）は、mtime に関係なく全対象をフル点検する。**
  公式ドキュメント側の変更を拾うため

## 2. 公式ドキュメントの参照（フル点検の日だけ）

差分点検の日は、下の固定チェックリストだけで判定する。context7 を引かない。

フル点検の日（毎月1日と初回）だけ、context7 MCP で公式ドキュメントを引いて
チェックリスト自体が古くなっていないかを確認する。ライブラリIDは
`/llmstxt/code_claude_llms_txt`（code.claude.com の公式 llms.txt）。
**呼び出しは1回の点検で最大3回まで。**引く観点は以下に絞る。

- CLAUDE.md / メモリの推奨（行数上限、チートシート方針、rules との使い分け）
- SKILL.md の frontmatter と description の書き方、progressive disclosure
- settings.json の推奨構造（permissions の allow/deny、hooks、$schema）

**取得結果をファイルに保存しない。**キャッシュファイルを作らないこと。
チェックリストが公式と食い違っていたら、このタスクの SKILL.md（第3節）を直接書き換える。

## 3. 固定チェックリスト

### 全ファイル共通
- **参照しているパスが実在するか。**`@` import、ドキュメント内のパス、bash コマンド内のパスすべて。
  これが過去に実際に壊れた項目（2026-08-16 に CLAUDE.md の @import 4本と
  日次タスクのパス全部がリンク切れになっていた）。**最優先で見る**
- 相対日付（「先週」「今月」「最近」）が残っていないか。絶対日付に直す
- 記述が矛盾していないか。両論併記になっていないか（この保管庫の既定は上書き更新）

### `C:\Users\nr202\projects\work\harness\settings.json`
- JSON として妥当か
- `$schema` に `https://json.schemastore.org/claude-code-settings.json` が入っているか
- `permissions` の `allow`/`deny` に、実在しないコマンドやツール名の指定が無いか
- `enabledPlugins` に挙がっているプラグインが実際に使われているか

### `C:\Users\nr202\projects\work\harness\scheduled-tasks\*\SKILL.md`
- frontmatter に `name` と `description` があり、`name` がディレクトリ名と一致しているか
- `description` が「何をするか」だけでなく**「いつ使うか」**を含んでいるか（公式の推奨形）
- **タスクが自己完結しているか。**各実行は前回の記憶を持たない。会話の文脈に依存した
  指示（「さっきの」「前回決めたとおり」）が残っていないか
- SKILL.md が肥大していないか。詳細は別ファイルに切り出して参照させる（progressive disclosure）
- **そのタスクの対象が実在するか。**対象0件のまま毎日走っていないか。
  これが過去に実際に起きた（memory-health-check が対象0件で空回りしていた）
- **タスク同士が同じ検査を重複して持っていないか。**役割は 2026-08-16 に分離済み。
  `link-integrity-check`（17:40）＝保管庫の整合性検査／このタスク＝ベストプラクティス適合と索引の修復。
  **索引リンクだけは意図的に重複する**（修復には検出が伴うため）。
  AMBIG/GONE は17:35と17:40の両方から報告される。これは仕様

**点検前に `list_scheduled_tasks` を引き、`scheduled-tasks/` のディレクトリと1対1か確認する。**
ディレクトリがあるのに未登録なら報告する（索引が「登録済み」と書いていても実際には走っていない）。
登録が無いディレクトリは点検対象から外す。

### `C:\Users\nr202\projects\work\harness\rules\*.md`
- 保管庫のルール（索引の「保管庫を触るとき」が指すファイル群）と二重管理になっていないか。
  同じ規約が両方にあれば指摘する
- そのルールが適用される対象が実在するか

### ユーザースコープの `CLAUDE.md`
- **200行以内か。**`@` import があれば展開後の実効行数で数えること（import 先の行数を足す）
- ドキュメントではなくチートシートになっているか。導出できる説明が残っていないか
- ファイルパスの直書きが復活していないか（パスは索引が持つ規約）。
  **ただし索引 `C:\Users\nr202\.claude\rules\保管庫索引.md` への入口ポインタだけは例外。**
  これが無いと索引に辿り着けない

### 索引 `C:\Users\nr202\.claude\rules\保管庫索引.md`
- 索引の全行について、リンク先が実在するか
- 実体があるのに索引に無いファイルが無いか（`00_inbox/` と日次log、`40_report/`、
  `projects/メンバー/` はフォルダ単位1行なので個別ファイルは対象外）
- 個別行を持つのがルール群・`30_context/` `20_knowledge/` `10_log/` の台帳だけに保たれているか。
  日次log や report の個別行が増えていたら、フォルダ単位1行に畳む
- 本文（要約・知見の中身）が索引に書き込まれていないか。
  各行のフックは**「いつ読むか」の判断材料**（型・トリガー条件）まで。
  ノートの結論そのものを書くと、ノート更新のたびに索引も直す二重メンテになる

## 4. 直すか報告するか

- **機械的に直せるものはその場で直す。** パスの修正、frontmatter の欠落補完、
  索引の欠落行の追加と実体の無い行の削除、相対日付の絶対日付化（元の日付が特定できる場合のみ。推測しない）
- **判断が要るものは直さず報告する。** ファイルの削除・統合、規約そのものの変更、
  矛盾する2つの記述のどちらを残すか、CLAUDE.md から何を出すか

保管庫のファイルを変更した場合は、`進捗.md`（索引の「保管庫を触るとき」が指す先）に反映する。
**iCloud Drive の同期競合を避けるため、同一ファイルへの編集は必ず直列で行う。**
また iCloud は作業中にも同期し、本人が Obsidian 上でファイルを移動していることもあるため、
**書き込む直前に対象ファイルを読み直すこと。**

## 5. 衝突コピーの復元と索引の退避（毎回やる。索引の修復より先）

**先に iCloud の衝突コピーを片付ける。**`〜 2.md` が残ったまま `fix-index.sh` を回すと、
実体を見つけられずに索引の行を消し、衝突コピーを正規登録してしまう。

```bash
bash "C:/Users/nr202/.claude/scheduled-tasks/config-health-check/fix-conflicts.sh" --apply
```

正本名でグループ化し、**判定できるものは正本を置き換えてでも解決する**（2026-08-18・本人指示）。

- 判定材料は2つだけ。**`updated:` 行を除いて byte 一致**か、**frontmatter の `updated:` が最大**か。
  **mtime は使わない。**iCloud が実体化のときに打ち直すため内容の新しさを表さない（実測で確認）
- どちらでも決まらなければ **REPORT。自走で処理しない**（本文が分岐かつ `updated:` が同日・欠落）
- 敗者は削除せず `~/.claude/backups/icloud-conflicts/<ts>/<相対パス>/` へ**複製してから消す。**
  正本が敗者になるときは正本も同じ場所へ退避する。**バイトは消えない**
- **同じ正本名で2度目の強制解決になるときは止める**（`解決済み.txt`）。毎日入れ替わるピンポンの検知
- `PART` は「退避はできたが iCloud が削除を止めた」。バイトは安全で、衝突コピーだけが残っている

そのあと索引を退避する。**索引はユーザースコープの直接編集で、配布物ではない。**
壊れたときに戻せる先はこの退避だけ。

```bash
bash "C:/Users/nr202/.claude/scheduled-tasks/config-health-check/backup-index.sh"
```

## 6. 索引の自動修復（毎回やる）

**本人は Obsidian 上でフォルダを頻繁に動かす。**そのたびに索引のリンクが切れる。
2026-08-16 には1日に2度、いずれも作成から1時間以内に全リンクが切れた。
**索引は保管庫の唯一のパス解決手段。**切れると、日次タスクもセッションも実体へ辿り着けなくなる。
これがこのタスクで最も実害の大きい故障なので、毎回必ず実行する。

```bash
bash "C:/Users/nr202/.claude/scheduled-tasks/config-health-check/fix-index.sh" --apply
```

ベース名で保管庫内に一意に解決できるリンクは自動で直る。以下は直らないので報告する。

- **AMBIG** — 同名ファイルが複数（例：`作業ログ.md` は各ストリームにある）。
  索引のそのセクションがどのストリームの話かを読んで決める
- **GONE** — 実体が見つからない。削除されたか、索引が知らない名前に改名された

**リンク切れ以外の整合性チェック（wikilink・本文中のパス・被リンクゼロ）は
`link-integrity-check`（17:40）が持つ。ここでは行わない。**
**衝突コピーは両方が持つ。**あちらは検出だけ（読み取り専用）、こちらが第5節で復元する。

索引の「保管庫の外」節に並ぶバッククォート表記の絶対パスは、markdown リンクではないため
`fix-index.sh` も `linkcheck.sh` も検査しない。**ここだけは毎回、目視で実在を確認する。**

```bash
grep -oP 'C:\\[^`]+' "C:/Users/nr202/.claude/rules/保管庫索引.md" | while IFS= read -r p; do [ -e "${p//\\//}" ] || echo "索引『保管庫の外』に実体なし: $p"; done
```

（`read -r` と `${p//\\//}` が要る。バックスラッシュ区切りのまま `[ -e ]` に渡すと必ず失敗する）

## 7. コミット・PR作成・マージ

第4〜6節で `harness/` または `vault-index/` に変更が生じたら、まとめて1コミットにして
PRを作成し、マージまで行う（2026-08-20・本人指示）。変更が無ければこの節を飛ばす。

**人の承認を待たない。**承認のゲートは fable のサブエージェントによるレビューが兼ねる
（worktree-cleanup と同じ設計）。判断が要る変更は第4節で直さず報告に回しているため、
ここへ来る時点で残っているのは機械的な修正だけである。

**この節を実行している間、本体チェックアウトのブランチを切り替える。**
対話セッションが同時に本体チェックアウトで作業していないことを前提にする。

Bash ツールを使う。**本体チェックアウトで作業する。**

```bash
cd "C:/Users/nr202/projects/work" && git status --porcelain -- harness/ vault-index/
```

出力が空ならこの節を終える。空でなければ次に進む。

```bash
cd "C:/Users/nr202/projects/work" && git checkout main && git pull --ff-only
```

`pull --ff-only` が失敗したら（本体が dirty、または main が発散している）、pull は諦めて
現在の HEAD からブランチを切る。それも失敗したら、コミットせず報告に回す。

```bash
cd "C:/Users/nr202/projects/work" && BR="claude/config-health-check-$(date +%Y%m%d-%H%M)" && git branch -D "$BR" 2>/dev/null; git checkout -b "$BR"
```

同名ブランチが前回の失敗で残っていても、分単位のタイムスタンプと事前削除で衝突しない。

変更ファイルは `harness/` と `vault-index/` だけを対象にする。**`git add -A` を使わない。**

```bash
cd "C:/Users/nr202/projects/work" && git add harness/ vault-index/ && git status --short
```

このどちらでもないパスが出ていたら `git restore --staged` で外し、そのファイルは報告に回す。

`git diff --staged` と、根拠にした規約の該当条項（通常は `メモリ管理規約.md` 10節の自律実行3条件）
を fable のサブエージェントへ渡し、レビューを依頼する
（Agent ツールを `model: "fable"` で呼ぶ。使えなければ `"opus"`）。
問いは「承認してよいか」ではなく**「この diff で失われる情報は何か」**にする（10節の条件2）。
却下されたらコミットせず、変更を作業ツリーに残したまま「判断が要るもの」として報告する。
このときも `git checkout main` で本体を main へ戻してから終える。

承認されたら、コミット・push・PR作成・マージまで進める。
コミットメッセージは1行の要約だけで終わらせず、何をどう直したかと理由を本文に書く
（既存コミットの慣例に合わせる）。実行しているモデル名を `Co-Authored-By:` 行に入れる。

```bash
cd "C:/Users/nr202/projects/work" && git commit -m "$(cat <<'EOF'
chore(harness): config-health-check の自動修復

<第4〜6節で直した内容の要旨>

Co-Authored-By: <実行モデル名> <noreply@anthropic.com>
EOF
)"
```

```bash
cd "C:/Users/nr202/projects/work" && git push -u origin HEAD
```

```bash
cd "C:/Users/nr202/projects/work" && gh pr create --title "chore(harness): config-health-check の自動修復" --body "config-health-check が機械的に直した内容。"
```

```bash
cd "C:/Users/nr202/projects/work" && gh pr merge --merge --delete-branch
```

マージ後、本体を `main` へ戻し、配布へ反映する。

```bash
cd "C:/Users/nr202/projects/work" && git checkout main && git pull --ff-only && bash "C:/Users/nr202/projects/work/scripts/deploy.sh" --yes
```

`gh pr merge` がコンフリクト等で失敗したら、PRのURLを報告に載せて人の判断に回す。
ブランチは残したまま、`git checkout main` で本体だけ main へ戻して終える。

問題が起きてから戻すときは、マージコミットを `git revert -m 1 <SHA>` してから
`deploy.sh --yes` を実行すればよい。このタスクが作るブランチは当日の使い捨てで、
削除するのは自分が作ったブランチだけである。

## 8. 空振りカウンタと降格提案

state.md に空振り（指摘ゼロ）の連続日数を持つ。

- 指摘が1件でも出たら 0 にリセットする
- **14日連続で空振りになったら、報告の最後に「週1（日曜のみ）への降格を提案する」と書く。**
  降格の実行は本人の判断に委ねる。勝手に cron を変更しない
- 成功判定は「走ったか」ではなく「指摘が修正に繋がったか」。
  state.md に累計の指摘件数と修正件数も1行で持つ

## 9. 報告

**簡潔に。前置き・要約・励ましを書かない。**

- 変化なしなら「変化なし（空振りN日目）」の1行で終える
- 変化があったが指摘ゼロなら「N件点検・異常なし」の1行
- 指摘があった場合のみ、**直したもの**と**判断が要るもの**を分けて箇条書きにする。
  ファイルは `パス:行` 形式で示す
- 第7節でPRを作成した場合は、マージ済みならPRのURLを1行、
  レビュー却下やマージ失敗で人の判断に回した場合はその旨とURLを1行付ける
- 14日連続空振りなら降格提案を1行付ける

最後に state.md を更新する（点検日時、各ファイルの mtime、空振り連続日数、累計指摘/修正件数）。

この点検作業自体が目的化しないこと。この保管庫の持ち主には「生産性ポルノ」
（効率化そのものに時間をかけすぎて本来の成果が出ない）という自己傾向が記録されている。
点検対象を勝手に増やさない。新しい管理ファイルを作らない。