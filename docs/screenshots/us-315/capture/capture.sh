# capture.sh <name>: with the stage open, the name field focused and the software keyboard up,
# records keyboard dismiss → focus → dismiss and extracts every frame to $OUT/<name>/.
# Needs `frames` built from frames.swift: swiftc -O frames.swift -o "$OUT/frames".
set -u
source "$(dirname "$0")/lib.sh"
name=$1
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
video=$!
sleep 2
press "|done|"; sleep 2
press "|text-field|Design name"; sleep 2
press "|done|"; sleep 2
kill -INT $video; sleep 1.5
"$OUT/frames" "$OUT/$name.mp4" "$OUT/$name" 0 30
