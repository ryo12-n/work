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

# 状態ファイルへ「配布先の現状」を記録する。差分の有無に関わらず呼ぶことで、
# .harness-state が消えたり古いままだったりしても check.sh が正しく復帰できるようにする。
# --dry-run では絶対に呼ばない（何も書き込まないという契約を守るため）。
write_harness_state() {
  {
    printf '# deployedAt: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# commit: %s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      printf '%s  %s\n' "$(harness_sha "$HARNESS_TARGET/$p")" "$p"
    done < <(harness_source_files)
  } > "$HARNESS_STATE"
}

PLAN="$(harness_plan)"
CHANGES="$(printf '%s\n' "$PLAN" | grep -v '^SAME' || true)"

if [ -z "$CHANGES" ]; then
  printf '差分なし。\n'
  if [ "$DRY_RUN" -eq 0 ]; then
    write_harness_state
  fi
  exit 0
fi

printf '%s\n' "$CHANGES" | while IFS=$'\t' read -r action path; do
  printf '  %-6s %s\n' "$action" "$path"
done
printf '\n'

if [ "$DRY_RUN" -eq 1 ]; then
  # printf の書式文字列が `--` で始まるとオプションとして解釈され失敗する。%s 経由で渡す。
  printf '%s\n' '--dry-run のため反映しません。'
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
write_harness_state

printf '反映しました。バックアップ: %s\n' "$BACKUP_DIR"
