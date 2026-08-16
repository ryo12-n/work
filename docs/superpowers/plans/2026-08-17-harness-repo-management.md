# AIハーネスのリポジトリ管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/.claude` のAIハーネスをこのリポジトリで原本管理し、`scripts/deploy.sh` 一本でユーザースコープへ一方向配布できるようにする。

**Architecture:** `harness/` が `~/.claude` 直下と 1:1 対応する原本。`scripts/lib.sh` が列挙・除外・ハッシュ・差分を持ち、`deploy.sh`（書く）と `check.sh`（読むだけ）が同じ判定を共有する。`harness/` 直下のディレクトリは丸ごと所有して削除まで同期し、直下のファイルは上書きのみ。それ以外の `~/.claude` には一切触れない。

**Tech Stack:** bash 5（Git Bash / cygwin）、GNU coreutils（`sha256sum`）、GNU findutils（`find -printf`）。**`jq` と `rsync` は存在しない。使わない。**

**Spec:** `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\personal\projects\開発環境構築\AIハーネス改善\ハーネスをリポジトリ管理\2026-08-17-ハーネスのリポジトリ管理-設計.md`

## Global Constraints

- リポジトリ本体チェックアウト: `C:\Users\nr202\projects\work`
- 保管庫ルート: `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\`
- 全スクリプトは `#!/usr/bin/env bash` + `set -euo pipefail`（テストスクリプトのみ `set -uo pipefail`）
- ソート・比較は必ず `LC_ALL=C`。日本語ファイル名でバイト安定な順序にするため
- `HARNESS_SOURCE`（既定 `<repo>/harness`）と `HARNESS_TARGET`（既定 `$HOME/.claude`）で入出力を差し替え可能にする。**これが無いとテストが本番を壊す**
- 除外名（配布も削除もしない）: `state.md` / `実行ログ.md` / `.gitkeep`
- 所有ディレクトリ = `harness/` 直下のディレクトリ。**削除同期はこの中だけ。ルート階層では絶対に削除しない**
- 状態ファイルは `$HARNESS_TARGET/.harness-state`。`sha256sum` 互換の manifest 形式
- コミットメッセージは日本語。末尾に `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- **`~/.claude` は自動タスクによって分単位で書き換わる。** 現物のファイル一覧をこの計画から読まず、実行時に列挙する

---

### Task 1: リポジトリの掃除と骨組み

**Files:**
- Delete: `analysis/ramen-shop/conditions/draft-list.md`
- Delete: `analysis/ramen-shop/conditions/plan.md`
- Delete: `analysis/ramen-shop/conditions/scoring-sheet.md`
- Delete: `analysis/ramen-shop/report/final-report.md`
- Modify: `.gitignore`（全置換）
- Create: `harness/skills/.gitkeep`, `harness/agents/.gitkeep`, `harness/commands/.gitkeep`, `harness/hooks/.gitkeep`

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: `harness/` ディレクトリ、除外パターンを持つ `.gitignore`

- [ ] **Step 1: ラーメン分析ファイルを削除**

```bash
git rm -r analysis
```

- [ ] **Step 2: `.gitignore` を全置換**

`.gitignore` の内容を以下で完全に置き換える（Go テンプレートは破棄）:

```gitignore
# 秘密情報 — 絶対に追跡しない
.credentials.json
*.credentials.json

# 実行時状態（毎日変わる。追跡するとドリフト警告が鳴り続ける）
harness/scheduled-tasks/*/state.md
harness/scheduled-tasks/*/実行ログ.md

