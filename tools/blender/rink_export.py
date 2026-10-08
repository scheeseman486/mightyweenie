"""Saves the 3D rink's Blender source and exports the game's glTF (plan 14).

Run after ``rink_build.py`` in a session holding nothing else - normally through
``tools/bin/rink3d-blender``, which starts Blender in the background on an empty
file and runs both scripts::

    tools/bin/rink3d-blender            # -> assets/blender/rink.blend, game/assets/rink3d/rink.glb

To export after tweaking ``rink.blend`` by hand, open it and run this script
(Scripting tab, or ``blender --background assets/blender/rink.blend --python
tools/blender/rink_export.py``).

Writes

* ``assets/blender/rink.blend``: the session (the scene ``MW_Rink`` with the
  collection ``MW_Rink`` and a preview camera), uncompressed, without a
  thumbnail, images referenced by relative path only;
* ``game/assets/rink3d/rink.glb``: the collection's meshes (positions,
  normals, UV0, one material per object, names kept), **no images**.

Refuses to write if an image is packed: the ROM's pixels must never end up in
a committed file (docs/architecture.md, Assets).
"""
from __future__ import annotations

import os
import sys

import bpy

COLLECTION = "MW_Rink"
SCENE = "MW_Rink"


def repo_root() -> str:
    here = os.path.dirname(os.path.abspath(globals().get("__file__", os.getcwd())))
    return os.path.abspath(os.path.join(here, "..", ".."))


def check_no_packed_images() -> None:
    packed = [img.name for img in bpy.data.images if img.packed_file is not None]
    if packed:
        raise RuntimeError("packed images would go into the files: %s" % packed)


def source_scene(col: bpy.types.Collection) -> bpy.types.Scene:
    """A scene showing just the rink (+ a preview camera), for the .blend."""
    sc = bpy.data.scenes.get(SCENE)
    if sc is None:
        sc = bpy.context.scene
        sc.name = SCENE
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    cam = bpy.data.objects.get("MW_PreviewCamera")
    if cam is None:
        cam = bpy.data.objects.new("MW_PreviewCamera", bpy.data.cameras.new("MW_PreviewCamera"))
        # behind the near end, 45 deg down, the original's direction (looking north)
        cam.location = (0.0, -24.0, 17.0)
        cam.rotation_euler = (0.785398, 0.0, 0.0)
        cam.data.angle = 0.87
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    sc.camera = cam
    sc.view_settings.view_transform = "Standard"
    return sc


def save_blend(path: str, col: bpy.types.Collection) -> None:
    sc = source_scene(col)
    if bpy.context.window is not None:
        bpy.context.window.scene = sc
    bpy.context.preferences.filepaths.file_preview_type = "NONE"   # no thumbnail in the file
    bpy.context.preferences.filepaths.save_version = 0              # no .blend1 backup beside it
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=False, relative_remap=True, copy=True)


def export_glb(path: str, col: bpy.types.Collection) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    view = bpy.context.view_layer
    for o in view.objects:
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
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        raise RuntimeError("no %s collection: run tools/blender/rink_build.py first" % COLLECTION)
    check_no_packed_images()
    root = repo_root()
    save_blend(os.path.join(root, "assets", "blender", "rink.blend"), col)
    export_glb(os.path.join(root, "game", "assets", "rink3d", "rink.glb"), col)
    print("wrote assets/blender/rink.blend and game/assets/rink3d/rink.glb")


if __name__ == "__main__":
    main()
