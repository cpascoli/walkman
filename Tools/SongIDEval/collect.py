#!/usr/bin/env python3
"""Builds a labelled set: the top YouTube result for each query, with the song
YouTube credits in its Music section.

    ./collect.py sets/new.queries.txt sets/new.json

Each row gets `"expected": "TODO"`. Replace it by hand with
`{"artists": ["artist", "alternative spelling"], "track": "name|alternative"}`,
or `null` when the video isn't a single song.
"""
import json, sys, time, urllib.request

CTX = {"client": {"clientName": "WEB", "clientVersion": "2.20250101.00.00", "hl": "en", "gl": "US"}}

def post(endpoint, body):
    req = urllib.request.Request(
        f"https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false",
        data=json.dumps(dict(body, context=CTX)).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=20))

def text(node):
    if not isinstance(node, dict): return None
    if "simpleText" in node: return node["simpleText"]
    runs = node.get("runs")
    return "".join(r.get("text", "") for r in runs) if runs else None

def walk(o, key):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == key: yield v
            yield from walk(v, key)
    elif isinstance(o, list):
        for x in o: yield from walk(x, key)

def top_video(query):
    for v in walk(post("search", {"query": query, "params": "EgIQAQ%3D%3D"}), "videoRenderer"):
        return {"id": v["videoId"], "title": text(v.get("title")), "channel": text(v.get("ownerText")) or "",
                "duration": text(v.get("lengthText")) or ""}

def music_credit(video_id):
    for h in walk(post("next", {"videoId": video_id}), "horizontalCardListRenderer"):
        if h.get("header", {}).get("richListHeaderRenderer", {}).get("title", {}).get("simpleText") != "Music":
            continue
        for card in h.get("cards", []):
            vm = card.get("videoAttributeViewModel")
            if vm:
                return {"song": vm.get("title"), "artist": vm.get("subtitle"),
                        "album": (vm.get("secondarySubtitle") or {}).get("content")}

queries_path, out_path = sys.argv[1], sys.argv[2]
rows = []
for query in (line.strip() for line in open(queries_path) if line.strip()):
    video = top_video(query)
    video.update(query=query, music=music_credit(video["id"]), expected="TODO")
    rows.append(video)
    print(f"{query!r:44} -> {video['title']!r} [{video['channel']}] music={video['music']}")
    time.sleep(0.3)

json.dump(rows, open(out_path, "w"), indent=1, ensure_ascii=False)
print(f"{len(rows)} rows, {sum(1 for r in rows if r['music'])} with a Music credit -> {out_path}")
