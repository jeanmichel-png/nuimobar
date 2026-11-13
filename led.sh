#!/bin/zsh
# Draw on the Nuimo's 9x9 display through the running NuimoBar app.
# Usage: ./led.sh <81 cells, row by row, # or 1 = lit> [seconds] [brightness 0-1]
#        ./led.sh all [seconds]     light every LED
#        ./led.sh off               blank the display
#        ./led.sh flash [times]     flash every LED
#        ./led.sh emoji 🔥 [seconds] show an emoji (or any single character)
set -euo pipefail

send() {
    osascript -l JavaScript -e 'function run(a){ObjC.import("Foundation");$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("co.theforge.NuimoBar.led",a[0],$(),true)}' "$1" >/dev/null
}

ALL=$(printf '#%.0s' {1..81})
OFF=$(printf '.%.0s' {1..81})

case "${1:-}" in
    all) send "$ALL|${2:-2}|1" ;;
    off) send "$OFF|0.1|1" ;;
    flash)
        for i in {1..${2:-5}}; do
            send "$ALL|0.3|1"; /bin/sleep 0.3
            send "$OFF|0.1|1"; /bin/sleep 0.25
        done ;;
    emoji) send "emoji:${2:?emoji needed}|${3:-3}|1" ;;
    "") echo "usage: $0 <pattern>|all|off|flash [seconds|times] [brightness]"; exit 1 ;;
    *) send "$1|${2:-1.5}|${3:-1}" ;;
esac
