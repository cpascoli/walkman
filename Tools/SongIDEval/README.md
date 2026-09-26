# Song identification eval

Measures how well the app works out which song a YouTube video is — the step
that seeds a tape of similar tracks. 65 real search results, each labelled by
hand with its artist and track, or as not a single song.

| Set | Videos | Role |
|---|---|---|
| `tuning` | 30 | The rules were developed against these |
| `held-out` | 20 | Scored before its misses were looked at, then used for one round of fixes |
| `fresh` | 15 | Never tuned against — the honest number |

```sh
LASTFM_API_KEY=… Tools/SongIDEval/run.sh
```

It builds a small command-line tool from the app's own sources, so it scores
the real `SongIdentifier`. Add a strategy to `main.swift` to compare another
approach against it.

To grow a set, list queries one per line and collect their top results, then
label each row's `expected` by hand:

```sh
Tools/SongIDEval/collect.py sets/new.queries.txt sets/new.json
```

The sets are snapshots: the titles, durations and Music credits were recorded
when the set was collected. Last.fm's answers are live, so scores can drift.

## Results

Right / wrong / missed / false positive, where a false positive is a non-song
identified as one:

| | tuning | held-out | fresh | total |
|---|---|---|---|---|
| Title rules alone (before) | 15 / 7 / 0 / 8 | 8 / 7 / 0 / 5 | 7 / 5 / 0 / 3 | **30** / 19 / 0 / 16 |
| `SongIdentifier` | 29 / 1 / 0 / 0 | 18 / 0 / 2 / 0 | 13 / 1 / 1 / 0 | **60** / 2 / 3 / 0 |

What's left needs knowledge the video doesn't state — Zelda's composer, which
piece "Star Wars Main Theme" is, a Bollywood title that leads with the film.

### Apple's on-device model

`OnDeviceModel.swift` asks the Foundation Models framework to read the title,
channel, length and Music credit into `isSingleSong` / `artist` / `track`, and
checks its answer against Last.fm the same way. It runs automatically when
Apple Intelligence is on (macOS 26).

| | Right | Wrong | Missed | False positive |
|---|---|---|---|---|
| `SongIdentifier` | 60 | 2 | 3 | 0 |
| Model alone | 55 | 0 | 4 | 6 |
| `SongIdentifier`, then the model when it finds nothing | 60 | 2 | 2 | 1 |

As a fallback it breaks even: it finds "Star Wars Main Theme" (John Williams)
but invents a song for a sourdough tutorial. Alone, it misreads background-music
credits and makes songs up — David Bowie for a tiddlywinks video — and it picked
a different YOASOBI song from the one in the title. Without greedy sampling its
answers changed between runs. So the app doesn't use it. Calls took about a
second each once warm, several seconds when cold.

Two labels were widened after this run showed valid Last.fm names they didn't
accept ("Star Wars (Main Theme)", "Moonlight Sonata 3rd Movement"). Neither
changes `SongIdentifier`'s score.

`FULL_NAMES=1` prints each strategy's full Last.fm answer.
