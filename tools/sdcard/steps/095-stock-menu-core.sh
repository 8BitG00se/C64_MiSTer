#!/bin/sh
# 095 - the stock menu core: MiSTer's own menu.rbf (its white noise at power-on), back where it was.
#
# WHY: build 3 and earlier put an Octophonic navy menu.rbf in (step 090, now gone). Neal wants the
# stock white-noise menu back. The navy step kept the stock one as menu.rbf.stock (the first time
# only) and in octophonic/backups; this step copies that back over menu.rbf, keeping the navy one in
# the backups. On a card that never had the navy core (a fresh image) there is nothing to do.
# A MiSTer update puts the stock one back too. Idempotent: run twice, the second run changes nothing.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

CUR="$OCTO_ROOT/menu.rbf"
STK="$OCTO_ROOT/menu.rbf.stock"
if [ ! -e "$STK" ]; then
    octo_say "no menu.rbf.stock: this card never had the navy menu core - the menu core is MiSTer's own"
    octo_mark_done "no navy menu core to take out"
    exit 0
fi
SZ=$(wc -c < "$STK")
[ "$SZ" -gt 1000000 ] || { echo "menu.rbf.stock is only $SZ bytes - not a menu core, left alone"; exit 1; }
if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$STK")" ]; then
    octo_say "menu.rbf is already the stock one"
    octo_mark_done "stock menu.rbf already $(octo_md5 "$CUR")"
    exit 0
fi
[ -e "$CUR" ] && { octo_backup "$CUR" || exit 1; }
cp -f "$STK" "$CUR.octo-new" && mv -f "$CUR.octo-new" "$CUR" || exit 1
sync
[ "$(octo_md5 "$CUR")" = "$(octo_md5 "$STK")" ] || { echo "the copy does not match"; exit 1; }
octo_mark_done "stock menu.rbf back: $(octo_md5 "$CUR")"
