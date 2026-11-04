# OCTOPHONIC SD RECIPE - shared helpers. Sourced by every step; not run on its own.
#
# Rules every step keeps:
#   - it can be run twice with no harm: it checks first and only changes what needs changing
#   - it backs up anything it replaces
#   - on success it writes ONE line to $OCTO_ROOT/octophonic/steps-done.txt
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
    printf '%s %s %s\n' "$(octo_name)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1:-ok}" >> "$OCTO_DONE"
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
