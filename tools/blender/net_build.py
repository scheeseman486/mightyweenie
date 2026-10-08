"""Builds the goal nets (plan 17) in Blender: low-poly 3D models in the
original's colours, hand-made from numbers (no pixels traced or copied). Two
styles: ``standard`` and ``battle`` (the Battle Net: the standard net with
spikes).

Run from a live Blender session (its Python console)::

    exec(open("<repo>/tools/blender/net_build.py").read(),
         {"__name__": "__main__", "__file__": "<repo>/tools/blender/net_build.py",
          "STYLE": "battle"})

or in the background (``tools/bin/net3d-blender`` builds and exports both)::

    blender --background --python tools/blender/net_build.py -- --style battle

It (re)builds the style's scene (``MW_Net_Standard``, ``MW_Net_Battle``) with
the collection of the same name, and leaves every other scene alone.
``net_export.py`` saves it and exports the glTF.

Units and axes as the rink (``rink_build.py``): 1 rink px = 0.05 Blender
units; Blender X = rink x, Y = -rink y (north), Z = height. The model is the
far (top) net at its spot: the origin on the goal line's centre, on the ice;
the mouth faces south (-Y), the net reaches north (+Y). The game turns it
round for the near net.

Sizes (rink px) come from the original's two drawings of the net (front
``$3DAE6``, back ``$3DAC6``, read through its oblique projection map = (x, y
- z)) and the physics (``$1C74A``: the puck's centre stops at half width 28
and 16 px behind the goal line, a puck's radius outside the drawn net).

The frame is one closed mesh: two bars of one square section swept along
their paths with mitred bends (the top ring: crossbar and the frame round
the roof; the posts with the base frame on the ice), meeting flush in the
ring's front corners, united by an exact boolean. Its outline is the same
bars a little thicker, united the same way and turned inside out: one
piece, clear of the frame everywhere. The sides' and back's netting unwrap into one strip (UV = length
round the net at mid-height, height), so the stipple runs up the netting
and on unbroken round the corners.

Colours are the rink palette's line 0 indices the original's net uses (the
stadium's colours: a palette change recolours the net, as in 2D). Each
material's name carries them, the game reads it (``MwNet3D``):

    net_<line>_<outer>_<inner>   the netting: a 1 px stipple (every other px,
                                 checkered in UV px), its outer side in the
                                 outer colour (1 white), its inner side in the
                                 inner colour (8 dark grey)
    bar_<line>_<index>           the frame's faces by the way they face: up
                                 11, front / back 13, sides 12, down 10
    outline_<line>_<index>       the frame's outline (9): a shell 0.4 px
                                 bigger, faces turned inwards (drawn from
                                 behind only)
    spike_<line>_<index>         the Battle Net's spikes' faces by how they face
                                 a light from above: up 1, sideways 7, down 8
                                 (outlined like the frame, 0.7 px clear)
    hidden                       never drawn: the feet of the spikes on the
                                 netting, just inside it (it is see-through)
    shadow_<line>_<fill>         the ground shadow inside the net, on the ice
                                 (UV = x, d in px): the game draws the ROM's
                                 own shadow, the ice its front drawing shows
                                 through the mouth, and fills the sides the
                                 drawing hides behind the posts and netting
                                 with the fill colour (6)

The preview colours here are rough stand-ins; the game takes the stadium's.
"""
from __future__ import annotations

import math
import sys

import bmesh
import bpy
from mathutils import Vector

S = 0.05                       # metres per rink px
# The union's solver: Manifold (Blender 4.5+) keeps the result closed where
# the bars' faces lie flush on each other; Exact left a stray edge there.
BOOLEAN_SOLVER = "MANIFOLD"
STYLES = ("standard", "battle")
LINE = 0                       # the rink palette's line the net is drawn with

