#!/bin/sh
# OCTOPHONIC: puts a core in place on the MiSTer - run there by every install .bat (core and OS builds).
#   sh /tmp/install_core.sh C64_Octophonic_<date>_<tag>.rbf <order> [force]
# <order> grows with every core build (the core line's number); the core in place is recorded in
# /media/fat/_Octophonic/core.txt. A NEWER core than this one is never replaced without "force"
# (exit 3). Nothing is deleted: the core that was there goes to _Octophonic/old cores.
NEW="$1"; ORD="$2"; FORCE="$3"
cd "${OCTO_ROOT:-/media/fat}" || exit 1
[ -e "/tmp/$NEW" ] || { echo "the new core did not arrive in /tmp"; exit 1; }
mkdir -p "_Octophonic/old cores"
CUR=""
for f in _Computer/.C64_Octophonic_*.rbf; do [ -e "$f" ] && CUR=$(basename "$f"); done
CURORD=0
if [ -n "$CUR" ]; then
	if grep -qx "NAME=$CUR" _Octophonic/core.txt 2>/dev/null; then
		CURORD=$(sed -n 's/^ORDER=//p' _Octophonic/core.txt)
	else
		case "$CUR" in                       # the cores from before core.txt
			*_v11b6.rbf) CURORD=6 ;;
			*_mem1.rbf)  CURORD=7 ;;
			*_mem2.rbf)  CURORD=8 ;;
			*)           CURORD=0 ;;
		esac
	fi
fi
if [ "${CURORD:-0}" -gt "$ORD" ] && [ "$FORCE" != force ]; then
	echo "A NEWER CORE IS ALREADY ON THE MISTER: ${CUR#.} (core number $CURORD; this one is $ORD)."
	echo "It was NOT replaced."
	rm -f "/tmp/$NEW"
	exit 3
fi
for f in _Computer/.C64_Octophonic_*.rbf; do [ -e "$f" ] && mv -f "$f" "_Octophonic/old cores/"; done
mv "/tmp/$NEW" "_Computer/.$NEW" || exit 1
printf 'NAME=.%s\nORDER=%s\n' "$NEW" "$ORD" > _Octophonic/core.txt
# Fix 60: the Octophonic64RGB core sent with it (Octophonic64RGB_<date>.rbf, the same build) - hidden in _Computer
# beside the Octophonic core, one only; the one that was there goes to _Octophonic/old cores
for r in /tmp/Octophonic64RGB_*.rbf; do
	[ -s "$r" ] || continue
	for f in _Computer/.Octophonic64RGB_*.rbf; do [ -e "$f" ] && mv -f "$f" "_Octophonic/old cores/"; done
	mv "$r" "_Computer/.$(basename "$r")" && echo "Octophonic64RGB core: $(basename "$r")"
done
sync
[ -n "$CUR" ] && [ "$CUR" != ".$NEW" ] && echo "(the core that was there, ${CUR#.}, is in _Octophonic/old cores)"
echo "Now active: $NEW"
