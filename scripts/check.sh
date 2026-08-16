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
# テスト分離のためのガード: 未コミット判定は原本が本当にこのリポジトリの harness/
# であるときにしか意味を持たない。比較は文字列の完全一致で行う（パス正規化はしない）。
if [ "$HARNESS_SOURCE" = "$REPO_ROOT/harness" ] && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  DIRTY="$(git -C "$REPO_ROOT" status --porcelain -- harness || true)"
  if [ -n "$DIRTY" ]; then
    report "未コミット: harness/ に未コミットの変更があります。"
    printf '%s\n' "$DIRTY" | sed 's/^/    /'
  fi
else
  printf '%s\n' "（未コミット判定はスキップ: HARNESS_SOURCE がこのリポジトリの harness/ ではありません）"
fi

if [ "$ISSUES" -eq 0 ]; then
  printf '異常なし\n'
  exit 0
fi
exit 1