# --- sizes (rink px) -------------------------------------------------------
POST_X = 21.0                  # the posts' centres (front drawing: post columns at x -22..-20, 20..22)
BAR_Z = 20.0                   # the crossbar's and the top frame's centre height (crossbar rows y - z = -22..-20)
BAR_T = 1.6                    # every bar's square section: one for all, so where bars meet they are flush
OUTLINE = 0.4                  # the outline shell outside the frame
# The roof's outline at BAR_Z and the base frame's on the ice, (x, d) with d
# behind the goal line, from one post round the back to the other (same
# count: the netting's side and back panels join them point to point). The
# roof is narrower and shallower (the front drawing: its back edge x -14..13,
# 9 px back); the base follows the net's footprint the rink picture paints
# behind each goal line (x -24..23 from 2 px back, rounding in to -20..19 at
# 14 px; the front drawing's ground agrees, its back drawing is 3 px
# shallower). Both leave the posts straight back for a bar's width, so the
# frame's corners are square and its bars meet flush.
TOP = [(-21.0, 0.0), (-21.0, 1.6), (-20.2, 4.4), (-18.0, 6.6), (-14.5, 8.7),
       (14.5, 8.7), (18.0, 6.6), (20.2, 4.4), (21.0, 1.6), (21.0, 0.0)]
BASE = [(-21.0, 0.0), (-21.0, 1.6), (-24.4, 4.0), (-24.0, 11.5), (-20.0, 14.0),
        (20.0, 14.0), (24.0, 11.5), (24.4, 4.0), (21.0, 1.6), (21.0, 0.0)]
SHADOW_Z = 0.1                 # the shadow's height over the ice (no fighting with the floor)
NET_ROWS = 4                   # the sides' and back's netting in rows ...
NET_COLUMN = 8.0               # ... and columns at most this wide (px): smooth UVs on the slanted panels
# The Battle Net's spikes (the manual: "spikes and barbed wire hurt players
# nearby"), the left half's, mirrored for the right. Roots and directions
# solved from its two drawings (front `$1FC82`: screen (x, -d - z); back
# `$1FC68`: (x, d - z)): each spike's line in both, its angle in each view
# (a spike seen in only one: the other's angle as the drawings suggest;
# lengths where a drawing's edge cuts a spike short from the other). ("bar",
# root (x, d, z), direction, length, half width): rooted on the frame's
# centre line. ("net", segment, along, up, direction, length, half width):
# rooted on the netting - the panel between TOP / BASE points segment and
# segment + 1, that far along it and that high (0..1).
SPIKES = {"standard": [], "battle": [
    ("bar", (-12.5, 8.7, BAR_Z), (-0.7, 0.5, 0.5), 4.0, 0.8),          # the roof's back bar: up and back, out
    ("bar", (-5.0, 8.7, BAR_Z), (-0.4, 0.65, 0.65), 4.0, 0.8),         # (end on in the back drawing)
    ("bar", (-20.4, 3.8, BAR_Z), (-0.8, 0.31, 0.49), 11.0, 1.2),       # the roof's front corners: out and up
    ("net", 1, 0.33, 0.8, (-0.97, -0.15, 0.21), 11.0, 1.1),            # the side, high at the front: out, a little up
    ("net", 1, 0.56, 0.6, (-0.97, -0.02, -0.23), 11.0, 1.1),           # below it: out, a little down
    ("net", 3, 0.5, 0.68, (-0.94, 0.33, -0.02), 12.0, 1.1),            # the back corner, high: out and back
    ("net", 4, 0.11, 0.34, (-0.8, 0.6, 0.08), 8.0, 1.0),               # the back, low at the side: out and back
    ("net", 4, 0.36, 0.36, (-0.36, 0.93, -0.07), 7.0, 1.1),            # the back, low: back
    ("net", 4, 0.23, 0.79, (0.0, 0.71, 0.71), 3.5, 1.3),               # the back, high: back and up (end on in the back drawing)
]}
SPIKE_IN = 0.15                # a netting spike's foot this far inside the netting (px)
SPIKE_OUTLINE = 0.7            # the spikes' outline: wider than the bars' (0.4), so a thin spike's shows at 1 px

# --- colours (line 0 indices) ----------------------------------------------
NET_OUTER, NET_INNER = 1, 8
BAR_UP, BAR_FRONT, BAR_SIDE, BAR_DOWN = 11, 13, 12, 10
OUTLINE_INDEX = 9
SHADOW_FILL = 6
SPIKE_GREYS = (1, 7, 8)        # the spikes' greys, up / sideways / down (the drawings' 1 / 7 / 8, outlined darker)
HIDDEN = "hidden"              # faces never drawn: the netting spikes' feet
# rough preview stand-ins (sRGB, not the ROM's colours)
PREVIEW_SRGB = {1: (0.95, 0.95, 0.95), 8: (0.42, 0.42, 0.52), 9: (0.26, 0.26, 0.4),
           10: (0.12, 0.12, 0.24), 11: (1.0, 0.72, 0.95), 12: (0.84, 0.56, 0.84),
           13: (0.56, 0.42, 0.56), 6: (0.42, 0.55, 0.85), 7: (0.72, 0.72, 0.86)}