# OS
Thumbs.db
.DS_Store
```

- [ ] **Step 3: 空ディレクトリの枠を作る**

```bash
mkdir -p harness/skills harness/agents harness/commands harness/hooks
touch harness/skills/.gitkeep harness/agents/.gitkeep harness/commands/.gitkeep harness/hooks/.gitkeep
```

- [ ] **Step 4: 意図どおりか確認**

```bash
git status --porcelain
```

期待: `analysis/` 配下4件が `D`、`.gitignore` が `M`、`harness/*/.gitkeep` が4件 `??`。

- [ ] **Step 5: コミット**

```bash
git add -A
git commit -m "chore: ラーメン分析を削除しハーネス管理用の骨組みを作る

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: lib.sh — 列挙・除外・ハッシュ

**Files:**
- Create: `scripts/lib.sh`
- Test: `scripts/test-lib.sh`

**Interfaces:**
- Consumes: Task 1 の `harness/`
- Produces: 以下の関数と変数。後続タスクはこれを `source` して使う
  - `$REPO_ROOT` — リポジトリルート絶対パス
  - `$HARNESS_SOURCE` — 原本ディレクトリ（既定 `$REPO_ROOT/harness`）
  - `$HARNESS_TARGET` — 配布先（既定 `$HOME/.claude`）
  - `harness_sha <file>` → sha256 を標準出力に1行
  - `harness_is_excluded <basename>` → 除外なら終了コード0
  - `harness_owned_dirs` → 所有ディレクトリ名を1行1件（`LC_ALL=C` ソート済み）
  - `harness_source_files` → 配布対象の相対パスを1行1件（除外適用済み・ソート済み）
  - `harness_target_managed_files` → 配布先の所有ディレクトリ配下の相対パスを1行1件（除外適用済み・ソート済み）

- [ ] **Step 1: 失敗するテストを書く**

`scripts/test-lib.sh` を作る:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok     - %s\n' "$1"; }
ng() { FAIL=$((FAIL+1)); printf 'NOT OK - %s\n' "$1"; }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else ng "$3"; printf '         expected: %s\n         actual:   %s\n' "$2" "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# フィクスチャ: 原本
mkdir -p "$TMP/src/rules" "$TMP/src/scheduled-tasks/foo" "$TMP/src/skills"
printf 'A\n'       > "$TMP/src/settings.json"
printf 'R1\n'      > "$TMP/src/rules/メモリ管理規約.md"
printf 'S\n'       > "$TMP/src/scheduled-tasks/foo/SKILL.md"
printf 'RUNTIME\n' > "$TMP/src/scheduled-tasks/foo/state.md"
printf 'LOG\n'     > "$TMP/src/scheduled-tasks/foo/実行ログ.md"
: > "$TMP/src/skills/.gitkeep"

# フィクスチャ: 配布先
mkdir -p "$TMP/dst/rules" "$TMP/dst/sessions"
printf 'STALE\n'  > "$TMP/dst/rules/古いルール.md"
printf 'SECRET\n' > "$TMP/dst/.credentials.json"
printf 'X\n'      > "$TMP/dst/sessions/s1.jsonl"

export HARNESS_SOURCE="$TMP/src"
export HARNESS_TARGET="$TMP/dst"
source "$SCRIPT_DIR/lib.sh"

assert_eq "$(harness_sha "$TMP/src/settings.json")" \
          "$(sha256sum "$TMP/src/settings.json" | cut -d' ' -f1)" \
          "harness_sha が sha256sum と一致する"

harness_is_excluded "state.md"      && ok "state.md は除外"      || ng "state.md は除外"
harness_is_excluded "実行ログ.md"    && ok "実行ログ.md は除外"    || ng "実行ログ.md は除外"
harness_is_excluded ".gitkeep"      && ok ".gitkeep は除外"      || ng ".gitkeep は除外"
harness_is_excluded "SKILL.md"      && ng "SKILL.md は除外しない" || ok "SKILL.md は除外しない"

assert_eq "$(harness_owned_dirs | tr '\n' ',')" "rules,scheduled-tasks,skills," \
          "所有ディレクトリは harness/ 直下のディレクトリのみ"

assert_eq "$(harness_source_files | tr '\n' ',')" \
          "rules/メモリ管理規約.md,scheduled-tasks/foo/SKILL.md,settings.json," \
          "配布対象から除外名が落ちている"

assert_eq "$(harness_target_managed_files | tr '\n' ',')" "rules/古いルール.md," \
          "配布先の列挙は所有ディレクトリ内のみ（.credentials.json と sessions/ を含まない）"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
bash scripts/test-lib.sh
```

期待: FAIL。`scripts/lib.sh: No such file or directory`。

- [ ] **Step 3: `scripts/lib.sh` を実装**

```bash
#!/usr/bin/env bash
# ハーネス配布の共通ロジック。deploy.sh と check.sh が同じ判定を使うためのもの。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${HARNESS_SOURCE:=$REPO_ROOT/harness}"
: "${HARNESS_TARGET:=$HOME/.claude}"
HARNESS_STATE="$HARNESS_TARGET/.harness-state"

# 配布も削除もしない名前。実行時状態と枠確保用のファイル。
HARNESS_EXCLUDE_NAMES=("state.md" "実行ログ.md" ".gitkeep")

harness_sha() {
  sha256sum "$1" | cut -d' ' -f1
}

harness_is_excluded() {
  local name="$1" e
  for e in "${HARNESS_EXCLUDE_NAMES[@]}"; do
    [ "$name" = "$e" ] && return 0
  done
  return 1
}

# 標準入力の相対パスから除外名を落とす
harness_filter_excluded() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    harness_is_excluded "$(basename "$p")" || printf '%s\n' "$p"
  done
}

harness_owned_dirs() {
  [ -d "$HARNESS_SOURCE" ] || return 0
  ( cd "$HARNESS_SOURCE" && find . -mindepth 1 -maxdepth 1 -type d -printf '%P\n' ) \
    | LC_ALL=C sort
}

harness_source_files() {
  [ -d "$HARNESS_SOURCE" ] || return 0
  ( cd "$HARNESS_SOURCE" && find . -type f -printf '%P\n' ) \
    | harness_filter_excluded | LC_ALL=C sort
}

# 配布先のうち「所有ディレクトリ配下」だけを列挙する。
# ルート直下のファイルは絶対に含めない — ここに含めると削除対象になってしまう。
harness_target_managed_files() {
  local d
  while IFS= read -r d; do
    [ -d "$HARNESS_TARGET/$d" ] || continue
    ( cd "$HARNESS_TARGET" && find "$d" -type f -printf '%p\n' )
  done < <(harness_owned_dirs) | harness_filter_excluded | LC_ALL=C sort
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
bash scripts/test-lib.sh
```

期待: `8 passed, 0 failed`、終了コード0。

- [ ] **Step 5: コミット**

```bash
git add scripts/lib.sh scripts/test-lib.sh
git commit -m "feat(scripts): ハーネスの列挙・除外・ハッシュを lib.sh に実装

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: lib.sh — 差分計算

**Files:**
- Modify: `scripts/lib.sh`（末尾に追記）
- Modify: `scripts/test-lib.sh`（末尾のサマリ出力の前に追記）

**Interfaces:**
- Consumes: Task 2 の全関数
- Produces: `harness_plan` → `<動作>\t<相対パス>` を1行1件で標準出力。動作は `ADD` / `UPDATE` / `SAME` / `DELETE`。ADD/UPDATE/SAME は原本順、DELETE は配布先順で後に続く

- [ ] **Step 1: 失敗するテストを書く**

`scripts/test-lib.sh` の `printf '\n%d passed` の行の**直前**に挿入する:

```bash
# --- harness_plan ---
# 配布先に settings.json は無い → ADD
# rules/メモリ管理規約.md も無い → ADD
# rules/古いルール.md は原本に無い → DELETE
assert_eq "$(harness_plan | tr '\t' ':' | tr '\n' ',')" \
          "ADD:rules/メモリ管理規約.md,ADD:scheduled-tasks/foo/SKILL.md,ADD:settings.json,DELETE:rules/古いルール.md," \
          "初回は全て ADD、原本に無い所有ファイルは DELETE"

# 同一内容を置いたら SAME、変えたら UPDATE
mkdir -p "$TMP/dst/scheduled-tasks/foo"
cp "$TMP/src/settings.json" "$TMP/dst/settings.json"
printf 'DIFFERENT\n' > "$TMP/dst/rules/メモリ管理規約.md"
assert_eq "$(harness_plan | grep -c '^SAME')"   "1" "内容が同じファイルは SAME"
assert_eq "$(harness_plan | grep -c '^UPDATE')" "1" "内容が違うファイルは UPDATE"
rm -f "$TMP/dst/settings.json" "$TMP/dst/rules/メモリ管理規約.md"
rmdir "$TMP/dst/scheduled-tasks/foo" "$TMP/dst/scheduled-tasks"
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
bash scripts/test-lib.sh
```

期待: FAIL。`harness_plan: command not found`。

- [ ] **Step 3: `harness_plan` を `scripts/lib.sh` の末尾に追記**

```bash
# 配布計画を "<動作>\t<相対パス>" で出す。
# ADD/UPDATE/SAME は原本側、DELETE は所有ディレクトリ内の余剰ファイル。
harness_plan() {
  local p src_hash dst_hash
  declare -A in_src=()

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    in_src["$p"]=1
    if [ ! -f "$HARNESS_TARGET/$p" ]; then
      printf 'ADD\t%s\n' "$p"
    else
      src_hash="$(harness_sha "$HARNESS_SOURCE/$p")"
      dst_hash="$(harness_sha "$HARNESS_TARGET/$p")"
      if [ "$src_hash" = "$dst_hash" ]; then
        printf 'SAME\t%s\n' "$p"
      else
        printf 'UPDATE\t%s\n' "$p"
      fi
    fi
  done < <(harness_source_files)

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -n "${in_src[$p]+x}" ] || printf 'DELETE\t%s\n' "$p"
  done < <(harness_target_managed_files)
}
```

- [ ] **Step 4: テストが通ることを確認**

```bash
bash scripts/test-lib.sh
```

期待: `11 passed, 0 failed`、終了コード0。

- [ ] **Step 5: コミット**

```bash
git add scripts/lib.sh scripts/test-lib.sh
git commit -m "feat(scripts): 配布計画を計算する harness_plan を実装

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: deploy.sh

**Files:**
- Create: `scripts/deploy.sh`
- Test: `scripts/test-deploy.sh`

**Interfaces:**
- Consumes: Task 2・3 の `lib.sh` 全関数、`$HARNESS_STATE`
- Produces: `scripts/deploy.sh [--dry-run] [--yes]`。配布先に `.harness-state` を書く

- [ ] **Step 1: 失敗するテストを書く**

`scripts/test-deploy.sh` を作る:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok     - %s\n' "$1"; }
ng() { FAIL=$((FAIL+1)); printf 'NOT OK - %s\n' "$1"; }
assert_eq()      { if [ "$1" = "$2" ]; then ok "$3"; else ng "$3"; printf '         expected: %s\n         actual:   %s\n' "$2" "$1"; fi; }
assert_file()    { if [ -f "$1" ]; then ok "$2"; else ng "$2 (無い: $1)"; fi; }
assert_absent()  { if [ ! -e "$1" ]; then ok "$2"; else ng "$2 (在る: $1)"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

setup() {
  rm -rf "$TMP/src" "$TMP/dst"
  mkdir -p "$TMP/src/rules" "$TMP/src/scheduled-tasks/foo" "$TMP/src/skills"
  printf 'A\n'       > "$TMP/src/settings.json"
  printf 'R1\n'      > "$TMP/src/rules/メモリ管理規約.md"
  printf 'S\n'       > "$TMP/src/scheduled-tasks/foo/SKILL.md"
  printf 'RUNTIME\n' > "$TMP/src/scheduled-tasks/foo/state.md"
  : > "$TMP/src/skills/.gitkeep"

  mkdir -p "$TMP/dst/rules" "$TMP/dst/sessions"
  printf 'STALE\n'  > "$TMP/dst/rules/古いルール.md"
  printf 'SECRET\n' > "$TMP/dst/.credentials.json"
  printf 'HIST\n'   > "$TMP/dst/history.jsonl"
  printf 'X\n'      > "$TMP/dst/sessions/s1.jsonl"
}

run_deploy() {
  HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" \
    bash "$SCRIPT_DIR/deploy.sh" "$@" >/dev/null 2>&1
}

# --- 1. --dry-run は一切書き込まない ---
setup
before="$(cd "$TMP/dst" && find . | LC_ALL=C sort)"
HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" \
  bash "$SCRIPT_DIR/deploy.sh" --dry-run >/dev/null 2>&1
dry_rc=$?
after="$(cd "$TMP/dst" && find . | LC_ALL=C sort)"
assert_eq "$after" "$before" "--dry-run が配布先を変更しない"
assert_eq "$dry_rc" "1" "--dry-run は差分ありで終了コード1"

# --- 2. 初回デプロイ ---
setup
run_deploy --yes
assert_eq "$(cat "$TMP/dst/settings.json")" "A"                     "ルート直下ファイルが配置される"
assert_eq "$(cat "$TMP/dst/rules/メモリ管理規約.md")" "R1"           "所有ディレクトリ内に配置される"
assert_eq "$(cat "$TMP/dst/scheduled-tasks/foo/SKILL.md")" "S"      "入れ子のファイルが配置される"
assert_absent "$TMP/dst/rules/古いルール.md"                         "所有ディレクトリ内の余剰ファイルが削除される"
assert_absent "$TMP/dst/scheduled-tasks/foo/state.md"               "除外名は配布されない"
assert_absent "$TMP/dst/skills/.gitkeep"                            ".gitkeep は配布されない"
if [ -d "$TMP/dst/skills" ]; then ok "空の所有ディレクトリは作られる"; else ng "空の所有ディレクトリは作られる"; fi
assert_eq "$(cat "$TMP/dst/.credentials.json")" "SECRET"            "対象外の秘密ファイルが残る"
assert_eq "$(cat "$TMP/dst/history.jsonl")" "HIST"                  "ルート直下の対象外ファイルが削除されない"
assert_eq "$(cat "$TMP/dst/sessions/s1.jsonl")" "X"                 "対象外ディレクトリが残る"
assert_file "$TMP/dst/.harness-state"                               "状態ファイルが作られる"
assert_eq "$(grep -c '^[0-9a-f]\{64\}  ' "$TMP/dst/.harness-state")" "3" "状態ファイルに配布3件が記録される"

# --- 3. バックアップ ---
bk="$(find "$TMP/dst/backups/harness-deploy" -name '古いルール.md' 2>/dev/null | head -1)"
if [ -n "$bk" ] && [ "$(cat "$bk")" = "STALE" ]; then ok "削除されたファイルがバックアップされる"; else ng "削除されたファイルがバックアップされる"; fi

# --- 4. 上書き ---
printf 'A2\n' > "$TMP/src/settings.json"
run_deploy --yes
assert_eq "$(cat "$TMP/dst/settings.json")" "A2" "既存ファイルが上書きされる"
bk2="$(find "$TMP/dst/backups/harness-deploy" -name 'settings.json' 2>/dev/null | head -1)"
if [ -n "$bk2" ] && [ "$(cat "$bk2")" = "A" ]; then ok "上書き前の内容がバックアップされる"; else ng "上書き前の内容がバックアップされる"; fi

# --- 5. 冪等 ---
run_deploy --yes
rc=$?
assert_eq "$rc" "0" "差分が無い状態で再実行しても成功する"
assert_eq "$(cat "$TMP/dst/settings.json")" "A2" "再実行で内容が変わらない"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
bash scripts/test-deploy.sh
```

期待: FAIL。`deploy.sh: No such file or directory`。

- [ ] **Step 3: `scripts/deploy.sh` を実装**

```bash
#!/usr/bin/env bash
# harness/ の内容を $HARNESS_TARGET へ一方向に配布する。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    *) printf '不明な引数: %s\n使い方: deploy.sh [--dry-run] [--yes]\n' "$arg" >&2; exit 2 ;;
  esac
done

printf '原本:   %s\n' "$HARNESS_SOURCE"
printf '配布先: %s\n\n' "$HARNESS_TARGET"

PLAN="$(harness_plan)"
CHANGES="$(printf '%s\n' "$PLAN" | grep -v '^SAME' || true)"

if [ -z "$CHANGES" ]; then
  printf '差分なし。\n'
  exit 0
fi

printf '%s\n' "$CHANGES" | while IFS=$'\t' read -r action path; do
  printf '  %-6s %s\n' "$action" "$path"
done
printf '\n'

if [ "$DRY_RUN" -eq 1 ]; then
  printf '--dry-run のため反映しません。\n'
  exit 1
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "反映しますか？ [y/N] " reply
  case "$reply" in [yY]*) ;; *) printf '中止しました。\n'; exit 1 ;; esac
fi

BACKUP_DIR="$HARNESS_TARGET/backups/harness-deploy/$(date -u +%Y%m%dT%H%M%SZ)"

# 1. 上書き・削除されるものを退避
while IFS=$'\t' read -r action path; do
  case "$action" in
    UPDATE|DELETE)
      mkdir -p "$BACKUP_DIR/$(dirname "$path")"
      cp -p "$HARNESS_TARGET/$path" "$BACKUP_DIR/$path"
      ;;
  esac
done <<< "$CHANGES"

# 2. 所有ディレクトリを先に作る（ファイルが1件も無い枠のため）
while IFS= read -r d; do
  [ -n "$d" ] || continue
  mkdir -p "$HARNESS_TARGET/$d"
done < <(harness_owned_dirs)

# 3. 反映
while IFS=$'\t' read -r action path; do
  case "$action" in
    ADD|UPDATE)
      mkdir -p "$HARNESS_TARGET/$(dirname "$path")"
      cp -p "$HARNESS_SOURCE/$path" "$HARNESS_TARGET/$path"
      ;;
    DELETE)
      rm -f "$HARNESS_TARGET/$path"
      ;;
  esac
done <<< "$CHANGES"

# 4. 状態を記録
{
  printf '# deployedAt: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# commit: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s  %s\n' "$(harness_sha "$HARNESS_TARGET/$p")" "$p"
  done < <(harness_source_files)
} > "$HARNESS_STATE"

printf '反映しました。バックアップ: %s\n' "$BACKUP_DIR"
```

- [ ] **Step 4: テストが通ることを確認**

```bash
bash scripts/test-deploy.sh
```

期待: `19 passed, 0 failed`、終了コード0。

- [ ] **Step 5: コミット**

```bash
git add scripts/deploy.sh scripts/test-deploy.sh
git commit -m "feat(scripts): 一方向デプロイと上書き前バックアップを実装

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: check.sh

**Files:**
- Create: `scripts/check.sh`
- Test: `scripts/test-check.sh`

**Interfaces:**
- Consumes: Task 2・3 の `lib.sh`、Task 4 が書く `$HARNESS_STATE`
- Produces: `scripts/check.sh`。書き込まない。問題なしで終了コード0、問題ありで1

**判定の考え方:** `.harness-state` を基準点として両側を見る。原本が基準からずれていれば「未デプロイ」、配布先が基準からずれていれば「本番ドリフト」。

- [ ] **Step 1: 失敗するテストを書く**

`scripts/test-check.sh` を作る:

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok     - %s\n' "$1"; }
ng() { FAIL=$((FAIL+1)); printf 'NOT OK - %s\n' "$1"; }
assert_contains() { if printf '%s' "$1" | grep -qF "$2"; then ok "$3"; else ng "$3"; printf '         出力: %s\n' "$1"; fi; }
assert_absent_str() { if printf '%s' "$1" | grep -qF "$2"; then ng "$3"; else ok "$3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

setup() {
  rm -rf "$TMP/src" "$TMP/dst"
  mkdir -p "$TMP/src/rules" "$TMP/dst"
  printf 'A\n'  > "$TMP/src/settings.json"
  printf 'R1\n' > "$TMP/src/rules/メモリ管理規約.md"
}
run_check() { HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" bash "$SCRIPT_DIR/check.sh" 2>&1; }
run_deploy() { HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" bash "$SCRIPT_DIR/deploy.sh" --yes >/dev/null 2>&1; }

# --- 1. 状態ファイルが無い ---
setup
out="$(run_check)"; rc=$?
assert_contains "$out" "未デプロイ" "状態ファイルが無ければ未デプロイと報告する"
[ "$rc" -eq 1 ] && ok "問題ありで終了コード1" || ng "問題ありで終了コード1"

# --- 2. デプロイ直後は異常なし ---
setup; run_deploy
out="$(run_check)"; rc=$?
assert_contains "$out" "異常なし" "デプロイ直後は異常なし"
[ "$rc" -eq 0 ] && ok "問題なしで終了コード0" || ng "問題なしで終了コード0"

# --- 3. 原本が進んだ = 未デプロイ ---
setup; run_deploy
printf 'A2\n' > "$TMP/src/settings.json"
out="$(run_check)"
assert_contains "$out" "未デプロイ" "原本を変えると未デプロイになる"
assert_absent_str "$out" "本番ドリフト" "原本の変更を本番ドリフトと呼ばない"

# --- 4. 配布先が書き換わった = 本番ドリフト ---
setup; run_deploy
printf 'HACKED\n' > "$TMP/dst/rules/メモリ管理規約.md"
out="$(run_check)"
assert_contains "$out" "本番ドリフト" "配布先の書き換えを本番ドリフトとして検出する"

# --- 5. 配布先にファイルが増えた = 本番ドリフト ---
setup; run_deploy
printf 'NEW\n' > "$TMP/dst/rules/新しいルール.md"
out="$(run_check)"
assert_contains "$out" "本番ドリフト" "配布先に増えたファイルを本番ドリフトとして検出する"

# --- 6. 書き込まない ---
setup; run_deploy
before="$(cd "$TMP/dst" && find . | LC_ALL=C sort)"
run_check >/dev/null
after="$(cd "$TMP/dst" && find . | LC_ALL=C sort)"
[ "$before" = "$after" ] && ok "check.sh は配布先に書き込まない" || ng "check.sh は配布先に書き込まない"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
bash scripts/test-check.sh
```

期待: FAIL。`check.sh: No such file or directory`。

- [ ] **Step 3: `scripts/check.sh` を実装**

```bash
#!/usr/bin/env bash
# 原本と配布先のずれを報告する。書き込まない。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ISSUES=0
report() { ISSUES=$((ISSUES+1)); printf '%s\n' "$1"; }

if [ ! -f "$HARNESS_STATE" ]; then
  report "未デプロイ（初回）: $HARNESS_STATE がありません。deploy.sh を実行してください。"
else
  STATE_BODY="$(grep -v '^#' "$HARNESS_STATE" || true)"

  # 未デプロイ: 原本の現ハッシュ一覧が記録と一致しない
  SRC_MANIFEST="$(
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      printf '%s  %s\n' "$(harness_sha "$HARNESS_SOURCE/$p")" "$p"
    done < <(harness_source_files)
  )"
  if [ "$SRC_MANIFEST" != "$STATE_BODY" ]; then
    report "未デプロイ: リポジトリが配布先より進んでいます。deploy.sh を実行してください。"
    diff <(printf '%s\n' "$STATE_BODY" | sed 's/^[0-9a-f]*  //' | LC_ALL=C sort) \
         <(printf '%s\n' "$SRC_MANIFEST" | sed 's/^[0-9a-f]*  //' | LC_ALL=C sort) \
         | sed 's/^/    /' || true
  fi

  # 本番ドリフト(a): 記録されたパスの配布先ハッシュが違う、または欠落
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    recorded="${line%%  *}"
    path="${line#*  }"
    if [ ! -f "$HARNESS_TARGET/$path" ]; then
      report "本番ドリフト: 配布先から消えています — $path"
    elif [ "$(harness_sha "$HARNESS_TARGET/$path")" != "$recorded" ]; then
      report "本番ドリフト: 配布先が書き換わっています — $path（次回デプロイで消えます）"
    fi
  done <<< "$STATE_BODY"

  # 本番ドリフト(b): 所有ディレクトリ内に記録に無いファイルが増えている
  STATE_PATHS="$(printf '%s\n' "$STATE_BODY" | sed 's/^[0-9a-f]*  //' | LC_ALL=C sort)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\n' "$STATE_PATHS" | grep -qxF "$p" \
      || report "本番ドリフト: 配布先に増えています — $p（次回デプロイで消えます）"
  done < <(harness_target_managed_files)
fi

# 未コミット
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  DIRTY="$(git -C "$REPO_ROOT" status --porcelain -- harness || true)"
  if [ -n "$DIRTY" ]; then
    report "未コミット: harness/ に未コミットの変更があります。"
    printf '%s\n' "$DIRTY" | sed 's/^/    /'
  fi
fi

if [ "$ISSUES" -eq 0 ]; then
  printf '異常なし\n'
  exit 0
fi
exit 1
```

- [ ] **Step 4: テストが通ることを確認**

```bash
bash scripts/test-check.sh
```

期待: `9 passed, 0 failed`、終了コード0。

- [ ] **Step 5: 全テストをまとめて実行**

```bash
bash scripts/test-lib.sh && bash scripts/test-deploy.sh && bash scripts/test-check.sh
```

期待: 3本とも `0 failed`。

- [ ] **Step 6: コミット**

```bash
git add scripts/check.sh scripts/test-check.sh
git commit -m "feat(scripts): 未デプロイ・本番ドリフト・未コミットを報告する check.sh を実装

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: ハーネス現物の取り込み

**Files:**
- Create: `harness/rules/**`（実行時に列挙してコピー）
- Create: `harness/scheduled-tasks/**`（同上）
- Create: `harness/settings.json`

**Interfaces:**
- Consumes: Task 1 の `harness/`、Task 4 の `deploy.sh --dry-run`
- Produces: 取り込み済みの `harness/`。**Task 9 の本番適用が差分ゼロになる前提条件**

**重要:** `~/.claude` は自動タスクによって分単位で書き換わる。**この計画に書かれたファイル一覧を正としない。実行時に `find` で列挙する。**

- [ ] **Step 1: 取り込み前の現物を列挙して記録**

```bash
cd /c/Users/nr202/.claude && find rules scheduled-tasks -type f | LC_ALL=C sort
```

出力を控える。Step 4 の照合に使う。

- [ ] **Step 2: 現物をコピー**

```bash
cd "$(git rev-parse --show-toplevel)"
mkdir -p harness/rules harness/scheduled-tasks
cp -R /c/Users/nr202/.claude/rules/. harness/rules/
cp -R /c/Users/nr202/.claude/scheduled-tasks/. harness/scheduled-tasks/
cp /c/Users/nr202/.claude/settings.json harness/settings.json
```

- [ ] **Step 3: 除外対象が紛れていないか確認して落とす**

```bash
find harness -name 'state.md' -o -name '実行ログ.md'
```

見つかったら削除する（`.gitignore` で追跡されないが、`harness/` に置くと紛らわしいため）:

```bash
find harness \( -name 'state.md' -o -name '実行ログ.md' \) -delete
```

- [ ] **Step 4: 取り込みが正確か照合**

```bash
cd "$(git rev-parse --show-toplevel)"
diff <(cd /c/Users/nr202/.claude && find rules scheduled-tasks -type f \
        \( ! -name 'state.md' -a ! -name '実行ログ.md' \) | LC_ALL=C sort) \
     <(cd harness && find rules scheduled-tasks -type f | LC_ALL=C sort)
```

期待: 出力なし。差分があれば Step 2 からやり直す（その間に自動タスクが書いた可能性がある）。

- [ ] **Step 5: `--dry-run` で差分ゼロを確認**

```bash
bash scripts/deploy.sh --dry-run
```

期待: `差分なし。`、終了コード0。

**差分が出たら取り込みに漏れか改変がある。デプロイせず Step 2 へ戻る。**

- [ ] **Step 6: コミット**

```bash
git add harness
git commit -m "chore(harness): ~/.claude の現物を原本として取り込む

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: CLAUDE.md の移設とパス絶対化

**Files:**
- Create: `harness/CLAUDE.md`

**Interfaces:**
- Consumes: Task 6 の `harness/`
- Produces: `harness/CLAUDE.md`。Task 8 の `obsidian-daily-extraction` 参照差し替えが依存する

保管庫の `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\CLAUDE.md` をユーザースコープへ移す。
保管庫ルートからの相対パスで書かれているため、全プロジェクトで解決するよう絶対化する。
表記は `harness/rules/メモリ管理規約.md` が既に採っている `<保管庫>` 方式に揃える。

- [ ] **Step 1: `harness/CLAUDE.md` を作成**

以下の内容で作る。原文からの変更は「先頭に保管庫ルートの定義を足したこと」と
「`personal/...` の相対パスを `<保管庫>\personal\...` にしたこと」の2点のみ。
それ以外の文言は一字も変えない。

```markdown
保管庫のルートは `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\`。以下 `<保管庫>` と書く。

## 作業ポリシー

作業は、着手前と完了後に **fable のサブエージェントへレビューを依頼する**。
Agent ツールを `model: "fable"` で呼び出す（使えない場合は `"opus"`）。
> このファイルは**本人がグローバルな方針を書く場所**。
> 個別のファイル名・パス・層の運用ルールはここに書かない。索引と各 `AIメモリ/` が持つ。
このファイルは人間が編集する。AIは明示的に指示されない限り編集しない
・公式の情報をcontext7で調べること

## AIメモリ

**`AIメモリ` という名前のディレクトリは、AIが自由に書いてよい場所。**
本人はここを手で書かない。どこに置かれていても扱いは同じで、
**上書き更新・常に最新のみ・履歴は残さない。**

- `<保管庫>\personal\AIメモリ\` — 保管庫全体のもの。索引（`MEMORY.md`）
- `<保管庫>\personal\projects\<ストリーム>\AIメモリ\` — そのストリーム固有の運用ルール・設計・進捗・作業ログ・知見

**同じ内容を両方に書かない。** ストリーム内で完結する話はストリーム側にだけ置く。

## 作業開始時にやること

計画・提案・相談に答える前に、まず `<保管庫>\personal\AIメモリ\MEMORY.md` を読む。
索引の**「常時」セクションのファイルは必ず開く**。

読んだら、**今回に効く項目だけ**を「出典 / 項目 / この作業への効き方」で1項目1行で挙げ、
それから着手する。読んだことの報告ではなく、何を前提に置くかの宣言。


## 更新の原則

**古い記述は削除して新しい記述へ置き換える。** 追記して両方を残さない。
「以前は〜だったが今は〜」と書かない。現在の事実だけを書く。
内容を足すときは、何を落とすかを同時に決める。
明示的に過去の記述を背景として保持するという指示があれば残してよい


## 作業後

状態が変わったら `<保管庫>\personal\AIメモリ\MEMORY.md` を最新化する。
ファイルを新規作成・削除・改名したら、**MEMORY.md の行を同時に直す。**
```

- [ ] **Step 2: 相対パスが残っていないか確認**

```bash
grep -n 'personal/' harness/CLAUDE.md
```

期待: 出力なし（全て `<保管庫>\personal\...` のバックスラッシュ表記になっている）。

- [ ] **Step 3: 原文と本文が一致するか確認**

```bash
diff <(grep -v '保管庫のルートは' harness/CLAUDE.md | grep -v '^$') \
     <(grep -v '^$' "/c/Users/nr202/iCloudDrive/iCloud~md~obsidian/CLAUDE.md")
```

期待: パスを書き換えた5行分のみ差分として出る。それ以外の行が差分に出たら文言を変えてしまっている。

- [ ] **Step 4: コミット**

```bash
git add harness/CLAUDE.md
git commit -m "feat(harness): 保管庫の CLAUDE.md をユーザースコープへ移設しパスを絶対化

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: 自動タスクの参照先切り替え

**Files:**
- Modify: `harness/scheduled-tasks/config-health-check/SKILL.md`
- Modify: `harness/scheduled-tasks/memory-health-check/SKILL.md`
- Modify: `harness/scheduled-tasks/memory-health-check/reference/点検項目.md`
- Modify: `harness/scheduled-tasks/obsidian-daily-extraction/SKILL.md`

**Interfaces:**
- Consumes: Task 6 の取り込み済みタスク定義、Task 7 の `harness/CLAUDE.md`
- Produces: 書き込み先が `C:\Users\nr202\projects\work\harness\` を向いたタスク定義

**方針:** タスクが**書き換える**対象をリポジトリへ向ける。**読むだけ**の参照（`fix-index.sh` の実行パスなど）は配布先のままでよい。

- [ ] **Step 1: 現在の参照箇所を全て洗い出す**

```bash
cd "$(git rev-parse --show-toplevel)/harness"
grep -rn '\.claude' scheduled-tasks/ | cat
```

出力された各行を、下の表で分類する。

| 参照の種類 | 対応 |
|---|---|
| 点検・修復の**対象**として `~/.claude/rules/*.md` や `~/.claude/scheduled-tasks/*/SKILL.md` を指す | `C:\Users\nr202\projects\work\harness\rules\*.md` 等へ**書き換える** |
| 点検・修復の**対象**として `~/.claude/settings.json` を指す | `C:\Users\nr202\projects\work\harness\settings.json` へ**書き換える** |
| 自分自身の実行時状態（`state.md` / `実行ログ.md`）の置き場 | **そのまま**（配布先に残す。リポジトリでは追跡しない） |
| スクリプトの実行パス（`bash ".../fix-index.sh"`） | **そのまま**（配布先の実体を実行する） |
| 判定基準として規約を読む | `C:\Users\nr202\projects\work\harness\rules\メモリ管理規約.md` へ**書き換える** |

- [ ] **Step 2: `config-health-check/SKILL.md` を書き換える**

点検対象のパスをリポジトリへ向ける。既知の該当行（Step 1 の出力で現在値を確認してから編集すること）:

- `stat -c` の行の `"C:/Users/nr202/.claude/settings.json"` → `"C:/Users/nr202/projects/work/harness/settings.json"`
- 同行の `"C:/Users/nr202/.claude/rules/"*.md` → `"C:/Users/nr202/projects/work/harness/rules/"*.md`
- 同行の `"C:/Users/nr202/.claude/scheduled-tasks/"*/SKILL.md` → `"C:/Users/nr202/projects/work/harness/scheduled-tasks/"*/SKILL.md`
- 同行の裸の `CLAUDE.md`（保管庫ルートからの相対）→ `"C:/Users/nr202/projects/work/harness/CLAUDE.md"`
- 見出し `### \`C:\Users\nr202\.claude\settings.json\`` → `### \`C:\Users\nr202\projects\work\harness\settings.json\``
- 見出し `### \`C:\Users\nr202\.claude\scheduled-tasks\*\SKILL.md\`` → `### \`C:\Users\nr202\projects\work\harness\scheduled-tasks\*\SKILL.md\``
- 見出し `### \`C:\Users\nr202\.claude\rules\*.md\`` → `### \`C:\Users\nr202\projects\work\harness\rules\*.md\``
- 見出し `### 保管庫の \`CLAUDE.md\`` → `### ユーザースコープの \`CLAUDE.md\``

