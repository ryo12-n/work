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

# パスだけでなく内容も見る manifest。in-place の中身書き換えを見逃さないため、
# ハッシュ一覧（ファイル）とパス一覧（空ディレクトリの増減も拾う）の両方を比較材料にする。
manifest() {
  ( cd "$1" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort
    cd "$1" && find . | LC_ALL=C sort )
}

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

# --- 6. 記録済みファイルが配布先から消えた = 本番ドリフト ---
setup; run_deploy
rm -f "$TMP/dst/rules/メモリ管理規約.md"
out="$(run_check)"
assert_contains "$out" "本番ドリフト" "配布先から消えたファイルを本番ドリフトとして検出する"

# --- 7. 書き込まない ---
setup; run_deploy
before="$(manifest "$TMP/dst")"
run_check >/dev/null
after="$(manifest "$TMP/dst")"
[ "$before" = "$after" ] && ok "check.sh は配布先に書き込まない" || ng "check.sh は配布先に書き込まない"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