def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


PREVIEW = {i: tuple(_linear(c) for c in rgb) for i, rgb in PREVIEW_SRGB.items()}


def b(x: float, d: float, z: float) -> Vector:
    """Rink px (x, d behind the goal line, z) -> Blender."""
    return Vector((x * S, d * S, z * S))


# --- materials -------------------------------------------------------------
def _emission(mat: bpy.types.Material, rgb) -> tuple:
    if hasattr(mat, "use_nodes") and bpy.app.version < (6, 0, 0):
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return nt, out, em


def _socket(sockets, identifier: str):
    return next(x for x in sockets if x.identifier == identifier)


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if name == HIDDEN:
        if hasattr(mat, "use_nodes") and bpy.app.version < (6, 0, 0):
            mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        nt.links.new(tr.outputs["BSDF"], out.inputs["Surface"])
        mat.surface_render_method = "DITHERED"
        return mat
    kind, *nums = name.split("_")
    nums = [int(n) for n in nums]
    if kind == "net":
        nt, out, em = _emission(mat, PREVIEW[nums[1]])
        # outer / inner colour by the side seen
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        _socket(mix.inputs, "A_Color").default_value = (*PREVIEW[nums[1]], 1.0)
        _socket(mix.inputs, "B_Color").default_value = (*PREVIEW[nums[2]], 1.0)
        nt.links.new(geo.outputs["Backfacing"], _socket(mix.inputs, "Factor_Float"))
        nt.links.new(_socket(mix.outputs, "Result_Color"), em.inputs["Color"])
        # the stipple: (floor u + floor v) even, in UV px
        uv = nt.nodes.new("ShaderNodeUVMap")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(uv.outputs["UV"], sep.inputs["Vector"])
        fu = nt.nodes.new("ShaderNodeMath"); fu.operation = "FLOOR"
        fv = nt.nodes.new("ShaderNodeMath"); fv.operation = "FLOOR"
        nt.links.new(sep.outputs["X"], fu.inputs[0])
        nt.links.new(sep.outputs["Y"], fv.inputs[0])
        add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
        nt.links.new(fu.outputs[0], add.inputs[0])
        nt.links.new(fv.outputs[0], add.inputs[1])
        mod = nt.nodes.new("ShaderNodeMath"); mod.operation = "FLOORED_MODULO"
        mod.inputs[1].default_value = 2.0
        nt.links.new(add.outputs[0], mod.inputs[0])
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        ms = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(mod.outputs[0], ms.inputs["Fac"])      # 0: drawn, 1: a hole
        nt.links.new(em.outputs["Emission"], ms.inputs[1])
        nt.links.new(tr.outputs["BSDF"], ms.inputs[2])
        nt.links.new(ms.outputs["Shader"], out.inputs["Surface"])
        mat.use_backface_culling = False
        mat.surface_render_method = "DITHERED"
    else:
        _emission(mat, PREVIEW[nums[1]])
        mat.use_backface_culling = True             # as the game draws them
    mat.diffuse_color = (*PREVIEW[nums[-1] if kind != "net" else nums[1]], 1.0)
    return mat


# --- geometry --------------------------------------------------------------
class MeshBuilder:
    """Faces with their own corners (flat), materials by name and UVs."""

    def __init__(self):
        self.verts: list[Vector] = []
        self.faces: list[list[int]] = []
        self.mats: list[str] = []
        self.uvs: list[list[tuple[float, float]]] = []

    def face(self, pts: list[Vector], mat: str, uv=None) -> None:
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(list(range(base, base + len(pts))))
        self.mats.append(mat)
        self.uvs.append(uv or [(0.0, 0.0)] * len(pts))

    def object(self, name: str, col: bpy.types.Collection) -> bpy.types.Object:
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        names = list(dict.fromkeys(self.mats))
        for n in names:
            me.materials.append(material(n))
        uvl = me.uv_layers.new(name="UVMap")
        for poly, m, uv in zip(me.polygons, self.mats, self.uvs):
            poly.material_index = names.index(m)
            for li, t in zip(poly.loop_indices, uv):
                uvl.data[li].uv = t
        me.validate()
        me.update()
        return _link(name, me, col)


