#!/usr/bin/env python3
"""Generate an image via FAL (flux/schnell) and save it.

Usage: python3 tools/fal_gen.py "<prompt>" <out.png> [square_hd|landscape_16_9]
"""
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY = next(line.split("=", 1)[1].strip()
           for line in open(ROOT / "env.txt")
           if line.startswith("FAL_API_KEY="))


def main():
    prompt, out = sys.argv[1], pathlib.Path(sys.argv[2])
    size = sys.argv[3] if len(sys.argv) > 3 else "square_hd"

    req = urllib.request.Request(
        "https://fal.run/fal-ai/flux/schnell",
        data=json.dumps({
            "prompt": prompt,
            "image_size": size,
            "num_images": 1,
            "enable_safety_checker": True,
        }).encode(),
        headers={
            "Authorization": f"Key {KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
    url = result["images"][0]["url"]
    out.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, out)
    print(f"[fal] {out} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
