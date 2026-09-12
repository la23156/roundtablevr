"""Simplify materials so Blender's USD exporter can translate them faithfully:
walk each material's node graph, find the image texture feeding Base Color
(possibly through mix/multiply nodes), and rewire it DIRECTLY into the
Principled BSDF. Import in convert_avatar.py and call after glTF import.
"""
import bpy


def first_image_upstream(socket, depth=0):
    """DFS through links feeding `socket` for the first TEX_IMAGE node."""
    if depth > 6 or not socket.is_linked:
        return None
    for link in socket.links:
        node = link.from_node
        if node.type == "TEX_IMAGE" and node.image:
            return node
        for upstream in node.inputs:
            found = first_image_upstream(upstream, depth + 1)
            if found:
                return found
    return None


def flatten_all_materials():
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        tree = mat.node_tree
        bsdf = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        base = bsdf.inputs["Base Color"]
        image_node = first_image_upstream(base)
        if image_node is None:
            continue
        # Drop whatever chain was in between and connect the texture directly.
        for link in list(base.links):
            tree.links.remove(link)
        tree.links.new(image_node.outputs["Color"], base)
        # Metallic/roughness/specular chains (ORM splits etc.) translate badly
        # to UsdPreviewSurface and can render pure black — force sane scalars.
        for input_name, value in [("Metallic", 0.0), ("Roughness", 0.7), ("Specular IOR Level", 0.3)]:
            if input_name in bsdf.inputs:
                socket = bsdf.inputs[input_name]
                for link in list(socket.links):
                    tree.links.remove(link)
                socket.default_value = value
        # Emission strength 0 and un-linked oddities keep the export clean.
        if "Emission Strength" in bsdf.inputs and not bsdf.inputs["Emission Strength"].is_linked:
            bsdf.inputs["Emission Strength"].default_value = 0.0
        print(f"[flatten] {mat.name}: base color <- {image_node.image.name}")