def _link(name: str, me: bpy.types.Mesh, col: bpy.types.Collection) -> bpy.types.Object:
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


# --- the frame: one mesh, one outline ---------------------------------------
def frame_paths() -> list:
    """The frame as two bent bars of one section: [(points in rink px,
    closed)]. The top ring (the crossbar and the frame round the roof, a
    closed loop at BAR_Z) and the posts with the base frame (down the left
    post, round the base on the ice, up the right post). The second ends in
    the ring's front corners, which it fills exactly: every face there is
    flush, so the frame has no step and its outline no seam."""
    ring = [(-POST_X, 0.0, BAR_Z), (POST_X, 0.0, BAR_Z)] + [(x, d, BAR_Z) for x, d in TOP[-2:0:-1]]
    h = BAR_T / 2                                    # the base frame's centre: on the ice
    u = ([(-POST_X, 0.0, BAR_Z), (-POST_X, 0.0, h)] + [(x, d, h) for x, d in BASE[1:-1]]
         + [(POST_X, 0.0, h), (POST_X, 0.0, BAR_Z)])
    return [(ring, True), (u, False)]


def sweep(path: list, t: float, closed: bool) -> bmesh.types.BMesh:
    """A square bar of section t along path (rink px) in Blender units. The
    section is carried along without twisting (parallel transport: each bend
    turns it as it turns the bar), its bends mitred (the corners meet on the
    plane halfway between the two directions); open ends capped."""
    bm = bmesh.new()
    pts = [Vector(p) for p in path]
    n = len(pts)
    nseg = n if closed else n - 1
    dirs = [(pts[(k + 1) % n] - pts[k]).normalized() for k in range(nseg)]
    v = Vector((0, 0, 1)) if abs(dirs[0].z) < 0.9 else Vector((0, 1, 0))
    u = dirs[0].cross(v).normalized()
    v = u.cross(dirs[0]).normalized()
    frames = [(u, v)]                                # the section's axes along each segment
    for k in range(1, nseg):
        q = dirs[k - 1].rotation_difference(dirs[k])
        frames.append((q @ frames[-1][0], q @ frames[-1][1]))
    h = t / 2
    rings = []
    for j in range(n):
        out = j if j < nseg else nseg - 1            # the segment leaving the point (the last: the one arriving)
        inn = (j - 1) % nseg if (closed or j > 0) else 0
        din, dout = dirs[inn], dirs[out]
        if not closed and j == n - 1:
            din = dout
        m = (din + dout).normalized()                # the mitre plane's normal
        fu, fv = frames[out]
        ring = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            c = fu * (sx * h) + fv * (sy * h)
            ring.append(bm.verts.new(b(*(pts[j] + c - dout * (c.dot(m) / dout.dot(m))))))
        rings.append(ring)
    for k in range(nseg):
        a, c = rings[k], rings[(k + 1) % n]
        for i in range(4):
            bm.faces.new((a[i], a[(i + 1) % 4], c[(i + 1) % 4], c[i]))
    if not closed:
        bm.faces.new(rings[0])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def spikes(style: str) -> list[Spike]:
    """The style's spikes, both halves (rink px)."""
    out = []
    for spec in SPIKES[style]:
        if spec[0] == "bar":
            _, root, a, length, w = spec
            root, a, plane = Vector(root), Vector(a).normalized(), None
        else:
            _, i, f, t, a, length, w = spec
            root, n = skirt_point(i, f, t)
            a = Vector(a).normalized()
            plane = (root.copy(), n)
        for m in (1.0, -1.0):
            def mirror(v: Vector) -> Vector:
                return Vector((v.x * m, v.y, v.z))
            out.append(Spike(mirror(root), mirror(a), length, w,
                             (mirror(plane[0]), mirror(plane[1])) if plane else None))
    return out


