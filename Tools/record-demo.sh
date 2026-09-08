#!/usr/bin/env bash
# Regenerates Docs/demo.gif by driving the app through DemoWalkthrough while
# recording the simulator, then turning the capture into a GIF.
#
# Usage: Tools/record-demo.sh [simulator name]
#
# Env overrides:
#   SPEEDUP=2.5      playback rate of the finished GIF
#   FPS=8            frames per second in the GIF
#   WIDTH=280        GIF width in pixels
#   KEEP_CAPTURE=1   keep the .mov so it can be re-encoded without re-recording
set -euo pipefail

SIM="${1:-iPhone 17 Pro}"
SPEEDUP="${SPEEDUP:-2.5}"
FPS="${FPS:-8}"
WIDTH="${WIDTH:-280}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
if [ "${KEEP_CAPTURE:-0}" != "1" ]; then
  trap 'rm -rf "$WORK"' EXIT
fi

DEVICE=$(xcrun simctl list devices available \
  | grep "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$DEVICE" ] || { echo "No booted-capable simulator named '$SIM'"; exit 1; }
xcrun simctl boot "$DEVICE" 2>/dev/null || true

echo "Building…"
xcodebuild -project "$ROOT/Walkman.xcodeproj" -scheme Walkman-Demo \
  -destination "id=$DEVICE" -configuration Debug build-for-testing >/dev/null

echo "Recording…"
xcrun simctl io "$DEVICE" recordVideo --codec h264 -f "$WORK/demo.mov" &
REC=$!
sleep 2
xcodebuild test-without-building -project "$ROOT/Walkman.xcodeproj" -scheme Walkman-Demo \
  -destination "id=$DEVICE" -only-testing:WalkmanUITests/DemoWalkthrough \
  | grep -E "Test Case .*(passed|failed)" || true
sleep 1
kill -INT $REC 2>/dev/null || true
sleep 4

echo "Encoding…"
swift "$ROOT/Tools/extract-frames.swift" "$WORK/demo.mov" "$WORK/frames" "$FPS" "$SPEEDUP" "$WIDTH"
python3 "$ROOT/Tools/build-gif.py" "$WORK/frames" "$ROOT/Docs/demo.gif"
echo "Wrote Docs/demo.gif"
[ "${KEEP_CAPTURE:-0}" = "1" ] && echo "Capture kept at $WORK/demo.mov"
