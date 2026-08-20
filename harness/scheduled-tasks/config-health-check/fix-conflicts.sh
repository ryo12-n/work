#!/usr/bin/env bash
# iCloud の衝突コピー（`〜 2.md` `〜 3.md`）を、判定できるものは強制的に解決する。
# 使い方: bash fix-conflicts.sh [--apply]   (--apply なしは dry-run)
#
# 判定の材料は2つだけ。**mtime は使わない。**
# iCloud は実体化のときに mtime を打ち直すため、内容の新しさを表さない
# （2026-08-18 に実物で確認。3秒差はダウンロード順であって編集順ではなかった）。
#
#   1. `updated:` 行を除いて byte 一致  → 本文が同じ。どれを採っても中身は変わらない
#   2. frontmatter の `updated:` が最大 → それを採る
#   どちらでも決まらなければ REPORT。自走で処理しない。
#
# 既知の穴（塞いでいない）:
#   - `〜 その 2.md` のように本人が付けた正規の名前を衝突コピーと誤認する経路がある。
#     本文が分岐していれば REPORT に落ちるが、構造的な穴として残っている
#   - iCloud のハングに対する timeout の効きは未検証。TERM が届かない I/O ブロックなら止まりうる
#
# 敗者は削除せず `~/.claude/backups/icloud-conflicts/<ts>/<相対パス>/` へ移動する。
# 正本が敗者になったときは、正本も同じ場所へ退避してから置き換える。
# 復元は退避先から元の名前へ mv（正本を置き換えた回だけは、どちらを正とするか決め直しが要る）。

set -u

VAULT="/c/Users/nr202/iCloudDrive/iCloud~md~obsidian"
QUARANTINE="/c/Users/nr202/.claude/backups/icloud-conflicts"
LEDGER="$QUARANTINE/解決済み.txt"

cd "$VAULT" || { echo "FATAL: 保管庫が見つかりません: $VAULT"; exit 1; }

APPLY=0
case "${1:-}" in
  "")       APPLY=0 ;;
  --apply)  APPLY=1 ;;
  *)        echo "FATAL: 不明な引数: $1（使えるのは --apply のみ）"; exit 1 ;;
esac

RUN_DIR="$QUARANTINE/$(date -u +%Y%m%dT%H%M%SZ)"

# frontmatter（先頭の --- から次の --- まで）の updated: 行だけを落とした全文。
# 本文中の updated: は落とさない。落とすと実在する内容差を「同一」と誤判定する。
body() {
  awk 'NR==1 && $0=="---" {fm=1; print; next}
       fm==1 && $0=="---" {fm=2; print; next}
       fm==1 && /^updated:[[:space:]]/ {next}
       {print}' "$1"
}

# frontmatter の updated: の日付（無ければ空）。本文の updated: は見ない
updated_of() {
  awk 'NR==1 && $0!="---" {exit}
       NR>1 && $0=="---" {exit}
       /^updated:[[:space:]]/ {print; exit}' "$1" 2>/dev/null \
    | grep -oP '^updated:[[:space:]]*\K[0-9]{4}-[0-9]{2}-[0-9]{2}'
}

# 正本ごとに一度でも強制解決していれば記録が残る。番号が 2→3 と進んでも捕まえる。
seen_before() { [ -f "$LEDGER" ] && grep -qxF "$1" <(cut -f2 "$LEDGER" 2>/dev/null); }

# 退避。複製してから消す。**mv を使わない。**
# iCloud フォルダから外へ mv すると、削除の段で無期限に止まることがある
# （2026-08-18 に実測。120秒待っても返らず、プロセスを落として復帰した）。
# 日次タスクが固まらないよう、どちらの段にも制限時間を置く。
# 戻り値 0=退避して衝突コピーも消えた / 2=退避はできたが衝突コピーが残った / 1=失敗
quarantine() {  # $1=保管庫ルート相対パス
  local p="$1" d b
  d="$RUN_DIR/$(dirname "$p")"; b=$(basename "$p")
  mkdir -p "$d" || return 1
  if ! timeout -k 5 30 cp "$p" "$d/"; then
    echo "          FAIL  退避の複製に失敗した（またはタイムアウト）: $p"; return 1
  fi
  if ! cmp -s "$p" "$d/$b"; then
    echo "          FAIL  退避の内容が一致しない: $p"; return 1
  fi
  echo "          退避: $d/$b"
  if ! timeout -k 5 30 rm -f "$p"; then
    echo "          注意: 退避は済んだが iCloud が削除を止めている。衝突コピーが残る: $p"
    return 2
  fi
  return 0
}