**そのままにする行:**
- `state.md` の置き場を指す行（自分の実行時状態）
- `fix-index.sh` を実行する行
- `/llmstxt/code_claude_llms_txt`（`code.claude.com` の一部であって `.claude` ディレクトリではない）

さらに、変更した意図を見失わないよう、冒頭の説明の直後に以下を追記する:

```markdown
**点検対象はリポジトリの原本（`C:\Users\nr202\projects\work\harness\`）である。**
`~/.claude` は配布物であり、直接直しても次のデプロイで巻き戻る。
直したら `bash "C:/Users/nr202/projects/work/scripts/deploy.sh" --yes` まで実行すること。
```

- [ ] **Step 3: `memory-health-check/SKILL.md` を書き換える**

- `C:\Users\nr202\.claude\rules\メモリ管理規約.md` → `C:\Users\nr202\projects\work\harness\rules\メモリ管理規約.md`
- `C:\Users\nr202\.claude\scheduled-tasks\memory-health-check\reference\点検項目.md` → `C:\Users\nr202\projects\work\harness\scheduled-tasks\memory-health-check\reference\点検項目.md`
- `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\CLAUDE.md`（レビュア指定の参照）→ `C:\Users\nr202\projects\work\harness\CLAUDE.md`

**そのままにする行:**
- `実行ログ.md` の置き場を指す行
- `fix-index.sh` を実行する行

