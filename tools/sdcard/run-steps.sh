#!/bin/sh
# OCTOPHONIC SD RECIPE - the runner.
#
# Runs every step in steps/ that is NOT already listed in
# $OCTO_ROOT/octophonic/steps-done.txt, in number order, and stops at the first failure.
# Running it again is always safe: finished steps are skipped, and every step is written so
# that running it twice changes nothing the second time.
#
#   sh run-steps.sh              bring this card up to date (skips -DEV- steps)
#   OCTO_DEV=1 sh run-steps.sh   also run Neal's own -DEV- steps
#   OCTO_FORCE=1 sh run-steps.sh run every step again, done or not
#   OCTO_ONLY=030 sh run-steps.sh   run just the step whose number is 030
#   OCTO_LIST=1 sh run-steps.sh  say what WOULD run, change nothing
#   OCTO_ROOT=/mnt/newcard sh run-steps.sh    build a fresh card (the release .img)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/octo-step-lib.sh"
export OCTO_ROOT OCTO_PAYLOAD
OCTO_RUNSTAMP="run-$(date -u +%Y%m%d-%H%M%S)"
export OCTO_RUNSTAMP

echo "==================================================================="
echo " OCTOPHONIC SD RECIPE"
echo "==================================================================="
echo " card:     $OCTO_ROOT"
echo " payload:  $OCTO_PAYLOAD"
echo " DEV steps: $([ "${OCTO_DEV:-0}" = 1 ] && echo "YES (Neal's machine)" || echo "no (skipped - this is how the release image is built)")"
echo " done list: $OCTO_DONE"
echo

[ -d "$OCTO_ROOT" ] || { echo "there is no $OCTO_ROOT - is the card there?"; exit 1; }
mkdir -p "$OCTO_STATE" 2>/dev/null || { echo "cannot write to $OCTO_STATE"; exit 1; }
[ -f "$OCTO_DONE" ] || : > "$OCTO_DONE"

RAN=0; SKIPPED=0; FAILED=0
for S in "$HERE"/steps/*.sh; do
    [ -e "$S" ] || continue
    N=$(basename "$S")
    NUM=$(printf '%s' "$N" | sed 's/[^0-9].*//')

    if [ -n "${OCTO_ONLY:-}" ] && [ "$NUM" != "$OCTO_ONLY" ]; then continue; fi

    case "$N" in
        *-DEV-*)
            if [ "${OCTO_DEV:-0}" != 1 ]; then
                echo "-- $N   SKIPPED (DEV only - not part of the release image)"
                SKIPPED=$((SKIPPED+1)); continue
            fi ;;
    esac

    if [ "${OCTO_FORCE:-0}" != 1 ] && grep -q "^$N " "$OCTO_DONE" 2>/dev/null; then
        echo "-- $N   already done ($(grep "^$N " "$OCTO_DONE" | tail -1 | awk '{print $2}'))"
        SKIPPED=$((SKIPPED+1)); continue
    fi

    if [ "${OCTO_LIST:-0}" = 1 ]; then
        echo "++ $N   WOULD RUN"
        RAN=$((RAN+1)); continue
    fi

    echo "++ $N"
    if sh "$S"; then
        RAN=$((RAN+1))
    else
        RC=$?
        echo
        echo "!! $N FAILED (exit $RC). Stopping here so nothing further is changed."
        echo "   Nothing after this step has run. Fix it and run this again -"
        echo "   the steps that did finish are recorded and will be skipped."
        FAILED=1
        break
    fi
    echo
done

echo "==================================================================="
if [ "${OCTO_LIST:-0}" = 1 ]; then
    echo " would run: $RAN    already done or skipped: $SKIPPED"
else
    echo " ran: $RAN    skipped: $SKIPPED"
fi
echo "==================================================================="
if [ "$FAILED" = 1 ]; then echo "RECIPE_FAILED"; exit 1; fi
echo
echo "steps-done.txt:"
cat "$OCTO_DONE"
echo
echo "RECIPE_OK"
