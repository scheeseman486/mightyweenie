"""Saves a 3D net's Blender source and exports the game's glTF (plan 17).

Run after ``net_build.py`` for the same style (same session; live in a
Blender session or by ``tools/bin/net3d-blender``)::

    exec(open("<repo>/tools/blender/net_export.py").read(),
         {"__name__": "__main__", "__file__": "<repo>/tools/blender/net_export.py",
          "STYLE": "battle"})

    blender --background ... --python tools/blender/net_export.py -- --style battle

Writes, for the style's scene (``MW_Net_Standard``, ``MW_Net_Battle``),

* ``assets/blender/net_<style>.blend``: that scene alone (its collection and
  a preview camera; the rest of the session is not written), uncompressed;
* ``game/assets/rink3d/net_<style>.glb``: the collection's meshes
  (positions, normals, UV0, the materials by name), no images.

Nothing ROM-derived is in either: numbers and hand-made geometry only.
"""
from __future__ import annotations

import os
import sys

import bpy

STYLES = ("standard", "battle")


def style_arg() -> str:
    """The style to export: STYLE (exec's globals) or --style after "--"."""
    style = globals().get("STYLE")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if style is None and "--style" in argv:
        style = argv[argv.index("--style") + 1]
    style = style or "standard"
    if style not in STYLES:
        raise ValueError("no net style %r (%s)" % (style, ", ".join(STYLES)))
    return style


def repo_root() -> str:
    here = os.path.dirname(os.path.abspath(globals().get("__file__", os.getcwd())))
    return os.path.abspath(os.path.join(here, "..", ".."))


def preview_camera(sc: bpy.types.Scene, style: str) -> None:
    """Only the collection and a preview camera in the scene's own list."""
    for ob in list(sc.collection.objects):
        sc.collection.objects.unlink(ob)
    name = "MW_NetPreviewCamera_" + style
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        # in front of the mouth, a little to the right and above
        cam.location = (1.6, -3.4, 2.0)
        cam.rotation_euler = (1.08, 0.0, 0.44)
    sc.collection.objects.link(cam)
    sc.camera = cam


def save_blend(path: str, sc: bpy.types.Scene) -> None:
    if any(img.packed_file is not None for img in bpy.data.images):
        raise RuntimeError("packed images in the session: not writing")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.data.libraries.write(path, {sc}, path_remap="RELATIVE_ALL", compress=False)


def export_glb(path: str, sc: bpy.types.Scene) -> None:
    """Exports from the scene in context (Blender 5.2 crashes exporting under
    a context override): the net scene must be it (net_build.py makes it so)."""
    if bpy.context.window is not None:
        bpy.context.window.scene = sc
    if bpy.context.scene != sc:
        raise RuntimeError("the scene in context is %s, not %s" % (bpy.context.scene.name, sc.name))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    view = bpy.context.view_layer
    col = bpy.data.collections[sc.name]
    for o in view.objects:
        if o is not None:
            o.select_set(False)
    for o in col.all_objects:
        if o.type == "MESH":
            o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_image_format="NONE", export_materials="EXPORT",
        export_texcoords=True, export_normals=True, export_yup=True, export_apply=False,
        export_cameras=False, export_lights=False, export_extras=False)


def main() -> None:
    style = style_arg()
    name = "MW_Net_" + style.title()
    sc = bpy.data.scenes.get(name)
    if sc is None:
        raise RuntimeError("no %s scene: run tools/blender/net_build.py first" % name)
    root = repo_root()
    file = "net_" + style
    preview_camera(sc, style)
    save_blend(os.path.join(root, "assets", "blender", file + ".blend"), sc)
    export_glb(os.path.join(root, "game", "assets", "rink3d", file + ".glb"), sc)
    print("wrote assets/blender/%s.blend and game/assets/rink3d/%s.glb" % (file, file))


if __name__ == "__main__":
    main()