Step 2 と同じ「対象はリポジトリの原本」の注意書きを冒頭の説明直後に追記する。

- [ ] **Step 4: `memory-health-check/reference/点検項目.md` を書き換える**

- 基準の所在 `~/.claude/rules/メモリ管理規約.md` → `C:\Users\nr202\projects\work\harness\rules\メモリ管理規約.md`
- 点検対象 `~/.claude/rules/*.md` → `C:\Users\nr202\projects\work\harness\rules\*.md`
- レビュア指定の `CLAUDE.md` → `C:\Users\nr202\projects\work\harness\CLAUDE.md`

**そのままにする行:** `~/.claude/projects/*/memory/*.md`（メモリは管理対象外。配布先のまま点検する）

- [ ] **Step 5: `obsidian-daily-extraction/SKILL.md` を書き換える**

第0節「まずルールを読む」の読み込み対象:

- `- \`CLAUDE.md\`` → `- \`C:\Users\nr202\projects\work\harness\CLAUDE.md\` — ユーザースコープの方針。会話開始時に自動ロードされるが明示的に読む`

**保管庫の `CLAUDE.md` は Task 9 で削除されるため、この差し替えは必須。**

`fix-index.sh` の実行行はそのまま。

- [ ] **Step 6: 書き換え漏れを確認**

