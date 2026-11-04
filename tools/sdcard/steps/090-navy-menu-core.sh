#!/bin/sh
# 090 - the navy menu core: menu.rbf with the Octophonic navy where MiSTer paints its grey noise.
#
# WHY: at power-on the MiSTer's bootloader always loads menu.rbf first (u-boot_MiSTer: core=menu.rbf,
# loaded before u-boot.txt is even read), and the menu core shows its moving grey noise until Main
# puts a picture up - about 5 seconds on the VGA/analog output (HDMI stays dark until Main starts).
# The navy one is the same core (tools/octoos/menu: Menu_MiSTer at UPSTREAM, navy.sh, built by
# .github/workflows/octo-menu.yml onto the branch octo-menu-build). In MiSTer's own menu (C=+F1) the
# background, where it used to be noise, is navy too.
#
# The stock menu.rbf is kept as menu.rbf.stock the first time only (and in the backups), so going
# back is: copy menu.rbf.stock over menu.rbf. A MiSTer update puts the stock one back.
# Payload wanted: files/menu.rbf (the navy one). Without it this step says so and is NOT marked
# done, so a later run picks it up - the rest of the recipe still runs.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

NEW=$(octo_payload menu.rbf) || {
    octo_say "no navy menu.rbf in the payload yet - the stock menu core stays (grey noise at power-on)"
    octo_say "not marked done: the next run puts it in once the payload has it"
    exit 0
}
CUR="$OCTO_ROOT/menu.rbf"
SZ=$(wc -c < "$NEW")
[ "$SZ" -gt 1000000 ] || { echo "files/menu.rbf is only $SZ bytes - not a menu core"; exit 1; }
octo_say "navy menu.rbf: $(octo_md5 "$NEW")  ($SZ bytes)"

if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ]; then
    octo_say "the navy menu core is already in place - nothing changed"
    octo_mark_done "navy menu.rbf already $(octo_md5 "$NEW")"
    exit 0
fi
if [ -e "$CUR" ]; then
    if [ -e "$OCTO_ROOT/menu.rbf.stock" ]; then
        octo_say "menu.rbf.stock already kept - left alone"
    else
        cp -p "$CUR" "$OCTO_ROOT/menu.rbf.stock" || exit 1
        octo_say "the stock menu core kept as menu.rbf.stock"
    fi
    octo_backup "$CUR" || exit 1
fi
cp -f "$NEW" "$CUR.octo-new" && mv -f "$CUR.octo-new" "$CUR" || exit 1
sync
[ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ] || { echo "the copy does not match"; exit 1; }
octo_mark_done "navy menu.rbf $(octo_md5 "$CUR")"
