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

# パスだけでなく内容も見る manifest。in-place の中身書き換えを見逃さないため、
# ハッシュ一覧（ファイル）とパス一覧（空ディレクトリの増減も拾う）の両方を比較材料にする。
manifest() {
  ( cd "$1" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort
    cd "$1" && find . | LC_ALL=C sort )
}

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
before="$(manifest "$TMP/dst")"
HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" \
  bash "$SCRIPT_DIR/deploy.sh" --dry-run >/dev/null 2>&1
dry_rc=$?
after="$(manifest "$TMP/dst")"
assert_eq "$after" "$before" "--dry-run が配布先を変更しない"
assert_eq "$dry_rc" "1" "--dry-run は差分ありで終了コード1"

# --- 1b. 差分が無い状態での --dry-run も一切書き込まない ---
setup
run_deploy --yes
before="$(manifest "$TMP/dst")"
HARNESS_SOURCE="$TMP/src" HARNESS_TARGET="$TMP/dst" \
  bash "$SCRIPT_DIR/deploy.sh" --dry-run >/dev/null 2>&1
dry_rc2=$?
after="$(manifest "$TMP/dst")"
assert_eq "$after" "$before" "差分なしの --dry-run も配布先を変更しない（状態ファイルの再生成を含めて書かない）"
assert_eq "$dry_rc2" "0" "差分なしの --dry-run は終了コード0"

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

# --- 6. 差分が無くても状態ファイルは書かれる（消えていたら復元される） ---
setup
run_deploy --yes
rm -f "$TMP/dst/.harness-state"
run_deploy --yes
rc6=$?
assert_eq "$rc6" "0" "差分なしの実デプロイも成功する"
assert_file "$TMP/dst/.harness-state" "差分が無くても状態ファイルが再作成される"

# --- 7. 配布先の所有ディレクトリ内にある除外名（state.md）は削除されない ---
setup
mkdir -p "$TMP/dst/scheduled-tasks/foo"
printf 'RUNTIME-DST\n' > "$TMP/dst/scheduled-tasks/foo/state.md"
run_deploy --yes
assert_eq "$(cat "$TMP/dst/scheduled-tasks/foo/state.md")" "RUNTIME-DST" \
  "配布先の所有ディレクトリ内にある除外名（state.md）は削除されずに残る"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
