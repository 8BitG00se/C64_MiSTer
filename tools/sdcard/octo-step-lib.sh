# OCTOPHONIC SD RECIPE - shared helpers. Sourced by every step; not run on its own.
#
# Rules every step keeps:
#   - it can be run twice with no harm: it checks first and only changes what needs changing
#   - it backs up anything it replaces
#   - on success it writes ONE line to $OCTO_ROOT/octophonic/steps-done.txt
#   - it never restarts anything (Main, the core, the MiSTer). Restarts are the installer's job, and
#     the installer writes each one, with its time, to octophonic/update.log
#
# Steps that CARRY A FILE (the core, Main, SHELL.PRG, oled.sh ...) have the line
#     # OCTO-RECHECK
# near the top. The runner runs those again even when steps-done.txt lists them, and the step itself
# compares the payload's md5 with what is on the card (octo_skip_if_current): the same -> nothing
# happens; different -> it installs the new one, backs up the old, and logs "updated <old> -> <new>".
# That is how a NEWER core / Main / SHELL.PRG reaches a card that ran the step long ago.
#
# Settings a caller may pass in:
#   OCTO_ROOT     the card (default /media/fat). The image build points this at the new card.
#   OCTO_PAYLOAD  where the files to install live (default ../files beside the steps)
#   OCTO_DEV      1 = also run the -DEV- steps (Neal's own machine). The image build leaves it unset.
#   OCTO_FORCE    1 = run a step even if steps-done.txt already lists it
#   OCTO_RUNSTAMP a name for this run's backup folder (the runner sets it)

OCTO_ROOT="${OCTO_ROOT:-/media/fat}"
OCTO_STATE="$OCTO_ROOT/octophonic"
OCTO_DONE="$OCTO_STATE/steps-done.txt"
OCTO_BACKUPS="$OCTO_STATE/backups"
OCTO_RUNSTAMP="${OCTO_RUNSTAMP:-manual-$(date -u +%Y%m%d-%H%M%S)}"
if [ -z "${OCTO_PAYLOAD:-}" ]; then
    OCTO_PAYLOAD="$(cd "$(dirname "$0")/../files" 2>/dev/null && pwd)"
    [ -n "$OCTO_PAYLOAD" ] || OCTO_PAYLOAD="$(dirname "$0")/../files"
fi

octo_name() { basename "$0"; }
octo_say()  { printf '    %s\n' "$*"; }

# already recorded as done?
octo_is_done() {
    [ "${OCTO_FORCE:-0}" = 1 ] && return 1
    [ -f "$OCTO_DONE" ] || return 1
    grep -q "^$(octo_name) " "$OCTO_DONE"
}

# record this step as finished. One line, as Neal asked.
octo_mark_done() {
    mkdir -p "$OCTO_STATE" 2>/dev/null
    if [ -f "$OCTO_DONE" ] && grep -q "^$(octo_name) " "$OCTO_DONE"; then
        # re-run: replace the old line rather than letting the file grow
        grep -v "^$(octo_name) " "$OCTO_DONE" > "$OCTO_DONE.new" 2>/dev/null || :
        mv -f "$OCTO_DONE.new" "$OCTO_DONE"
    fi
    _note="${1:-ok}"
    if [ -n "$OCTO_UPDATED" ]; then _note="$OCTO_UPDATED | $_note"; fi
    printf '%s %s %s\n' "$(octo_name)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_note" >> "$OCTO_DONE"
    octo_log "$_note"
    sync
}

# back up one file before replacing it. Keeps the path shape so same-named files never clash.
octo_backup() {
    [ -e "$1" ] || return 0
    B="$OCTO_BACKUPS/$OCTO_RUNSTAMP"
    mkdir -p "$B" || return 1
    REL=$(printf '%s' "$1" | sed "s|^$OCTO_ROOT/||" | tr '/' '~')
    cp -p "$1" "$B/$REL" || return 1
    octo_say "backed up: $1  ->  octophonic/backups/$OCTO_RUNSTAMP/$REL"
}

octo_md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# one line to octophonic/update.log (the install log Neal reads)
octo_log() {
    mkdir -p "$OCTO_STATE" 2>/dev/null
    printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(octo_name)" "$*" >> "$OCTO_STATE/update.log"
}

# For an OCTO-RECHECK step, called first thing, before anything is changed:
#   octo_skip_if_current "<payload file>|<file on the card>" ...
# Not done yet            -> returns (the step runs as normal - a first install).
# Done, every pair the same md5, or no payload brought this time -> says so and EXITS the step (0).
# Done, a payload differs -> says old/new, sets OCTO_UPDATED, returns (the step installs it).
# OCTO_LIST=1: only says what it would do, and exits.
OCTO_UPDATED=""
octo_skip_if_current() {
    if ! octo_is_done; then
        [ "${OCTO_LIST:-0}" = 1 ] && { octo_say "WOULD RUN (first time)"; exit 0; }
        return 0
    fi
    _diff=""; _have=0
    for _pair in "$@"; do
        _p=${_pair%%|*}; _c=${_pair#*|}
        [ -n "$_p" ] && [ -s "$_p" ] || continue
        _have=1
        _pm=$(octo_md5 "$_p"); _cm=$(octo_md5 "$_c"); [ -n "$_cm" ] || _cm=none
        [ "$_pm" = "$_cm" ] || _diff="$_diff $(basename "$_c") ${_cm} -> ${_pm};"
    done
    if [ "$_have" = 0 ]; then
        octo_say "already done (this update brings no new file for it)"; exit 0
    fi
    if [ -z "$_diff" ]; then
        octo_say "already done, and the card has exactly this version (md5 the same) - nothing changed"; exit 0
    fi
    # an OLDER package than the card (its core number is lower than the core in place) changes nothing:
    # Main and SHELL.PRG must stay with the newer core they were made for
    _pn=$(tr -dc '0-9' < "$OCTO_PAYLOAD/core-number.txt" 2>/dev/null)
    _cn=$(sed -n 's/^ORDER=//p' "$OCTO_ROOT/_Octophonic/core.txt" 2>/dev/null | tr -dc '0-9')
    if [ -n "$_pn" ] && [ -n "$_cn" ] && [ "$_cn" -gt "$_pn" ]; then
        octo_say "this update is OLDER than the card (its core number $_pn, the card's $_cn) - kept what is there, nothing changed"
        exit 0
    fi
    OCTO_UPDATED="updated:${_diff%;}"
    if [ "${OCTO_LIST:-0}" = 1 ]; then octo_say "WOULD UPDATE -$_diff"; exit 0; fi
    octo_say "already done once, but this update brings a different version -$_diff"
    octo_say "installing it (the old one is backed up)"
    return 0
}

# a payload file must be there before a step will change anything
octo_payload() {
    if [ -s "$OCTO_PAYLOAD/$1" ]; then
        printf '%s' "$OCTO_PAYLOAD/$1"
        return 0
    fi
    return 1
}

# is the root filesystem read-only? (it is, on a MiSTer: / is linux.img on a loop device)
octo_root_is_ro() { mount | grep ' / ' | grep -q 'ro,'; }