```bash
cd "$(git rev-parse --show-toplevel)/harness"
grep -rn '\.claude' scheduled-tasks/ | grep -v 'state\.md' | grep -v '実行ログ\.md' \
  | grep -v 'fix-index\.sh' | grep -v 'linkcheck\.sh' | grep -v 'llms_txt' \
  | grep -v 'projects/\*/memory' | cat
```

期待: 出力なし。残っていれば Step 2〜5 で拾い漏れている。

- [ ] **Step 7: 保管庫 CLAUDE.md への参照が残っていないか確認**

```bash
grep -rn 'iCloud~md~obsidian.CLAUDE\.md' scheduled-tasks/ | cat
grep -rn '^- `CLAUDE\.md`' scheduled-tasks/ | cat
```

期待: どちらも出力なし。

- [ ] **Step 8: コミット**

```bash
git add harness/scheduled-tasks
git commit -m "feat(harness): 自動タスクの点検・修復対象をリポジトリの原本へ向ける

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: harness-drift-check タスクの新設

**Files:**
- Create: `harness/scheduled-tasks/harness-drift-check/SKILL.md`

**Interfaces:**
- Consumes: Task 5 の `scripts/check.sh`
- Produces: 日次で差分を報告するスケジュール済みタスク定義

- [ ] **Step 1: `harness/scheduled-tasks/harness-drift-check/SKILL.md` を作成**

```markdown
---
name: harness-drift-check
description: AIハーネスの原本（リポジトリ）と配布先（~/.claude）のずれを毎日検出して報告する。修正はしない（読み取り専用）
---