def skirt_point(i: int, f: float, t: float) -> tuple[Vector, Vector]:
    """The netting's point on the panel between TOP / BASE points i and i + 1,
    f along it and t up it (rink px), and the panel's outward normal there."""
    b0, b1 = Vector((*BASE[i], 0.0)), Vector((*BASE[i + 1], 0.0))
    t0, t1 = Vector((*TOP[i], BAR_Z)), Vector((*TOP[i + 1], BAR_Z))
    lo, hi = b0.lerp(b1, f), t0.lerp(t1, f)
    p = lo.lerp(hi, t)
    along = b1.lerp(t1, t) - b0.lerp(t0, t)
    n = along.cross(hi - lo).normalized()
    if n.dot(p - Vector((0.0, 7.0, p.z))) < 0:
        n = -n
    return p, n


def spike_frame(a: Vector) -> tuple[Vector, Vector]:
    """A spike's section axes (one level, one 'up' when it is not upright)."""
    s = a.cross(Vector((0, 0, 1))) if abs(a.z) < 0.95 else Vector((1, 0, 0))
    s.normalize()
    return s, s.cross(a).normalized()


class Spike:
    """A spike: a pyramid of square section (rink px), flat faces up, down and
    to the sides - from the game's camera, above and in front, it shows two
    of them, lit and shaded, which keeps it readable at 1 px. On a bar its
    foot is square across its root (on the bar's centre line); on the netting
    the pyramid is cut off by the netting's plane (plane: (point, outward
    normal)), SPIKE_IN inside it, so its foot is flush and never pokes
    through. That foot's face is HIDDEN: the netting is see-through."""

    def __init__(self, root: Vector, a: Vector, length: float, w: float, plane=None):
        self.root, self.a, self.length, self.w, self.plane = root, a, length, w, plane
        self.s, self.u = spike_frame(a)

    def _square(self, k: float, r: float) -> list[Vector]:
        c = self.root + self.a * k
        return [c + self.s * (sx * r) + self.u * (sy * r) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    def _foot(self, ring: list[Vector], top: list[Vector]) -> list[Vector]:
        """The foot's corners: ring, or on the netting each slid along its
        side edge (from top) onto the netting's plane, SPIKE_IN inside."""
        if not self.plane:
            return ring
        p0, n = self.plane
        p0 = p0 - n * SPIKE_IN
        return [t + (c - t) * ((p0 - t).dot(n) / (c - t).dot(n)) for c, t in zip(ring, top)]

    def faces(self) -> list[list[Vector]]:
        """Its faces (rink px): the foot first, then the sides."""
        tip = self.root + self.a * self.length
        foot = self._foot(self._square(0.0, self.w), [tip] * 4)
        return [foot] + [[foot[i], foot[(i + 1) % 4], tip] for i in range(4)]

    def outline_faces(self, g: float) -> list[list[Vector]]:
        """Its outline's faces (rink px, the foot first): g clear of it all
        along (a frustum from w + g at its root to g at its tip's level)
        and capped by a short point 1.5 g beyond the tip. A pyramid only
        grown would thin out to nothing along a thin spike."""
        top = self._square(self.length, g)
        apex = self.root + self.a * (self.length + 1.5 * g)
        foot = self._foot(self._square(0.0, self.w + g), top)
        return ([foot] + [[foot[i], foot[(i + 1) % 4], top[(i + 1) % 4], top[i]] for i in range(4)]
                + [[top[i], top[(i + 1) % 4], apex] for i in range(4)])


def solid(faces: list[list[Vector]]) -> tuple[bmesh.types.BMesh, list]:
    """A closed mesh (Blender units) of faces in rink px, its normals
    outward, and its faces' planes [(normal, point in rink px)] in order."""
    bm = bmesh.new()
    verts = {}
    for f in faces:
        vs = []
        for p in f:
            key = tuple(round(c, 5) for c in p)
            if key not in verts:
                verts[key] = bm.verts.new(b(*p))
            vs.append(verts[key])
        bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    return bm, [(f.normal.copy(), f.verts[0].co / S) for f in bm.faces]


def on_plane(c: Vector, n: Vector, planes: list):
    """The tag of the first of planes [(normal, point, tag)] a face (centre
    c in rink px, normal n) lies in, else None: after the union the spikes'
    faces are pieces of their own faces, in the same planes."""
    for pn, pp, tag in planes:
        if n.dot(pn) > 0.995 and abs((c - pp).dot(pn)) < 0.02:
            return tag
    return None


def spike_solids(style: str, outline: bool) -> tuple[list, list]:
    """The style's spikes (or their outlines) as closed meshes, and their
    faces' planes tagged "foot" (a netting spike's foot: HIDDEN) or
    "spike"."""
    shapes, planes = [], []
    for sp in spikes(style):
        bm, pl = solid(sp.outline_faces(SPIKE_OUTLINE) if outline else sp.faces())
        shapes.append(bm)
        planes += [(n, p, "foot" if k == 0 and sp.plane else "spike") for k, (n, p) in enumerate(pl)]
    return shapes, planes


def union(name: str, t: float, extra: list) -> bpy.types.Mesh:
    """The frame's bars at section t and extra closed meshes (the spikes)
    made one closed mesh (a boolean union), its flat faces merged."""
    shapes = [sweep(path, t, closed) for path, closed in frame_paths()] + extra
    parts = []
    for k, bm in enumerate(shapes):
        me = bpy.data.meshes.new("%s_part%d" % (name, k))
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)     # evaluated in the scene in context
        parts.append(ob)
    for other in parts[1:]:
        mod = parts[0].modifiers.new("union_" + other.name, "BOOLEAN")
        mod.operation = "UNION"
        mod.solver = BOOLEAN_SOLVER
        mod.object = other
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(parts[0].evaluated_get(dg))
    me.name = name
    for ob in parts:
        pm = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(pm)
    bpy.context.view_layer.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.001, verts=bm.verts, edges=bm.edges)
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    return me


