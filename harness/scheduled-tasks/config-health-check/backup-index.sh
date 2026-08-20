#!/usr/bin/env bash
# 保管庫索引の退避。正本はユーザースコープ（配布物ではない）ため、
# 壊れたときに戻せる先がここしかない。リポジトリ側へ上書きコピーするだけ。
# 使い方: bash backup-index.sh

set -u

INDEX="/c/Users/nr202/.claude/rules/保管庫索引.md"
DEST_DIR="/c/Users/nr202/projects/work/vault-index"
DEST="$DEST_DIR/保管庫索引.md"

[ -f "$INDEX" ] || { echo "FATAL: 索引が見つかりません: $INDEX"; exit 1; }

# 空・極端に短いものを退避すると、壊れた版でバックアップを潰す。
lines=$(wc -l < "$INDEX")
if [ "$lines" -lt 20 ]; then
  echo "SKIP: 索引が $lines 行しかありません。退避しません（壊れている可能性）"
  exit 1
fi

mkdir -p "$DEST_DIR"

if [ -f "$DEST" ] && cmp -s "$INDEX" "$DEST"; then
  echo "変化なし: $DEST"
  exit 0
fi

# 世代1本だと、壊れた索引を退避した瞬間に唯一のバックアップが消える。
# 前回分を1本だけ残す（行数チェックをすり抜ける壊れ方に対する保険）。
[ -f "$DEST" ] && cp "$DEST" "$DEST_DIR/保管庫索引.prev.md"

cp "$INDEX" "$DEST"
echo "退避しました: $DEST（$lines 行）"
echo "※ git へのコミットは SKILL.md 第7節（config-health-check）が行う。"
