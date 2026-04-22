#!/bin/bash
# Record the RViz2 window (running inside the apexnav container, displayed on
# the host via X11 forwarding) to an mp4 file. Run on the host, Ctrl+C to stop.
#
# Deps on host: ffmpeg xdotool  (sudo apt install ffmpeg xdotool)
# Usage:
#   bash docker/record_rviz.sh                      # auto-detect RViz window
#   bash docker/record_rviz.sh --pick               # click the window to record
#   bash docker/record_rviz.sh --full               # record whole screen
#   bash docker/record_rviz.sh --out my_demo.mp4    # custom output path
#   bash docker/record_rviz.sh --fps 60             # custom framerate
set -e

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# Default to docker/recordings (host-created, host-writable). The repo's videos/
# is owned by root inside the container, so the host user can't write there.
OUT_DIR="${REPO_DIR}/docker/recordings"
FPS=30
MODE=auto   # auto | pick | full
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --pick) MODE=pick; shift ;;
        --full) MODE=full; shift ;;
        --fps)  FPS="$2"; shift 2 ;;
        --out)  OUT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

for cmd in ffmpeg xdotool; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing '$cmd'. Install with: sudo apt install ffmpeg xdotool" >&2
        exit 1
    }
done

[ -n "${DISPLAY:-}" ] || { echo "DISPLAY is unset; run from a graphical session." >&2; exit 1; }
mkdir -p "$OUT_DIR"
[ -n "$OUT" ] || OUT="${OUT_DIR}/rviz_$(date +%Y%m%d_%H%M%S).mp4"

case "$MODE" in
    auto)
        # RViz spawns several windows sharing the 'rviz' string (Qt Selection Owner 3x3,
        # rviz2 1x1, and the real main window 'XYZ.rviz - RViz' at 1080+). Pick the
        # largest-area candidate so we ignore the utility windows.
        WID=""
        best_area=0
        for w in $(xdotool search --name 'RViz' 2>/dev/null); do
            eval "$(xdotool getwindowgeometry --shell "$w" 2>/dev/null)"
            area=$(( WIDTH * HEIGHT ))
            if [ "$area" -gt "$best_area" ]; then
                best_area=$area
                WID=$w
            fi
        done
        if [ -z "$WID" ] || [ "$best_area" -lt 10000 ]; then
            echo "No RViz main window found (only utility windows < 100x100 px)." >&2
            echo "Start RViz first, or rerun with --pick." >&2
            exit 1
        fi
        ;;
    pick)
        echo "Click the RViz window..."
        WID=$(xdotool selectwindow)
        ;;
    full)
        WID=""
        ;;
esac

if [ -n "$WID" ]; then
    # xdotool getwindowgeometry --shell outputs X= Y= WIDTH= HEIGHT=
    eval "$(xdotool getwindowgeometry --shell "$WID")"
    # Clamp to screen bounds: RViz sometimes reports a geometry that overflows.
    SCREEN=$(xdpyinfo | awk '/dimensions:/ {print $2; exit}')
    SCR_W=${SCREEN%x*}; SCR_H=${SCREEN#*x}
    [ "$X" -lt 0 ] && { WIDTH=$((WIDTH+X));  X=0; }
    [ "$Y" -lt 0 ] && { HEIGHT=$((HEIGHT+Y)); Y=0; }
    [ $((X + WIDTH))  -gt "$SCR_W" ] && WIDTH=$((SCR_W  - X))
    [ $((Y + HEIGHT)) -gt "$SCR_H" ] && HEIGHT=$((SCR_H - Y))
    # ffmpeg x11grab requires even width/height for yuv420p
    W=$(( WIDTH  - WIDTH  % 2 ))
    H=$(( HEIGHT - HEIGHT % 2 ))
    echo "Recording RViz window id=$WID @ ${W}x${H} +${X},${Y} (screen ${SCR_W}x${SCR_H})  →  $OUT"
    echo "Press Ctrl+C (or 'q' in this terminal) to stop."
    exec ffmpeg -hide_banner -loglevel warning -stats \
        -f x11grab -framerate "$FPS" -video_size "${W}x${H}" -i "${DISPLAY}+${X},${Y}" \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
        -movflags +faststart "$OUT"
else
    echo "Recording full screen  →  $OUT"
    echo "Press Ctrl+C (or 'q' in this terminal) to stop."
    # Fall back to xrandr-reported primary resolution
    RES=$(xrandr 2>/dev/null | awk '/ connected primary/ {print $4; exit}' | cut -d+ -f1)
    [ -n "$RES" ] || RES=$(xdpyinfo | awk '/dimensions:/ {print $2; exit}')
    exec ffmpeg -hide_banner -loglevel warning -stats \
        -f x11grab -framerate "$FPS" -video_size "$RES" -i "$DISPLAY" \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
        -movflags +faststart "$OUT"
fi
