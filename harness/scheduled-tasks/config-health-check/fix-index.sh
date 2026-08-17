#!/usr/bin/env bash
# MEMORY.md（索引）のリンク切れを、ベース名で一意に解決できるものだけ自動修復する。
# 曖昧なもの・見つからないものは報告のみ。
# 使い方: bash fix-index.sh [--apply]   (--apply なしは dry-run)

VAULT="/c/Users/nr202/iCloudDrive/iCloud~md~obsidian"
INDEX="personal/AIメモリ/MEMORY.md"   # 索引は1本だけ。探索しない（別の MEMORY.md を書き換えないため）

cd "$VAULT" || { echo "FATAL: 保管庫が見つかりません: $VAULT"; exit 1; }
[ -f "$INDEX" ] || { echo "FATAL: 索引が見つかりません: $INDEX"; exit 1; }

APPLY=0
case "${1:-}" in
  "")       APPLY=0 ;;
  --apply)  APPLY=1 ;;
  *)        echo "FATAL: 不明な引数: $1（使えるのは --apply のみ）"; exit 1 ;;
esac

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$INDEX" "$TMP/work.md"
MTIME_BEFORE=$(stat -c '%Y' "$INDEX")

broken=0; fixed=0; ambiguous=0; missing=0; failed=0

while IFS= read -r p; do
  [ -z "$p" ] && continue
  case "$p" in http*|\#*|/*) continue ;; esac
  # 記法の例示（本文中の `](パス)` など）を実リンクと誤認しない。
  # 索引のリンク先は全て .md。非 .md を索引へ書いたときは linkcheck.sh 側が拾う。
  case "$p" in *.md) ;; *) continue ;; esac
  # Markdown リンクの %20 は実ファイル名の空白（linkcheck.sh と同じ扱い）。
  # デコードせずに照合すると、実在するファイルを GONE と誤報する。
  # 置換キーは索引の表記そのままである必要があるため $p は書き換えない。
  decoded=$(printf '%s' "$p" | sed 's/%20/ /g')
  [ -e "$decoded" ] && continue
  broken=$((broken+1))

  base=$(basename "$decoded")
  mapfile -t hits < <(find . -name "$base" -not -path "./.Trash/*" -not -path "./.obsidian/*" | sed 's|^\./||')

  if [ "${#hits[@]}" -eq 1 ]; then
    # 索引へ書き戻す表記は空白を %20 へ再エンコードする。生の空白のまま書くと
    # Obsidian/CommonMark 上は未解決なのに、-e 判定では健全に見えるリンクができる。
    new=$(printf '%s' "${hits[0]}" | sed 's/ /%20/g')
    # BRE のメタ文字と sed の区切り(|)・置換特殊文字(&)をすべてエスケープする。
    # ここを漏らすと「FIX と報告したのに置換は空振り」という最悪の故障になる。
    esc_old=$(printf '%s' "$p"   | sed 's/[][\.*^$&|\\]/\\&/g')
    esc_new=$(printf '%s' "$new" | sed 's/[&|\\]/\\&/g')
    if sed -i "s|](${esc_old})|](${esc_new})|g" "$TMP/work.md" \
       && ! grep -qF "](${p})" "$TMP/work.md"; then
      echo "  FIX   $p"
      echo "        -> $new"
      fixed=$((fixed+1))
    else
      echo "  FAIL  $p — 置換に失敗した（パスに特殊文字が含まれる可能性）"
      failed=$((failed+1))
    fi
  elif [ "${#hits[@]}" -gt 1 ]; then
    echo "  AMBIG $p — 同名が複数。索引のそのセクションがどのストリームの話かを読んで決める"
    printf '        候補: %s\n' "${hits[@]}"
    ambiguous=$((ambiguous+1))
  else
    echo "  GONE  $p — 実体が見つからない。削除されたか、索引が知らない名前に改名された"
    missing=$((missing+1))
  fi
done < <(grep -oP '\]\(\K[^)]+' "$INDEX" | sort -u)

echo "---"
echo "壊れ ${broken} / 修復可 ${fixed} / 曖昧 ${ambiguous} / 実体なし ${missing} / 置換失敗 ${failed}"

if [ "$broken" -eq 0 ]; then
  echo "索引は健全です。"
  exit 0
fi

if [ "$APPLY" -eq 1 ] && [ "$fixed" -gt 0 ]; then
  # 読み取り後に索引が書き換わっていたら降りる（iCloud 同期・本人の編集との競合を避ける）
  if [ "$(stat -c '%Y' "$INDEX")" != "$MTIME_BEFORE" ]; then
    echo "中止: 処理中に索引が変更されました。競合を避けるため適用しません。再実行してください。"
    exit 2
  fi
  cp "$TMP/work.md" "$INDEX"
  echo "適用しました: $INDEX"
elif [ "$fixed" -gt 0 ]; then
  echo "（dry-run。適用するには --apply を付ける）"
fi

# 人の判断が要るものが残っていれば非ゼロで返す
if [ "$ambiguous" -gt 0 ] || [ "$missing" -gt 0 ] || [ "$failed" -gt 0 ]; then
  exit 2
fi
exit 0
