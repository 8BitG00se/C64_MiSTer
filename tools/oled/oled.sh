#!/bin/sh
# OCTOPHONIC 64 - the front screen (tty2oled), driven by Octophonic Main.  Lives in /media/fat/octophonic/oled.sh
#
#   oled.sh play "FILE.oled"   a program's own animation (Main: a program with a .oled beside it has started)
#   oled.sh logo               the Octophonic logo (Main: CTRL+F12, Esc held, the browser, the start screen)
#   oled.sh boot               Main has started with the Octophonic core: the logo, unless the tty2oled daemon is
#                              already looking after the screen (it sends the Octophonic picture itself, and the
#                              Octophonic screen firmware turns that into the animated logo)
#   oled.sh info               what this script knows (the screen's firmware, what is showing)
#
# The screen's firmware decides what can be shown:
#   230702-OCTO4 or later (8BitG00se/octophonic-tty2oled): the animation, sent once and held in the screen ("CMDOANI";
#     the same one again later costs nothing: "CMDOANP"); the logo with "CMDOCTO,0".
#   an older Octophonic or a stock tty2oled firmware: the still picture at the end of the .oled (as a core picture);
#     the logo comes back by itself with OCTO1-3 ("CMDOCTO,0"), or through the tty2oled daemon's own picture.
#   no screen, or no answer: nothing at all.
# Requests never cut a transfer short (the screen would read the next command as picture data): a newer request
# waits, and only the newest one is done once the line is free. Everything is logged to octophonic/oled.log.
S=${OCTO_OLED_STATE:-/tmp/octo_oled}
LOG=${OCTO_OLED_LOG:-/media/fat/octophonic/oled.log}
T2O=/media/fat/tty2oled