groups=0; resolved=0; reported=0

# 正本名でグループ化する
while IFS= read -r orig; do
  [ -z "$orig" ] && continue
  groups=$((groups+1))

  # この正本名を指す候補を集める（衝突コピー群＋正本）
  mapfile -t cand < <(
    find "$(dirname "$orig")" -maxdepth 1 -name "$(basename "$orig" .md) [2-9].md" 2>/dev/null | sed 's|^\./||' | sort
  )
  [ -e "$orig" ] && cand+=("$orig")

  # 走査の合間に iCloud が消した／名前にグロブ文字が入っていた等。1件も拾えなければ飛ばす。
  # ここで空配列を参照すると set -u で残りのグループごと落ちる。
  if [ "${#cand[@]}" -eq 0 ]; then
    echo "■ $orig — 候補を1本も拾えなかった。飛ばす"
    reported=$((reported+1)); continue
  fi

  echo "■ $orig（候補 ${#cand[@]} 本）"

  # 判定に使った時点の mtime。書き換える直前に再確認して、途中で動いていたら降りる
  declare -A mtime_at_scan=()
  for f in "${cand[@]}"; do mtime_at_scan["$f"]=$(stat -c '%Y' "$f"); done

  if seen_before "$orig"; then
    echo "  REPORT  前にも強制解決している。毎日入れ替わっている可能性がある。手で見る"
    reported=$((reported+1)); continue
  fi

  # 判定1: 本文（updated: を除く）が全て一致するか
  same_body=1
  for f in "${cand[@]}"; do
    if ! diff -q <(body "${cand[0]}") <(body "$f") >/dev/null 2>&1; then same_body=0; break; fi
  done

  winner=""; reason=""
  if [ "$same_body" -eq 1 ]; then
    # 本文が同じ。updated: が最大のものを採る。中身は変わらないので、
    # 判定できないときの既定は「正本を動かさない」＝正本があればそれ。
    best=""; winner=""
    for f in "${cand[@]}"; do [ "$f" = "$orig" ] && winner="$orig"; done
    [ -z "$winner" ] && winner="${cand[0]}"
    for f in "${cand[@]}"; do
      u=$(updated_of "$f")
      if [ -n "$u" ] && { [ -z "$best" ] || [[ "$u" > "$best" ]]; }; then best="$u"; winner="$f"; fi
    done
    reason="本文は全て同一（差は updated: のみ）"
  else
    # 判定2: updated: が全てにあり、最大が1本だけか
    best=""; top=0; winner=""
    for f in "${cand[@]}"; do
      u=$(updated_of "$f")
      [ -z "$u" ] && { winner=""; break; }
      if [ -z "$best" ] || [[ "$u" > "$best" ]]; then best="$u"; winner="$f"; top=1
      elif [ "$u" = "$best" ]; then top=$((top+1)); fi
    done
    if [ -z "$winner" ]; then
      echo "  REPORT  本文が分岐しており、updated: を持たない候補がある。内容を読む判断が要る"
      reported=$((reported+1)); continue
    fi
    if [ "$top" -gt 1 ]; then
      echo "  REPORT  本文が分岐しており、updated: が同日で並んでいる（$best）。内容を読む判断が要る"
      reported=$((reported+1)); continue
    fi
    reason="updated: が最新（$best）。本文は分岐している"
  fi

  echo "  勝者    $winner — $reason"
  for f in "${cand[@]}"; do
    [ "$f" = "$winner" ] && continue
    n=$(diff <(body "$winner") <(body "$f") 2>/dev/null | grep -c '^>')
    echo "  敗者    $f — 敗者にしかない行: ${n}"
  done

  if [ "$APPLY" -eq 0 ]; then
    echo "  WOULD   $winner -> $orig"
    resolved=$((resolved+1)); continue
  fi

  # --- 適用 ---
  if [ "$winner" = "$orig" ]; then
    # 正本が勝者。敗者を退避するだけ
    ok=1
    for f in "${cand[@]}"; do
      [ "$f" = "$winner" ] && continue
      quarantine "$f"; rc=$?
      [ "$rc" -eq 1 ] && ok=0
      [ "$rc" -eq 2 ] && [ "$ok" -ne 0 ] && ok=2
    done
    case "$ok" in
      1) echo "  FIX     正本が最新だった。衝突コピーを退避した"; resolved=$((resolved+1)) ;;
      2) echo "  PART    正本は正しい。退避は済んだが衝突コピーが消せていない"; reported=$((reported+1)) ;;
      *) echo "  FAIL    衝突コピーの退避に失敗した。正本は無傷"; reported=$((reported+1)) ;;
    esac
    # 本文が分岐していた回は、正本が勝っていても台帳へ残す。毎日湧くのを検知するため
    if [ "$ok" -ne 0 ] && [ "$same_body" -eq 0 ]; then
      mkdir -p "$QUARANTINE"
      printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$orig" >> "$LEDGER"
    fi
    continue
  fi

  # 判定してから書き換えるまでに動いた候補があれば、何もせず降りる
  moved=""
  for f in "${cand[@]}"; do
    [ "$(stat -c '%Y' "$f")" != "${mtime_at_scan[$f]}" ] && moved="$f"
  done
  if [ -n "$moved" ]; then
    echo "  ABORT   処理中に $moved が変更された。触らず降りる"
    reported=$((reported+1)); continue
  fi

  w_mtime="${mtime_at_scan[$winner]}"
  restored_orig=""

  if [ -e "$orig" ]; then
    restored_orig="$RUN_DIR/$(dirname "$orig")/$(basename "$orig")"
    quarantine "$orig" || { echo "  FAIL    正本の退避に失敗した"; reported=$((reported+1)); continue; }
  fi

  if ! cp "$winner" "$orig"; then
    echo "  FAIL    正本名への複製に失敗した"
    [ -n "$restored_orig" ] && mv "$restored_orig" "$orig" && echo "          退避した正本を戻した"
    reported=$((reported+1)); continue
  fi

  if ! cmp -s "$winner" "$orig"; then
    # 並行セッションが同じ名前へ書いた可能性がある。作りかけを消して元へ戻す。
    # 保管庫内の削除は止められることがあるので、ここにも制限時間を置く
    timeout -k 5 30 rm -f "$orig"
    [ -n "$restored_orig" ] && mv "$restored_orig" "$orig" && echo "          退避した正本を戻した"
    echo "  FAIL    複製後の内容が一致しない。元の状態へ戻して中止した"
    reported=$((reported+1)); continue
  fi

  if [ "$(stat -c '%Y' "$winner")" != "$w_mtime" ]; then
    echo "  ABORT   処理中に勝者が変更された。$orig を作ったまま止める。手で見る"
    reported=$((reported+1)); continue
  fi

  ok=1
  for f in "${cand[@]}"; do
    [ "$f" = "$orig" ] && continue
    quarantine "$f"; rc=$?
    [ "$rc" -eq 1 ] && ok=0
    [ "$rc" -eq 2 ] && [ "$ok" -ne 0 ] && ok=2
  done

  if [ "$ok" -ne 0 ]; then
    [ "$ok" -eq 2 ] && echo "  PART    $winner -> $orig（退避は済んだが衝突コピーが消せていない）" \
                    || echo "  FIX     $winner -> $orig"
    [ "$ok" -eq 2 ] && reported=$((reported+1)) || resolved=$((resolved+1))
    # 本文が分岐していた回だけ台帳へ残す。ピンポンの検知に使う
    if [ "$same_body" -eq 0 ]; then
      mkdir -p "$QUARANTINE"
      printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$orig" >> "$LEDGER"
    fi
  else
    reported=$((reported+1))
  fi
done < <(
  find . -regex '.* [2-9]\.md' \
    | grep -v "^./.Trash" \
    | sed 's|^\./||' \
    | sed -E 's/ [2-9]\.md$/.md/' \
    | sort -u
)

echo "---"
if [ "$groups" -eq 0 ]; then
  echo "衝突コピーはありません。"
  exit 0
fi
echo "正本 ${groups} 件 / 解決 ${resolved} / 報告 ${reported}"
[ "$APPLY" -eq 0 ] && echo "（dry-run。適用するには --apply を付ける）"
echo "退避先: $RUN_DIR"
echo "もどし方: 退避先のファイルを元の名前へ mv する"

[ "$reported" -gt 0 ] && exit 2
exit 0
