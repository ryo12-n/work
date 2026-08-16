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