AIハーネスの原本と配布先のずれを点検して**報告する**。

## このタスクは読み取り専用

**判定ロジックをここに書かない。** 基準は `scripts/check.sh` が唯一の正で、
ここは駆動だけを持つ。基準を増やしたくなったらスクリプト側を直す。

**何も書き換えない。** デプロイもしない。ずれの解消は本人が判断する。

## 手順

1. 検査スクリプトを実行する。**Bash ツールを使うこと**（PowerShell ではない）。

```
bash "C:/Users/nr202/projects/work/scripts/check.sh"
```

2. 出力をそのまま読む。3種類の状態が報告される。

| 報告 | 意味 | 促すこと |
|---|---|---|
| **未デプロイ** | リポジトリが配布先より進んでいる | `bash "C:/Users/nr202/projects/work/scripts/deploy.sh"` の実行 |
| **本番ドリフト** | `~/.claude` がデプロイ後に書き換わった | **次回デプロイで消える。**残したい変更なら `harness/` へ手で移すよう促す |
| **未コミット** | `harness/` に未コミットの変更がある | コミットを促す |

## 報告の形

終了コード0（`異常なし`）なら「**異常なし**」の1行で終える。
前置き・要約・励ましを書かない。

問題があった場合のみ、スクリプトの出力を種類ごとに整理して示す。
**本番ドリフトは「消える予定の変更」として扱う。**放置すると次のデプロイで失われる。