log() {
    [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 32768 ] && mv -f "$LOG" "$LOG.1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

tty_dev() {
    D=""
    for F in "$T2O/tty2oled-system.ini" "$T2O/tty2oled-user.ini"; do
        [ -r "$F" ] || continue
        V=$(sed -n 's/^[[:space:]]*TTYDEV="\{0,1\}\([^"#[:space:]]*\)"\{0,1\}.*/\1/p' "$F" | tail -1)
        [ -n "$V" ] && D=$V
    done
    echo "${D:-/dev/ttyUSB0}"
}
TTY=${OCTO_OLED_TTY:-$(tty_dev)}

daemon_running() {
    [ -e /run/tty2oled-daemon.pid ] && [ -d "/proc/$(cat /run/tty2oled-daemon.pid 2>/dev/null)" ] && return 0
    pidof tty2oled.sh >/dev/null 2>&1
}

setup_tty() { stty -F "$TTY" 115200 cs8 raw -parenb -cstopb -hupcl -echo 2>/dev/null; }

# the screen's firmware, asked once per power-on: "HWESP32DE;230702-OCTO4;" ("none": no answer)
firmware() {
    if [ ! -s "$S.fw" ]; then
        setup_tty
        cat "$TTY" > "$S.hw" 2>/dev/null &
        P=$!
        sleep 0.3
        printf 'CMDHWINF\n' > "$TTY"
        sleep 1.2
        kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
        FW=$(tr -d '\r\n' < "$S.hw" 2>/dev/null | grep -o 'HW[A-Z0-9]*;[^;]*;' | tail -1)
        echo "${FW:-none}" > "$S.fw"
        log "screen firmware: ${FW:-no answer} on $TTY"
    fi
    cat "$S.fw"
}

octo_level() {   # 4 for 230702-OCTO4, 0 for a stock or unknown firmware
    L=$(firmware | sed -n 's/.*-OCTO\([0-9][0-9]*\).*/\1/p')
    echo "${L:-0}"
}

do_play() {
    F=$1
    [ -r "$F" ] || { log "play: no file $F"; return; }
    [ "$(head -c 8 "$F")" = "OCTOANI1" ] || { log "play: $F is not an Octophonic animation (.oled)"; return; }
    H=$(od -An -tu1 -j8 -N8 "$F" 2>/dev/null)
    [ -n "$H" ] || H=$(python3 -c 'import sys; print(*open(sys.argv[1],"rb").read()[8:16])' "$F" 2>/dev/null)
    set -- $H
    [ $# -eq 8 ] || { log "play: could not read the header of $F"; return; }
    MS=$1; MODE=$2; FR=$(( $3 + $4 * 256 )); LEN=$(( $5 + $6 * 256 + $7 * 65536 + $8 * 16777216 ))
    LV=$(octo_level)
    if [ "$LV" -ge 4 ]; then
        SUM=$(md5sum "$F" | cut -c1-32)
        setup_tty
        if [ "$SUM" = "$(cat "$S.held" 2>/dev/null)" ]; then
            printf 'CMDOANP\n' > "$TTY"
            log "play (held in the screen already): $F"
        else
            : > "$S.held"
            { printf 'CMDOANI,%d,%d,%d,%d\n' "$LEN" "$FR" "$MS" "$MODE"; tail -c +17 "$F" | head -c "$LEN"; } > "$TTY"
            echo "$SUM" > "$S.held"
            log "play: $F ($FR frames, $LEN bytes)"
        fi
    elif [ "$(firmware)" != none ]; then
        setup_tty
        { printf 'CMDCOR,PRGSTILL,0\n'; sleep 0.2; tail -c 8192 "$F"; } > "$TTY"
        log "play: the still picture of $F (the screen's firmware $(firmware) has no animations)"
    fi
}

do_logo() {
    LV=$(octo_level)
    if [ "$LV" -ge 1 ]; then
        setup_tty
        printf 'CMDOCTO,0\n' > "$TTY"
        log "logo"
    elif daemon_running && [ -r /tmp/CORENAME ]; then
        C=$(cat /tmp/CORENAME); printf '%s' "$C" > /tmp/CORENAME       # the daemon sends its own picture again
        log "logo: the tty2oled daemon's picture for $C"
    fi
}

# --- the worker: does the newest request, then any that came in while it was busy ---------------------------
work() {
    while :; do
        W=$(cat "$S.want" 2>/dev/null)
        [ -n "$W" ] || break
        [ "$W" = "$(cat "$S.now" 2>/dev/null)" ] && break
        case "$W" in
            logo) do_logo ;;
            play\ *) do_play "${W#play }" ;;
        esac
        echo "$W" > "$S.now"
    done
}

ask() {
    echo "$1" > "$S.want"
    [ -c "$TTY" ] || exit 0                                    # no screen plugged in: nothing to do
    while :; do
        if mkdir "$S.lock" 2>/dev/null; then
            echo $$ > "$S.lock/pid"
            work
            rm -rf "$S.lock"
            # a request that came in just as the worker finished: do it now
            [ "$(cat "$S.want" 2>/dev/null)" = "$(cat "$S.now" 2>/dev/null)" ] && break
        else
            OWN=$(cat "$S.lock/pid" 2>/dev/null)
            if [ -n "$OWN" ] && [ ! -d "/proc/$OWN" ]; then rm -rf "$S.lock"; continue; fi   # a worker that died
            break                                              # the busy worker will pick this request up
        fi
    done
}

case "$1" in
    play) ask "play $2" ;;
    logo) ask "logo" ;;
    boot)
        if daemon_running; then
            echo logo > "$S.want"; echo logo > "$S.now"        # the daemon's Octophonic picture starts the logo
            log "boot: the tty2oled daemon shows the Octophonic logo"
        else
            rm -f "$S.now"; ask "logo"
        fi ;;
    info)
        echo "screen: $TTY $( [ -c "$TTY" ] && echo present || echo 'not there')"
        [ -c "$TTY" ] && echo "firmware: $(firmware)"
        echo "tty2oled daemon: $(daemon_running && echo running || echo 'not running')"
        echo "showing: $(cat "$S.now" 2>/dev/null)"
        ;;
    *) echo "oled.sh play FILE.oled | logo | boot | info"; exit 1 ;;
esac
exit 0
