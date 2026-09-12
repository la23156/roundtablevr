#!/usr/bin/env python3
"""Inspect a GLB: meshes, morph target names, skeleton joints, animations."""
import json
import struct
import sys


def load_glb_json(path):
    with open(path, "rb") as f:
        magic, _version, _length = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit(f"{path}: not a GLB (LFS pointer or HTML?)")
        chunk_len, chunk_type = struct.unpack("<II", f.read(8))
        if chunk_type != 0x4E4F534A:
            raise SystemExit(f"{path}: first chunk is not JSON")
        return json.loads(f.read(chunk_len))


def main(path):
    g = load_glb_json(path)
    print(f"== {path}")
    print(f"generator: {g.get('asset', {}).get('generator')}")
    print(f"meshes: {len(g.get('meshes', []))}, nodes: {len(g.get('nodes', []))}, "
          f"skins: {len(g.get('skins', []))}, animations: {len(g.get('animations', []))}, "
          f"images: {len(g.get('images', []))}")
    for mesh in g.get("meshes", []):
        prim = mesh.get("primitives", [{}])[0]
        n_targets = len(prim.get("targets", []))
        names = mesh.get("extras", {}).get("targetNames", [])
        print(f"  mesh '{mesh.get('name')}': {n_targets} morph targets")
        if names:
            print(f"    names: {', '.join(names[:60])}{' …' if len(names) > 60 else ''}")
    if g.get("skins"):
        joints = g["skins"][0].get("joints", [])
        node_names = [g["nodes"][j].get("name", "?") for j in joints]
        print(f"  skin joints ({len(node_names)}): {', '.join(node_names[:12])} …")
        interesting = [n for n in node_names if any(k in n for k in ("Head", "Eye", "Jaw", "Neck"))]
        print(f"  head/eye joints: {', '.join(interesting)}")
    for anim in g.get("animations", []):
        print(f"  animation: '{anim.get('name')}' channels={len(anim.get('channels', []))}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