def frame_mesh(style: str) -> bpy.types.Mesh:
    """The frame (and its spikes): one closed mesh, each face's material by
    the way it faces."""
    shapes, planes = spike_solids(style, False)
    me = union(style + "_frame", BAR_T, shapes)
    names = []
    for poly in me.polygons:
        n = Vector(poly.normal)
        tag = on_plane(Vector(poly.center) / S, n, planes)
        name = HIDDEN if tag == "foot" else _spike_material(n) if tag else _bar_material(n)
        if name not in names:
            names.append(name)
            me.materials.append(material(name))
        poly.material_index = names.index(name)
    me.update()
    return me


def outline_mesh(style: str) -> bpy.types.Mesh:
    """The frame's outline: the same bars OUTLINE thicker all round, made one
    mesh the same way (so it keeps OUTLINE clear of the frame everywhere,
    joins included) with the spikes' outlines, and turned inside out, so
    only its far side shows, round the edges."""
    shapes, planes = spike_solids(style, True)
    me = union(style + "_outline", BAR_T + 2 * OUTLINE, shapes)
    names = []
    for poly in me.polygons:
        tag = on_plane(Vector(poly.center) / S, Vector(poly.normal), planes)
        name = HIDDEN if tag == "foot" else "outline_%d_%d" % (LINE, OUTLINE_INDEX)
        if name not in names:
            names.append(name)
            me.materials.append(material(name))
        poly.material_index = names.index(name)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return me


def _spike_material(n: Vector) -> str:
    """A spike face's grey by how much it faces up (a light from above:
    the near net, the far one turned round, is lit the same): up 1, sideways
    7, down 8 - from the camera a spike shows its lit top and a side."""
    idx = SPIKE_GREYS[0] if n.z >= 0.45 else SPIKE_GREYS[1] if n.z >= -0.45 else SPIKE_GREYS[2]
    return "spike_%d_%d" % (LINE, idx)


def _bar_material(n: Vector) -> str:
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 2:
        idx = BAR_UP if n.z > 0 else BAR_DOWN
    elif ax == 1:
        idx = BAR_FRONT
    else:
        idx = BAR_SIDE
    return "bar_%d_%d" % (LINE, idx)


# --- the netting --------------------------------------------------------------
def skirt_columns() -> list[tuple[Vector, Vector]]:
    """The sides' and back's netting as columns from one post round the back
    to the other: [(point on the base, point on the roof's edge)] (rink px),
    each of TOP / BASE's segments cut into columns at most NET_COLUMN px
    wide (at mid-height)."""
    cols = []
    for i in range(len(TOP) - 1):
        b0 = Vector((*BASE[i], 0.0))
        b1 = Vector((*BASE[i + 1], 0.0))
        t0 = Vector((*TOP[i], BAR_Z))
        t1 = Vector((*TOP[i + 1], BAR_Z))
        mid = ((b1 + t1) - (b0 + t0)).length / 2
        n = max(1, math.ceil(mid / NET_COLUMN))
        for k in range(n + (1 if i == len(TOP) - 2 else 0)):
            f = k / n
            cols.append((b0.lerp(b1, f), t0.lerp(t1, f)))
    return cols