## 注意

**このリポジトリはAIハーネスの原本を持つ。** `config-health-check` と
`memory-health-check` は `C:\Users\nr202\projects\work\harness\` を直接直す設計になっている。
それらが直した直後は「未デプロイ」「未コミット」が出るのが正常。
```

- [ ] **Step 2: 参照するスクリプトが実在するか確認**

```bash
ls -l "$(git rev-parse --show-toplevel)/scripts/check.sh"
```

期待: ファイルが存在する。

- [ ] **Step 3: コミット**

```bash
git add harness/scheduled-tasks/harness-drift-check
git commit -m "feat(harness): 原本と配布先のずれを日次で報告する harness-drift-check を新設

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: README と bootstrap.md

**Files:**
- Modify: `README.md`（全置換）
- Create: `docs/bootstrap.md`

**Interfaces:**
- Consumes: Task 4・5 のスクリプト
- Produces: 運用手順の文書

- [ ] **Step 1: `README.md` を全置換**

```markdown
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
```

- [ ] **Step 2: `docs/bootstrap.md` を作成**

```markdown
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
```

- [ ] **Step 3: コミット**

```bash
git add README.md docs/bootstrap.md
git commit -m "docs: 運用手順と新マシン立ち上げ手順を追加

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: 本番適用

**Files:**
- Delete: `C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\CLAUDE.md`
- 配布先 `C:\Users\nr202\.claude\**`（スクリプトが書く）

