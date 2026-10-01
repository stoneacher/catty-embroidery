# Shared helpers for capture.sh. Set SIM (simulator UDID) and OUT (output directory) first.
: "${SIM:?set SIM to the simulator UDID}" "${OUT:?set OUT to an output directory}"
ua() { npx -y xcodebuildmcp@latest ui-automation "$@" 2>&1; }
snap() { ua snapshot-ui --simulator-id "$SIM" --style minimal; }
ref() { snap | grep "$1" | head -1 | cut -d'|' -f1 | tr -d ' '; }
# `touch` with an explicit down/up rather than `tap`, which silently misses rows here.
press() {
    local r
    r=$(ref "$1")
    [ -z "$r" ] && { echo "no ref for $1"; return 1; }
    ua touch --simulator-id "$SIM" --element-ref "$r" --down --up --delay 0.15 >/dev/null
}
