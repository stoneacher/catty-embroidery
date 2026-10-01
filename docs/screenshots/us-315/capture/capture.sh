# capture.sh <name>: with the stage open, the name field focused and the software keyboard up,
# records keyboard dismiss → focus → dismiss and extracts every frame to $OUT/<name>/.
# Needs `frames` built from frames.swift: swiftc -O frames.swift -o "$OUT/frames".
set -u
source "$(dirname "$0")/lib.sh"
name=$1
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
video=$!
sleep 2
# A missed press aborts the capture: a recording without the transition it claims to show would
# extract cleanly and look like evidence.
abort() { echo "capture aborted: $1" >&2; kill -INT $video; wait $video; exit 1; }
press "|done|" || abort "no Done key (is the software keyboard up?)"; sleep 2
press "|text-field|Design name" || abort "no name field"; sleep 2
press "|done|" || abort "no Done key after refocus"; sleep 2
# Wait for the recorder to finalise the file, rather than guessing how long that takes.
kill -INT $video; wait $video
"$OUT/frames" "$OUT/$name.mp4" "$OUT/$name" 0 30