**Interfaces:**
- Consumes: Task 1〜10 の全て
- Produces: 稼働中のハーネス

**このタスクだけが `~/.claude` と保管庫を実際に変更する。**

- [ ] **Step 1: 全テストを実行**

```bash
bash scripts/test-lib.sh && bash scripts/test-deploy.sh && bash scripts/test-check.sh
```

期待: 3本とも `0 failed`。**1つでも落ちたら止まる。**

- [ ] **Step 2: 作業ツリーがクリークか確認**

```bash
git status --porcelain
```

期待: 出力なし。

- [ ] **Step 3: 本番へ `--dry-run`**

```bash
bash scripts/deploy.sh --dry-run
```

期待される差分は以下**だけ**:

- `ADD  CLAUDE.md`（Task 7 で新設）
- `ADD  scheduled-tasks/harness-drift-check/SKILL.md`（Task 9 で新設）
- `UPDATE  scheduled-tasks/config-health-check/SKILL.md`（Task 8）
- `UPDATE  scheduled-tasks/memory-health-check/SKILL.md`（Task 8）
- `UPDATE  scheduled-tasks/memory-health-check/reference/点検項目.md`（Task 8）
- `UPDATE  scheduled-tasks/obsidian-daily-extraction/SKILL.md`（Task 8）

**これ以外の差分が出たら止まる。** 特に `rules/` や `settings.json` に
`UPDATE` が出た場合、Task 6 の取り込み後に自動タスクが `~/.claude` を書いている。
その変更を `harness/` へ取り込み直してから進む（配布先の変更を失わないため）。

- [ ] **Step 4: デプロイ**

```bash
bash scripts/deploy.sh
```

確認プロンプトに `y` で答える。

- [ ] **Step 5: 反映を確認**

```bash
bash scripts/check.sh
```

期待: `異常なし`、終了コード0。

```bash
ls -l /c/Users/nr202/.claude/CLAUDE.md /c/Users/nr202/.claude/scheduled-tasks/harness-drift-check/SKILL.md
ls -l /c/Users/nr202/.claude/.credentials.json
```

期待: 前2つが存在し、`.credentials.json` が**無傷で残っている**。

- [ ] **Step 6: 保管庫 CLAUDE.md を削除**

**削除前に、参照差し替えが済んでいることを再確認する:**

```bash
grep -rn 'iCloud~md~obsidian.CLAUDE\.md' /c/Users/nr202/.claude/scheduled-tasks/ | cat
grep -rln '^- `CLAUDE\.md`' /c/Users/nr202/.claude/scheduled-tasks/ | cat
```

期待: どちらも出力なし。**出力があれば削除しない。** Task 8 に戻る。

内容が `harness/CLAUDE.md` に引き継がれていることを確認:

```bash
diff <(grep -v '^$' "/c/Users/nr202/iCloudDrive/iCloud~md~obsidian/CLAUDE.md") \
     <(grep -v '保管庫のルートは' /c/Users/nr202/.claude/CLAUDE.md | grep -v '^$')
```

期待: パスを書き換えた5行分のみ。

削除する:

```bash
rm "/c/Users/nr202/iCloudDrive/iCloud~md~obsidian/CLAUDE.md"
```

- [ ] **Step 7: 保管庫の索引を直す**

`C:\Users\nr202\iCloudDrive\iCloud~md~obsidian\personal\AIメモリ\MEMORY.md` の
「保管庫の外」セクションに1行を足す。既存の `メモリ管理規約.md` の行の直後:

```markdown
- `C:\Users\nr202\.claude\CLAUDE.md` — **グローバル方針。**自動ロード。原本は `C:\Users\nr202\projects\work\harness\CLAUDE.md`（2026-08-17 に保管庫から移設）
```

`link-integrity-check` が保管庫 `CLAUDE.md` の `@import` を検査する設計なので、
検査1が「対象なし」になることを次の実行で確認する（このタスクでは確認しない）。

- [ ] **Step 8: `harness-drift-check` を cron 登録**

Claude Code の対話セッションで `55 17 * * *` に登録する。
登録後、手動で1度実行して `異常なし` が返ることを確認する。

- [ ] **Step 9: 最終コミット**

```bash
git add -A
git commit -m "chore: ハーネスを本番へ配布し保管庫の CLAUDE.md を廃止

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
