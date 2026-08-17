#!/usr/bin/env bash
# 保管庫のリンク切れ検出。プレースホルダ（<...> や 人名/ファイル名 等）は除外する。
VAULT="/c/Users/nr202/iCloudDrive/iCloud~md~obsidian"
cd "$VAULT" || { echo "FATAL: 保管庫が見つかりません: $VAULT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

find . -name "*.md" -not -path "./.Trash/*" -not -path "./.obsidian/*" > "$TMP/files.txt"
while IFS= read -r f; do basename "$f" .md; done < "$TMP/files.txt" > "$TMP/names.txt"
# 添付（画像等）も [[…]] の解決先になる。拡張子付きベース名で照合する。
# 除外ではなく照合対象の正確化なので、実在しない添付は引き続き BROKEN に出る。
find . -type f -not -name "*.md" -not -path "./.Trash/*" -not -path "./.obsidian/*" -not -path "./.git/*" \
  | while IFS= read -r f; do basename "$f"; done >> "$TMP/names.txt"
sort -u -o "$TMP/names.txt" "$TMP/names.txt"

# 保管庫の外に実体があるリンク先（ハーネス側のルール等）。BROKEN と分けて EXTERNAL で出す。
# 白リストにしないのは、規約ファイルが改名されたときに切れを見逃さないため。
find "$HOME/.claude" -name "*.md" -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r f; do basename "$f" .md; done | sort -u > "$TMP/extnames.txt"

# コードスパン・フェンスドブロックを落とす。記法の説明として書かれた `[[A]]` 等を
# 本物のリンクと区別するため。個別語のブロックリストにしないのは、
# 将来その名前の実ノートができたとき黙って取りこぼすため。
strip_code() {
  awk '/^[[:space:]]*```/{b=!b; next} !b' "$1" | sed 's/`[^`]*`//g'
}

# プレースホルダ判定：山括弧を含む、または以下の汎用語そのもの
is_placeholder() {
  case "$1" in
    *"<"*|*">"*|人名|ファイル名|名前|タイトル|日付|name|title|path|パス) return 0 ;;
  esac
  return 1
}

echo "### 対象 $(wc -l < "$TMP/files.txt") ファイル"

echo "### 1. CLAUDE.md の @import"
n=0
while IFS= read -r p; do
  if [ ! -f "$p" ]; then
    echo "  BROKEN  CLAUDE.md -> @$p"
    base=$(basename "$p")
    hit=$(find . -name "$base" -not -path "./.Trash/*" | head -3)
    [ -n "$hit" ] && echo "$hit" | sed 's|^\./|          候補: |'
    n=$((n+1))
  fi
done < <(grep -oE '@[^ ]+\.md' CLAUDE.md 2>/dev/null | sed 's/^@//' | sort -u)
[ "$n" -eq 0 ] && echo "  OK"

echo "### 2. [[wikilink]] の解決"
n=0
while IFS= read -r f; do
  strip_code "$f" | grep -oE '\[\[[^]|#]+' 2>/dev/null | sed 's/^\[\[//;s/[[:space:]]*$//' | sort -u | while IFS= read -r l; do
    [ -z "$l" ] && continue
    is_placeholder "$l" && continue
    grep -qxF "$l" "$TMP/names.txt" && continue
    if grep -qxF "$l" "$TMP/extnames.txt"; then
      echo "  EXTERNAL  ${f#./} -> [[$l]]（実体は ~/.claude 配下。Obsidian 上は未解決）"
    else
      echo "  BROKEN  ${f#./} -> [[$l]]"
    fi
  done
done < "$TMP/files.txt" | sort -u > "$TMP/wiki.txt"
if [ -s "$TMP/wiki.txt" ]; then cat "$TMP/wiki.txt"; else echo "  OK"; fi

echo "### 3. 本文中のパス参照（バッククォート内）"
# 層ルートからの論理参照（`10_log/` 等）を誤検知しないよう、
# 保管庫内の実在パスのいずれかに末尾一致すれば解決とみなす。
find . -not -path "./.Trash/*" -not -path "./.obsidian/*" -not -path "./.git/*" \
  | sed 's|^\./||' | sort -u > "$TMP/allpaths.txt"
