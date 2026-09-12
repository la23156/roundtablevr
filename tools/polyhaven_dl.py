#!/usr/bin/env python3
"""Download Poly Haven assets (CC0).

Usage:
  python3 tools/polyhaven_dl.py model <asset_id>      # glTF + textures -> assets/env/<id>/
  python3 tools/polyhaven_dl.py texture <asset_id>    # 2k diffuse/normal/rough jpg -> assets/textures/
  python3 tools/polyhaven_dl.py hdri <asset_id>       # 2k .hdr -> assets/env/
"""
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


UA = {"User-Agent": "roundtable-asset-fetch/1.0"}


def fetch_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"  {dest.relative_to(ROOT)} ({dest.stat().st_size // 1024} KB)", flush=True)


def main():
    kind, asset = sys.argv[1], sys.argv[2]
    files = fetch_json(f"https://api.polyhaven.com/files/{asset}")

    if kind == "model":
        entry = files["gltf"]["2k"]["gltf"]
        base = ROOT / "assets" / "env" / asset
        download(entry["url"], base / f"{asset}.gltf")
        for rel, info in entry.get("include", {}).items():
            download(info["url"], base / rel)
    elif kind == "texture":
        outdir = ROOT / "assets" / "textures"
        for key in files:
            k = key.lower()
            if k.startswith(("diffuse", "nor_gl", "rough", "arm")):
                try:
                    url = files[key]["2k"]["jpg"]["url"]
                except KeyError:
                    continue
                download(url, outdir / f"{asset}_{k.split('_')[0]}.jpg")
    elif kind == "hdri":
        url = files["hdri"]["2k"]["hdr"]["url"]
        download(url, ROOT / "assets" / "env" / f"{asset}_2k.hdr")


if __name__ == "__main__":
    main()
