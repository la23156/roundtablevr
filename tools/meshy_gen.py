#!/usr/bin/env python3
"""Generate a 3D model via Meshy text-to-3D (preview -> refine) and download
USDZ + GLB.

Usage: python3 tools/meshy_gen.py "<prompt>" <output_basename> [target_polycount]
Writes assets/env/<output_basename>.usdz (+ .glb) relative to repo root.
"""
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY = next(line.split("=", 1)[1].strip()
           for line in open(ROOT / "env.txt")
           if line.startswith("MESHY_API_KEY="))
BASE = "https://api.meshy.ai/openapi/v2/text-to-3d"


def call(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def poll(task_id):
    while True:
        task = call("GET", f"{BASE}/{task_id}")
        status = task["status"]
        print(f"  {task_id[:8]} {status} {task.get('progress', 0)}%", flush=True)
        if status in ("SUCCEEDED", "FAILED", "CANCELED"):
            return task
        time.sleep(15)


def main():
    prompt, name = sys.argv[1], sys.argv[2]
    polycount = int(sys.argv[3]) if len(sys.argv) > 3 else 30000
    outdir = ROOT / "assets" / "env"
    outdir.mkdir(parents=True, exist_ok=True)

    print(f"[meshy] preview: {name}", flush=True)
    preview = call("POST", BASE, {
        "mode": "preview",
        "prompt": prompt,
        "art_style": "realistic",
        "should_remesh": True,
        "target_polycount": polycount,
        "topology": "triangle",
    })
    preview_task = poll(preview["result"])
    if preview_task["status"] != "SUCCEEDED":
        sys.exit(f"preview failed: {preview_task}")

    print(f"[meshy] refine: {name}", flush=True)
    refine = call("POST", BASE, {
        "mode": "refine",
        "preview_task_id": preview_task["id"],
        "enable_pbr": True,
        "texture_resolution": "2k",
    })
    refine_task = poll(refine["result"])
    if refine_task["status"] != "SUCCEEDED":
        sys.exit(f"refine failed: {refine_task}")

    urls = refine_task["model_urls"]
    for fmt in ("usdz", "glb"):
        if fmt in urls and urls[fmt]:
            dest = outdir / f"{name}.{fmt}"
            urllib.request.urlretrieve(urls[fmt], dest)
            print(f"[meshy] wrote {dest} ({dest.stat().st_size} B)", flush=True)


if __name__ == "__main__":
    main()