while IFS= read -r f; do
  # 外部リポジトリの「これから作る」構成を記述した設計書。未作成なのが仕様。
  case "$f" in
    *ハーネスをリポジトリ管理/*) continue ;;
  esac
  grep -oE '`[0-9A-Za-z_./ぁ-んァ-ヶ一-龠々ー-]+`' "$f" 2>/dev/null | tr -d '`' | while IFS= read -r p; do
    case "$p" in
      */*) ;;                      # パスらしきものだけ見る
      *) continue ;;
    esac
    case "$p" in
      Craft/*|Notion/*) continue ;;  # 外部ソース。保管庫内に実体はない
      /*) continue ;;                # context7 のライブラリID（/llmstxt/... 等）や絶対パス
      *.claude/*|*scheduled-tasks/*) continue ;;  # 保管庫の外（スケジュールタスク）
      # 外部リポジトリのスラッグ。リテラル白リストにするのは、汎用の2セグメント除外だと
      # scripts/deploy.sh 型の本物の壊れと区別できないため。改名されれば陳腐化として出る。
      ryo12-n/work|anthropics/claude-plugins-official|asciidwango/js-primer) continue ;;
      *YYYY*) continue ;;            # スナップショット_YYYY-MM-DD 等のテンプレート表記
    esac
    # ドット付きドメイン（最初の / より前に . を含む）。保管庫のディレクトリ名にドットは出ない。
    case "${p%%/*}" in
      *.*) continue ;;
    esac
    is_placeholder "$p" && continue
    p="${p%/}"
    esc=$(printf '%s' "$p" | sed 's/[][\.*^$/]/\\&/g')
    grep -qE "(^|/)${esc}\$" "$TMP/allpaths.txt" || echo "  BROKEN  ${f#./} -> $p"
  done
done < "$TMP/files.txt" | sort -u > "$TMP/paths.txt"
if [ -s "$TMP/paths.txt" ]; then cat "$TMP/paths.txt"; else echo "  OK"; fi

echo "### 4. 索引（MEMORY.md）のリンク"
INDEX="personal/AIメモリ/MEMORY.md"   # 索引は1本だけ。探索しない
if [ ! -f "$INDEX" ]; then
  echo "  BROKEN  索引が見つかりません: $INDEX"
  hit=$(find . -name "MEMORY.md" -not -path "./.Trash/*" -not -path "./.obsidian/*" | sed 's|^\./|          候補: |')
  [ -n "$hit" ] && echo "$hit"
else
  echo "  索引: ${INDEX#./}"
  n=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    is_placeholder "$p" && continue
    case "$p" in http*|\#*|/*) continue ;; esac  # fix-index.sh と同じ除外条件に揃える
    # Markdown リンクの %20 は実ファイル名の空白。デコードせずに照合すると
    # 索引（最優先で報告する層）に偽の壊れが出る。
    p=$(printf '%s' "$p" | sed 's/%20/ /g')
    if [ ! -e "$p" ]; then
      echo "  BROKEN  ${INDEX#./} -> $p"
      base=$(basename "$p")
      hit=$(find . -name "$base" -not -path "./.Trash/*" | head -3)
      [ -n "$hit" ] && echo "$hit" | sed 's|^\./|          候補: |'
      n=$((n+1))
    fi
  done < <(grep -oP '\]\(\K[^)]+' "$INDEX" 2>/dev/null | sort -u)
  [ "$n" -eq 0 ] && echo "  OK"
fi

echo "### 5. iCloud の競合コピー"
conf=$(find . -name "* 2.md" -o -name "* 3.md" | grep -v "^./.Trash" | sed 's|^\./|  CONFLICT  |')
if [ -n "$conf" ]; then echo "$conf"; else echo "  OK"; fi

echo "### 6. 被リンクゼロのノート（20_knowledge のみ）"
n=0
while IFS= read -r f; do
  base=$(basename "$f" .md)
  cnt=$(grep -rlF "[[$base]]" --include="*.md" . 2>/dev/null | grep -v "^./.Trash" | grep -vxF "$f" | wc -l)
  [ "$cnt" -eq 0 ] && { echo "  ORPHAN  ${f#./}"; n=$((n+1)); }
done < <(grep '20_knowledge' "$TMP/files.txt")
[ "$n" -eq 0 ] && echo "  OK"
