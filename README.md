# Walkman

A personal iOS video player that treats YouTube like a tape deck: paste a link,
play it, record it to the device, and file it onto your own tapes.

![Walkman walkthrough](Docs/demo.gif)

## What it does

- **Paste and play.** Accepts a bare video ID or any YouTube URL shape —
  `watch?v=`, `youtu.be`, `/shorts/`, `/embed/`, `/live/`, `youtube-nocookie`,
  with or without a scheme.
- **Plays in the background.** Audio keeps going when the app is backgrounded
  or the screen locks, with transport controls on the lock screen and in
  Control Center, plus Picture in Picture.
- **Records to the device.** A REC key saves a real `.mp4` you can play back
  with no network at all.
- **Tapes.** Named, ordered playlists. Reorder them, and play straight through
  with a two-second gap between tracks, wrapping at the end like a tape side.
- **A searchable catalogue** of everything you've played, with artwork.

## How it works

### Getting a playable stream

[`StreamResolver`](Walkman/Players/StreamResolver.swift) turns a video ID into a
set of qualities using [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit).

The wrinkle is that YouTube only publishes muxed (video **and** audio in one
file) streams up to **360p**. Everything above that is *adaptive*: separate
video-only and audio-only files. So for 480p–1080p the resolver loads both
tracks into an `AVMutableComposition`, which `AVPlayer` then streams as if it
were a single asset. Livestreams fall back to the HLS manifest, which `AVPlayer`
handles natively.

### Background playback

Three things have to line up: the `audio` background mode, an `AVAudioSession`
in the `.playback` category, and — the non-obvious one — detaching the player
from its layer on the way to the background.

iOS suspends video decoding when a layer is attached in a backgrounded app,
which stops the audio too.
[`VideoSurface`](Walkman/Players/VideoSurface.swift) drops the player from the
`AVPlayerViewController` when the app backgrounds and reattaches it on return.
Picture in Picture is the exception: while it's active the layer must stay put.

### Recording to the device

A download is produced by exporting the same composition the player uses,
through `AVAssetExportSession` in **passthrough** mode. That remuxes the
existing H.264 and AAC tracks into an MP4 container with no re-encoding, so a
1080p recording is fast and lossless rather than a 360p re-compression.

The presence of the file on disk is the only source of truth for "is this
recorded", so local copies survive clearing the catalogue.

A recording with a local copy is always played by `AVPlayer`, whatever the
Player setting says — the web view can neither reach the file nor keep playing
in the background.

### Running order

[`PlayQueue`](Walkman/Model/PlayQueue.swift) holds a **snapshot** of whatever
list you started playing from. It has to be a snapshot: playing a recording
bumps it to the top of the catalogue, so re-deriving the order after each track
would make the sequence eat itself and loop between two videos.

### Two players

The native path above is the default. An **Embedded** option still runs
YouTube's own IFrame player in a `WKWebView`, kept as a fallback for when
extraction breaks — YouTube changes its unofficial API from time to time. It
can't play in the background. There's also a remote-extraction fallback that
routes through YouTubeKit's server when local extraction fails.

## Building

Requires Xcode 26, iOS 17+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Walkman.xcodeproj
```

`project.yml` is the source of truth — the `.xcodeproj` is generated, so run
`xcodegen generate` after changing targets, files or settings. Set
`DEVELOPMENT_TEAM` in `project.yml` to your own team to run on a device.

## Tests

```sh
xcodebuild test -project Walkman.xcodeproj -scheme Walkman \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Unit tests cover URL parsing, queue rotation and wrap-around, and the tape
library. The UI tests are end-to-end against live YouTube — they stream a
video, record it, file it onto a tape, and check that continuous play advances
on its own. That makes them slower and occasionally flaky, which is the trade
for catching extraction breaking.

## Regenerating the demo

Run this **by hand**, and only when a change is worth showing — it is
deliberately not part of the build or test flow. Each recording commits a fresh
~3.5 MB binary, and the GIF stays accurate across most changes, so re-recording
routinely just grows the history for nothing.

```sh
Tools/record-demo.sh                          # defaults
SPEEDUP=2.5 FPS=8 WIDTH=280 KEEP_CAPTURE=1 \
  Tools/record-demo.sh                        # retune without re-recording
```

Drives the app through `DemoWalkthrough` while recording the simulator, then
builds `Docs/demo.gif`. `KEEP_CAPTURE=1` keeps the `.mov` so the encoding can be
adjusted without sitting through another capture.

The GIF is kept small by sharing one palette across frames so only changes are
stored, and by skipping dithering. The seeded accent colours in
`Tools/build-gif.py` exist because median cut otherwise spends the entire
palette on dark greys and renders the amber as brown.

The app icon is generated too, by `Tools/make-icon.swift`.

## Caveats

This is a personal project, not something to ship.

- Downloading YouTube videos conflicts with YouTube's Terms of Service.
- *Walkman* is a Sony trademark. Fine for an app on your own phone; not a name
  you could publish under.
- Extraction depends on YouTube's unofficial API and will break when they
  change it. The remote fallback buys time; updating YouTubeKit is the fix.
