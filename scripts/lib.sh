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