def column_u(cols: list[tuple[Vector, Vector]]) -> list[float]:
    """Each column's U: the length round the net at mid-height (px), 0 at the
    back's middle. A column keeps its U all the way up, so the stipple runs
    up the netting's lines and on unbroken round the corners (owner); it
    gathers a little towards the roof, which is shorter round than the base."""
    mids = [(bb + tt) / 2 for bb, tt in cols]
    s = [0.0]
    for i in range(len(mids) - 1):
        s.append(s[-1] + (mids[i + 1] - mids[i]).length)
    centre = s[-1] / 2                       # the net is symmetric: the back's middle
    return [x - centre for x in s]


def netting(mb: MeshBuilder) -> None:
    """The roof (UV = x, d in px) and the sides and back as one strip of
    NET_ROWS rows of columns (UV = the column's length round the net from
    the back's middle, the height), so the stipple is continuous across
    every edge of the strip."""
    mat = "net_%d_%d_%d" % (LINE, NET_OUTER, NET_INNER)
    inside = Vector((0.0, 6.0, BAR_Z / 2))
    roof = [(x, d, BAR_Z) for x, d in reversed(TOP)]           # its outer side up
    mb.face([b(*p) for p in roof], mat, [(p[0], p[1]) for p in roof])
    cols = skirt_columns()
    us = column_u(cols)
    for r in range(NET_ROWS):
        lo, hi = r / NET_ROWS, (r + 1) / NET_ROWS
        for k in range(len(cols) - 1):
            pts = [cols[k][0].lerp(cols[k][1], hi), cols[k + 1][0].lerp(cols[k + 1][1], hi),
                   cols[k + 1][0].lerp(cols[k + 1][1], lo), cols[k][0].lerp(cols[k][1], lo)]
            uv = [(us[k], pts[0].z), (us[k + 1], pts[1].z), (us[k + 1], pts[2].z), (us[k], pts[3].z)]
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            if n.dot(sum(pts, Vector()) / 4 - inside) < 0:       # outer side out
                pts.reverse()
                uv.reverse()
            mb.face([b(*p) for p in pts], mat, uv)


def shadow(mb: MeshBuilder) -> None:
    """The ground inside the net: the base's outline closed along the goal
    line, facing up, UV = (x, d) in px (the game maps the ROM's shadow on)."""
    pts = [(x, d, SHADOW_Z) for x, d in reversed(BASE)]
    mb.face([b(*p) for p in pts], "shadow_%d_%d" % (LINE, SHADOW_FILL), [(p[0], p[1]) for p in pts])


def scene_name(style: str) -> str:
    return "MW_Net_" + style.title()


def style_arg() -> str:
    """The style to build: STYLE (exec's globals) or --style after "--"."""
    style = globals().get("STYLE")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if style is None and "--style" in argv:
        style = argv[argv.index("--style") + 1]
    style = style or "standard"
    if style not in STYLES:
        raise ValueError("no net style %r (%s)" % (style, ", ".join(STYLES)))
    return style


def build(style: str = "standard") -> bpy.types.Collection:
    name = scene_name(style)
    sc = bpy.data.scenes.get(name) or bpy.data.scenes.new(name)
    if bpy.context.window is not None:
        bpy.context.window.scene = sc
    col = bpy.data.collections.get(name)
    if col is not None:
        for ob in list(col.objects):
            me = ob.data
            bpy.data.objects.remove(ob)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)
    else:
        col = bpy.data.collections.new(name)
    if col.name not in sc.collection.children:
        sc.collection.children.link(col)
    _link(style + "_frame", frame_mesh(style), col)
    _link(style + "_outline", outline_mesh(style), col)
    net, ground = MeshBuilder(), MeshBuilder()
    netting(net)
    shadow(ground)
    net.object(style + "_netting", col)
    ground.object(style + "_shadow", col)
    sc.view_settings.view_transform = "Standard"
    return col


if __name__ == "__main__":
    c = build(style_arg())
    print("built %s: %s" % (c.name, ", ".join("%s %d faces" % (o.name, len(o.data.polygons)) for o in c.objects)))
