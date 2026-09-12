"""Deterministic generator for original low-poly toon sailing assets.

Run with:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/create_assets.py

Creates original, procedurally modeled meshes (no imported art, no network,
no randomness) in a coherent warm saturated palette and exports one GLB per
asset into assets/models/ for Godot 4.  All materials are opaque Principled
BSDFs, all roots are neutral (identity transform, origin at ground base or
waterline), and geometry is authored in Blender Z-up with the bow toward
Blender +Y so the glTF exporter (+Y up conversion) yields Godot Y-up with the
bow toward -Z.

All assets are original and dedicated to the public domain (CC0).
"""

import math
import os

import bpy
import bmesh
from mathutils import Vector

SCRIPT_PATH = os.path.abspath(__file__)
ROOT = os.path.dirname(os.path.dirname(SCRIPT_PATH))
MODELS_DIR = os.path.join(ROOT, "assets", "models")
SOURCE_DIR = os.path.join(ROOT, "assets", "source")
BLEND_PATH = os.path.join(SOURCE_DIR, "archipelago_assets.blend")

# ---------------------------------------------------------------------------
# Palette: coherent warm saturated toon range.
# ---------------------------------------------------------------------------
PAL = {
    "sail_cream": (0.98, 0.93, 0.78),
    "cream": (0.95, 0.87, 0.68),
    "coral": (0.92, 0.34, 0.28),
    "coral_deep": (0.78, 0.24, 0.22),
    "teal": (0.09, 0.60, 0.58),
    "teal_deep": (0.06, 0.42, 0.42),
    "wood": (0.55, 0.34, 0.18),
    "wood_dark": (0.36, 0.22, 0.12),
    "wood_light": (0.72, 0.52, 0.30),
    "rope": (0.60, 0.50, 0.34),
    "sand": (0.90, 0.77, 0.52),
    "stone": (0.84, 0.71, 0.53),
    "stucco": (0.93, 0.86, 0.70),
    "frond": (0.24, 0.58, 0.25),
    "frond_dark": (0.15, 0.42, 0.20),
    "glow": (1.00, 0.78, 0.35),
}

_MATERIALS = {}


def mat(name, color, rough=0.75, metal=0.0):
    """Create (once) an opaque Principled BSDF material."""
    if name in _MATERIALS:
        return _MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    for extra in ("Alpha",):
        if extra in bsdf.inputs:
            bsdf.inputs[extra].default_value = 1.0
    for attr in ("blend_method", "shadow_method"):
        try:
            setattr(m, attr, "OPAQUE")
        except Exception:
            pass
    _MATERIALS[name] = m
    return m


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def asset_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def add_obj(name, verts, faces, material, col, smooth_faces=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    if smooth_faces is None:
        smooth_faces = [True] * len(faces) if False else None
    for i, p in enumerate(mesh.polygons):
        p.use_smooth = bool(smooth_faces[i]) if smooth_faces else False
    if material is not None:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


def box(name, center, size, material, col):
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    verts = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
             (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return add_obj(name, verts, faces, material, col)


def lathe(name, profile, material, col, segments=20, smooth=True, origin=(0.0, 0.0, 0.0)):
    """Revolve a (radius, z) profile around the Z axis."""
    rings = []
    for r, z in profile:
        ox, oy, oz = origin
        if r <= 1e-6:
            rings.append([(ox, oy, oz + z)])
        else:
            rings.append([
                (ox + r * math.cos(2 * math.pi * i / segments),
                 oy + r * math.sin(2 * math.pi * i / segments),
                 oz + z)
                for i in range(segments)
            ])
    verts, faces, side_start = [], [], None
    bases = []
    for ring in rings:
        bases.append(len(verts))
        verts.extend(ring)
    for i in range(len(rings) - 1):
        a, b = bases[i], bases[i + 1]
        na, nb = len(rings[i]), len(rings[i + 1])
        if na == 1 and nb == 1:
            continue
        if side_start is None:
            side_start = len(faces)
        if na == 1:
            for j in range(nb):
                faces.append([a, b + j, b + (j + 1) % nb])
        elif nb == 1:
            for j in range(na):
                faces.append([a + j, a + (j + 1) % na, b])
        else:
            for j in range(na):
                j2 = (j + 1) % na
                k = (j + 1) % nb
                faces.append([a + j, a + j2, b + k, b + j])
    smooth_faces = None
    if side_start is not None:
        smooth_faces = [False] * len(faces)
        for i in range(side_start, len(faces)):
            smooth_faces[i] = smooth
    obj = add_obj(name, verts, faces, material, col, smooth_faces=smooth_faces)
    # End caps as flat n-gons so tubes look closed.
    cap_faces = []
    verts = list(obj.data.vertices)
    if len(rings[0]) > 1:
        center = (origin[0], origin[1], profile[0][1] + origin[2])
        ci = len(obj.data.vertices)
        obj.data.vertices.add(1)
        obj.data.vertices[ci].co = center
        first = list(range(bases[0], bases[0] + len(rings[0])))
        cap_faces.append(first + [ci])
    if len(rings[-1]) > 1:
        center = (origin[0], origin[1], profile[-1][1] + origin[2])
        ci = len(obj.data.vertices)
        obj.data.vertices.add(1)
        obj.data.vertices[ci].co = center
        last = list(range(bases[-1], bases[-1] + len(rings[-1])))
        cap_faces.append(last + [ci])
    if cap_faces:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        for f in cap_faces:
            try:
                bm.faces.new([bm.verts[i] for i in f])
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
    return obj


def circle_profile(radius, segments):
    return [(radius * math.cos(2 * math.pi * i / segments),
             radius * math.sin(2 * math.pi * i / segments)) for i in range(segments)]


def rect_profile(width, height):
    hw, hh = width / 2.0, height / 2.0
    return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]


def sweep(name, path, profile2d, material, col, closed=False, smooth=True):
    """Sweep a 2D profile (normal-offset, binormal-offset) along a polyline."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    tangents = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        tangents.append(t.normalized())
    ref = Vector((0.0, 0.0, 1.0))
    if abs(tangents[0].dot(ref)) > 0.9:
        ref = Vector((1.0, 0.0, 0.0))
    prev_n = ref.cross(tangents[0]).normalized()
    verts, faces = [], []
    bases = []
    for i, p in enumerate(pts):
        t = tangents[i]
        if i > 0:
            prev_n = (prev_n - t * prev_n.dot(t))
            if prev_n.length < 1e-6:
                prev_n = ref.cross(t)
            prev_n = prev_n.normalized()
        b = t.cross(prev_n)
        bases.append(len(verts))
        verts.extend([tuple(p + prev_n * u + b * v) for u, v in profile2d])
    m = len(profile2d)
    last = n - 1 if closed else n - 2
    for i in range(last + 1):
        a = bases[i]
        b2 = bases[(i + 1) % n] if closed else bases[i + 1]
        for j in range(m):
            j2 = (j + 1) % m
            faces.append([a + j, a + j2, b2 + j2, b2 + j])
    if not closed and len(profile2d) > 2:
        faces.append(list(range(bases[0], bases[0] + m)))
        faces.append(list(range(bases[-1], bases[-1] + m)))
    return add_obj(name, verts, faces, material, col, smooth_faces=[smooth] * len(faces))


def tube(name, p0, p1, radius, material, col, segments=8):
    return sweep(name, [p0, p1], circle_profile(radius, segments), material, col)


def add_sway(obj, axis, amplitude, name, frames=48, keys=13):
    """Subtle looping rotation sway around a local axis; root stays neutral."""
    try:
        obj.animation_data_create()
        act = bpy.data.actions.new(name)
        fc = act.fcurves.new(data_path="rotation_euler", index=axis)
        for k in range(keys):
            frame = 1.0 + frames * k / (keys - 1)
            value = amplitude * math.sin(2 * math.pi * k / (keys - 1))
            fc.keyframe_points.insert((frame, value), options={"FAST"})
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        obj.animation_data.action = act
    except Exception as exc:  # animation is optional polish
        print("  [warn] sway animation skipped for %s: %s" % (obj.name, exc))


def finish_asset(col, objects, root_name):
    root = bpy.data.objects.new(root_name, None)
    col.objects.link(root)
    for obj in objects:
        # preserve intra-asset child hierarchies (e.g. emblem under sail);
        # only orphan top-level objects get the neutral root as parent
        if obj.parent is None or obj.parent not in objects:
            obj.parent = root
    return root


# ---------------------------------------------------------------------------
# Boat hull math (bow toward Blender +Y, stern -Y, waterline at z=0)
# ---------------------------------------------------------------------------

BOAT_L = 8.0
BOAT_HALF_BEAM = 1.75


def hull_params(u):
    """u in [0,1]: 0 = stern, 1 = bow. Returns (half_width, sheer_z, depth)."""
    if u <= 0.42:
        w = BOAT_HALF_BEAM * math.sqrt(max(0.0, 1.0 - ((0.42 - u) / 0.42) ** 2 * 0.30))
    else:
        w = BOAT_HALF_BEAM * math.sqrt(max(0.0, 1.0 - ((u - 0.42) / 0.58) ** 2))
    ztop = 0.90 + 0.70 * (2 * u - 1) ** 2 + 0.30 * (u - 0.5)
    uu = min(max(u, 0.02), 0.98)
    d = 1.90 * (0.62 + 0.38 * math.sin(math.pi * uu))
    return w, ztop, d


def hull_point(u, a):
    """Point on the molded hull surface. a in [0, pi]: 0 = port sheer, pi = starboard."""
    w, ztop, d = hull_params(u)
    y = -BOAT_L / 2.0 + BOAT_L * u
    x = -w * math.cos(a)
    z = ztop - d * (math.sin(a) ** 0.85)
    return Vector((x, y, z))


def hull_inward(p, u):
    w, ztop, d = hull_params(u)
    c = Vector((0.0, p.y, ztop - d * 0.45))
    return (c - p).normalized()


def deck_halfwidth(u, z):
    w, ztop, d = hull_params(u)
    if z >= ztop or d <= 1e-6:
        return 0.0
    s = min(max((ztop - z) / d, 0.0), 1.0) ** (1.0 / 0.85)
    return w * math.sqrt(max(0.0, 1.0 - s * s))


# ---------------------------------------------------------------------------
# Boat builder
# ---------------------------------------------------------------------------

SAIL_TACK = Vector((0.0, -0.52, 1.68))
SAIL_HEAD = Vector((0.0, -0.40, 8.25))
SAIL_CLEW = Vector((0.0, -3.42, 1.42))
SAIL_PIVOT = Vector((0.0, -0.50, 4.90))


def sail_point(t, s):
    luff = SAIL_TACK.lerp(SAIL_HEAD, t)
    # leech rises from CLEW (t=0) to HEAD (t=1) so the top edges converge
    leech = SAIL_CLEW.lerp(SAIL_HEAD, t)
    p = luff.lerp(leech, s)
    p.x += 0.42 * math.sin(math.pi * t) * math.sin(math.pi * s)
    return p


def _sail_basis(t0, s0, h=0.01):
    e_t = (sail_point(t0 + h, s0) - sail_point(t0 - h, s0)).normalized()
    e_s = (sail_point(t0, s0 + h) - sail_point(t0, s0 - h)).normalized()
    n = e_t.cross(e_s).normalized()
    return e_t, e_s, n


def _sail_patch_point(t0, s0, a, b, normal_off, e_t, e_s, n):
    """Map flat meters (a along chord, b along luff) onto the curved sail."""
    dt = b / max(e_t.length, 1e-6)
    ds = a / max(e_s.length, 1e-6)
    # local metric lengths per unit parameter
    len_t = (sail_point(t0 + 0.01, s0) - sail_point(t0 - 0.01, s0)).length / 0.02
    len_s = (sail_point(t0, s0 + 0.01) - sail_point(t0, s0 - 0.01)).length / 0.02
    p = sail_point(t0 + b / max(len_t, 1e-6), s0 + a / max(len_s, 1e-6))
    return p + n * normal_off


def build_sail_emblem(col, sail_obj):
    """Original teal emblem (sun ring, star, three chevrons) as real geometry."""
    e_t, e_s, n = _sail_basis(0.52, 0.5)
    verts, faces = [], []

    def emit_loop(loop, off0, off1):
        base0, base1 = len(verts), None
        for a, b in loop:
            verts.append(tuple(_sail_patch_point(0.52, 0.5, a, b, off0, e_t, e_s, n) - SAIL_PIVOT))
        base1 = len(verts)
        for a, b in loop:
            verts.append(tuple(_sail_patch_point(0.52, 0.5, a, b, off1, e_t, e_s, n) - SAIL_PIVOT))
        m = len(loop)
        faces.append(list(range(base0, base0 + m)))
        faces.append(list(range(base1, base1 + m)))

    def ring_loop(radius, seg):
        return [(radius * math.cos(2 * math.pi * i / seg),
                 radius * math.sin(2 * math.pi * i / seg)) for i in range(seg)]

    # Sun ring (annulus emitted as two loops at two offsets keeps it simple)
    emit_loop(ring_loop(0.54, 28), 0.030, 0.095)
    emit_loop(ring_loop(0.37, 24), 0.030, 0.095)
    # Four-point star inside the ring
    star = []
    for i in range(8):
        ang = math.pi / 2 + 2 * math.pi * i / 8
        r = 0.30 if i % 2 == 0 else 0.115
        star.append((r * math.cos(ang), r * math.sin(ang)))
    emit_loop(star, 0.030, 0.095)
    # Three chevron waves below the ring
    for c in (-0.78, -0.98, -1.18):
        upper = [(-0.55, c - 0.08), (-0.18, c + 0.10), (0.18, c - 0.08), (0.55, c + 0.10)]
        loop = upper + [(x, y - 0.10) for x, y in reversed(upper)]
        emit_loop(loop, 0.030, 0.095)

    emblem = add_obj("Boat_Sail_Emblem", verts, faces, mat("teal", PAL["teal"], 0.6), col)
    # verts are sail-local; keep parented to the sail so sway carries the emblem
    emblem.parent = sail_obj
    return emblem


def build_boat():
    col = asset_collection("ASSET_boat")
    m_coral = mat("coral", PAL["coral"], 0.55)
    m_coral_deep = mat("coral_deep", PAL["coral_deep"], 0.55)
    m_wood = mat("wood", PAL["wood"], 0.7)
    m_wood_dark = mat("wood_dark", PAL["wood_dark"], 0.75)
    m_wood_light = mat("wood_light", PAL["wood_light"], 0.65)
    m_rope = mat("rope", PAL["rope"], 0.85)
    m_sail = mat("sail_cream", PAL["sail_cream"], 0.8)
    objs = []

    # -- Curved hull built from six real plank bands ------------------------
    n_st, n_band = 17, 6
    u_samples = [i / (n_st - 1) for i in range(n_st)]
    verts, faces = [], []
    for k in range(n_band):
        a0 = math.pi * k / n_band + 0.02
        a1 = math.pi * (k + 1) / n_band - 0.02
        a_samples = [a0 + (a1 - a0) * j / 4 for j in range(5)]
        out_base = len(verts)
        for u in u_samples:
            for a in a_samples:
                verts.append(tuple(hull_point(u, a)))
        in_base = len(verts)
        for i, u in enumerate(u_samples):
            for a in a_samples:
                p = hull_point(u, a)
                verts.append(tuple(p + hull_inward(p, u) * 0.08))
        na = len(a_samples)
        for i in range(n_st - 1):
            for j in range(na - 1):
                o0 = out_base + i * na + j
                o1 = out_base + i * na + j + 1
                o2 = out_base + (i + 1) * na + j + 1
                o3 = out_base + (i + 1) * na + j
                faces.append([o0, o1, o2, o3])
                i0 = in_base + i * na + j
                i1 = in_base + i * na + j + 1
                i2 = in_base + (i + 1) * na + j + 1
                i3 = in_base + (i + 1) * na + j
                faces.append([i1, i0, i3, i2])
        for i in range(n_st - 1):
            for j in (0, na - 1):
                o0 = out_base + i * na + j
                o1 = out_base + (i + 1) * na + j
                i0 = in_base + i * na + j
                i1 = in_base + (i + 1) * na + j
                faces.append([o0, o1, i1, i0])
        for j in range(na - 1):
            for i in (0, n_st - 1):
                o0 = out_base + i * na + j
                o1 = out_base + i * na + j + 1
                i0 = in_base + i * na + j
                i1 = in_base + i * na + j + 1
                faces.append([o0, o1, i1, i0])
    objs.append(add_obj("Boat_Hull_Planks", verts, faces, m_wood, col))

    # -- Interior liner so plank gaps never reveal hollow geometry ----------
    verts, faces = [], []
    na = 17
    for i, u in enumerate(u_samples):
        for j in range(na):
            a = math.pi * j / (na - 1)
            p = hull_point(u, a)
            q = p + hull_inward(p, u) * 0.10
            if q.z > hull_point(u, 0.0).z - 0.02:
                q.z = hull_point(u, 0.0).z - 0.02
            verts.append(tuple(q))
    for i in range(n_st - 1):
        for j in range(na - 1):
            a0 = i * na + j
            a1 = i * na + j + 1
            a2 = (i + 1) * na + j + 1
            a3 = (i + 1) * na + j
            faces.append([a0, a1, a2, a3])
    objs.append(add_obj("Boat_Hull_Liner", verts, faces, m_wood_dark, col))

    # -- Transom ------------------------------------------------------------
    ring = [tuple(hull_point(0.0, math.pi * j / 8)) for j in range(9)]
    objs.append(add_obj("Boat_Transom", ring, [list(range(9))], m_wood_dark, col))

    # -- Deck with camber ---------------------------------------------------
    verts, faces = [], []
    nu, nf = 25, 9
    for i in range(nu):
        u = 0.03 + 0.94 * i / (nu - 1)
        for j in range(nf):
            f = -1.0 + 2.0 * j / (nf - 1)
            hw = deck_halfwidth(u, 0.56) * 0.995
            x = f * hw
            z = 0.46 + 0.10 * (1.0 - f * f)
            verts.append((x, -BOAT_L / 2.0 + BOAT_L * u, z))
    for i in range(nu - 1):
        for j in range(nf - 1):
            a0 = i * nf + j
            faces.append([a0, a0 + 1, a0 + nf + 1, a0 + nf])
    objs.append(add_obj("Boat_Deck", verts, faces, m_wood_light, col,
                        smooth_faces=[False] * len(faces)))

    # -- Coral gunwale rail + rub strakes -----------------------------------
    rail_path = []
    for i in range(n_st):
        p = hull_point(i / (n_st - 1), 0.0)
        rail_path.append(tuple(p + hull_inward(p, i / (n_st - 1)) * -0.045
                               + Vector((0, 0, 0.03))))
    rail_path.append((-hull_params(0.0)[0], -BOAT_L / 2.0, hull_params(0.0)[1] + 0.05))
    rail_path.append((0.0, -BOAT_L / 2.0 - 0.02, hull_params(0.0)[1] + 0.07))
    rail_path.append((hull_params(0.0)[0], -BOAT_L / 2.0, hull_params(0.0)[1] + 0.05))
    for i in range(n_st):
        u = i / (n_st - 1)
        p = hull_point(u, math.pi)
        rail_path.append(tuple(p + hull_inward(p, u) * -0.045 + Vector((0, 0, 0.03))))
    objs.append(sweep("Boat_Gunwale_Rail", rail_path, rect_profile(0.13, 0.10),
                      m_coral, col))

    for side, a_mid, mname in (("Port", 0.34, m_coral_deep),
                               ("Starboard", math.pi - 0.34, m_wood_dark)):
        path = []
        for i in range(n_st):
            u = i / (n_st - 1)
            p = hull_point(u, a_mid)
            path.append(tuple(p + (p - Vector((0, p.y, p.z))).normalized() * 0.025))
        objs.append(sweep("Boat_RubStrake_%s" % side, path, rect_profile(0.10, 0.06),
                          mname, col))

    # -- Deck furniture ------------------------------------------------------
    objs.append(box("Boat_Hatch", (0.0, -0.2, 0.62), (0.95, 0.75, 0.22), m_wood_dark, col))
    objs.append(box("Boat_Hatch_Lid", (0.0, -0.2, 0.76), (1.05, 0.85, 0.07), m_coral, col))
    hw1 = deck_halfwidth((1.3 + BOAT_L / 2) / BOAT_L, 0.62)
    hw2 = deck_halfwidth((-1.7 + BOAT_L / 2) / BOAT_L, 0.62)
    objs.append(box("Boat_Thwart_Fwd", (0.0, 1.3, 0.66), (2 * hw1 * 0.96, 0.34, 0.09),
                    m_wood, col))
    objs.append(box("Boat_Thwart_Aft", (0.0, -1.7, 0.64), (2 * hw2 * 0.96, 0.34, 0.09),
                    m_wood, col))

    # -- Spars ---------------------------------------------------------------
    objs.append(lathe("Boat_Mast",
                      [(0.085, 0.50), (0.098, 1.1), (0.075, 4.5), (0.055, 8.0),
                       (0.050, 8.30), (0.062, 8.36), (0.0, 8.45)],
                      m_wood_light, col, origin=(0.0, -0.40, 0.0)))
    objs.append(lathe("Boat_Mast_Boot", [(0.115, 0.45), (0.105, 0.55), (0.09, 1.0)],
                      m_coral, col, origin=(0.0, -0.40, 0.0)))
    objs.append(tube("Boom_Butt", (0.0, -0.45, 1.55), (0.0, -3.55, 1.32), 0.055,
                     m_wood_light, col))
    objs.append(lathe("Boom_End", [(0.0, 0.0), (0.07, -0.06), (0.06, -0.14)],
                      m_coral, col, origin=(0.0, -3.55, 1.32)))
    objs.append(tube("Boat_Bowsprit", (0.0, 3.75, 1.45), (0.0, 4.85, 2.30), 0.06,
                     m_wood, col))
    objs.append(lathe("Bowsprit_Tip", [(0.0, 0.0), (0.085, -0.07), (0.07, -0.16)],
                      m_coral, col, origin=(0.0, 4.85, 2.30)))

    # -- Rigging -------------------------------------------------------------
    rig = [(0.0, -0.40, 8.30), (0.0, 4.83, 2.28)]     # forestay
    rig2 = [(0.0, -0.40, 8.30), (0.0, -3.85, 1.30)]   # backstay
    rig3 = [(0.0, 4.83, 2.28), (0.0, 3.80, 1.42)]     # bobstay
    rig4 = [(0.0, -3.50, 1.34), (0.45, -2.85, 0.72)]  # sheet
    verts, faces = [], []
    for path in (rig, rig2, rig3, rig4):
        base = len(verts)
        p0, p1 = Vector(path[0]), Vector(path[1])
        d = (p1 - p0).normalized()
        ref = Vector((0, 0, 1))
        if abs(d.dot(ref)) > 0.9:
            ref = Vector((1, 0, 0))
        n = ref.cross(d).normalized()
        b = d.cross(n)
        prof = circle_profile(0.026, 6)
        for p in (p0, p1):
            for u, v in prof:
                verts.append(tuple(p + n * u + b * v))
        for j in range(6):
            faces.append([base + j, base + (j + 1) % 6, base + 6 + (j + 1) % 6,
                          base + 6 + j])
    objs.append(add_obj("Boat_Rigging", verts, faces, m_rope, col,
                        smooth_faces=[True] * len(faces)))

    # -- Rudder + tiller -----------------------------------------------------
    rverts = [
        (-0.30, -3.98, 0.85), (0.30, -3.98, 0.85),
        (0.24, -4.12, 0.85), (-0.24, -4.12, 0.85),
        (-0.22, -3.98, -0.95), (0.22, -3.98, -0.95),
        (0.18, -4.10, -0.88), (-0.18, -4.10, -0.88),
    ]
    rfaces = [(0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5),
              (0, 3, 2, 1), (4, 5, 6, 7)]
    objs.append(add_obj("Boat_Rudder", rverts, rfaces, m_wood_dark, col))
    objs.append(box("Boat_Rudder_Cap", (0.0, -4.05, 0.94), (0.62, 0.18, 0.10),
                    m_coral, col))
    objs.append(tube("Boat_Tiller", (0.0, -3.75, 1.00), (0.0, -2.55, 1.12), 0.035,
                     m_wood, col))

    # -- Curved cream sail with teal geometric emblem -------------------------
    verts, faces = [], []
    nt, ns = 13, 11
    for i in range(nt):
        t = i / (nt - 1)
        for j in range(ns):
            s = j / (ns - 1)
            verts.append(tuple(sail_point(t, s) - SAIL_PIVOT))
    for i in range(nt - 1):
        for j in range(ns - 1):
            a0 = i * ns + j
            faces.append([a0, a0 + 1, a0 + ns + 1, a0 + ns])
    sail = add_obj("Boat_Sail", verts, faces, m_sail, col,
                   smooth_faces=[True] * len(faces))
    sail.location = SAIL_PIVOT
    objs.append(sail)
    emblem = build_sail_emblem(col, sail)
    objs.append(emblem)
    add_sway(sail, 2, 0.035, "SailSway")

    # -- Pennant flag at masthead ---------------------------------------------
    fverts = [(0.0, -0.02, -0.28), (0.0, -0.02, 0.26), (0.0, -1.30, 0.04)]
    flag = add_obj("Boat_Flag", fverts, [(0, 1, 2), (2, 1, 0)], m_coral, col)
    flag.location = Vector((0.0, -0.40, 8.60))
    objs.append(flag)
    add_sway(flag, 2, 0.12, "FlagFlap", frames=36)

    root = finish_asset(col, objs, "Boat_Root")
    print("boat: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


# ---------------------------------------------------------------------------
# Palm (curved trunk, broad fanning fronds; ground base at z=0, Blender Z-up)
# ---------------------------------------------------------------------------

def build_palm():
    col = asset_collection("Palm")
    objs = []
    m_trunk = mat("Palm_Trunk", PAL["wood_light"], rough=0.85)
    m_trunk_rings = mat("Palm_Trunk_Rings", PAL["wood"], rough=0.85)
    m_frond = mat("Palm_Frond", PAL["frond"], rough=0.70)
    m_frond_dark = mat("Palm_Frond_Dark", PAL["frond_dark"], rough=0.70)
    m_coco = mat("Palm_Coconut", PAL["wood_dark"], rough=0.60)

    # Curved, segmented, tapering trunk via short tube runs between spine
    # stations (original leanutto spine: r = lean * (h/H)^1.9).
    H = 8.4
    BASE_R, TOP_R = 0.34, 0.16
    spine = []
    for i in range(11):
        s = i / 10.0
        spine.append(Vector((0.34 * s ** 1.9, 0.0, H * s)))
    for i in range(len(spine) - 1):
        a, b = spine[i], spine[i + 1]
        ra = BASE_R + (TOP_R - BASE_R) * (i / 10.0) ** 0.9
        rb = BASE_R + (TOP_R - BASE_R) * ((i + 1) / 10.0) ** 0.9
        seg = tube("Palm_Trunk_%02d" % i, tuple(a), tuple(b), ra, m_trunk, col, segments=9)
        # taper far end to rb while keeping the base ring planted at a
        d = (b - a)
        L = max(d.length, 1e-6)
        dn = d / L
        for v in seg.data.vertices:
            t = min(max(v.co.dot(dn) / L, 0.0), 1.0)
            v.co = a + (v.co - a) * (1.0 + (rb / ra - 1.0) * t)
        objs.append(seg)
        if 0 < i < len(spine) - 2:  # trunk ring bumps at segment joints
            ring = tube("Palm_Trunk_Ring_%02d" % i, tuple(a), tuple(a + Vector((0, 0, 0.07))),
                        ra * 1.16, m_trunk_rings, col, segments=9)
            objs.append(ring)
    top = spine[-1]

    # Broad individually modeled fronds: each is a curved spine sweep with a
    # pleated leaf blade built from quads along it; fans outward and droops.
    for k in range(9):
        yaw = 2 * math.pi * k / 9.0 + 0.22
        droop = 0.95 + 0.10 * math.sin(3.0 * k)
        m = m_frond_dark if k % 3 == 2 else m_frond
        tip = top + Vector((0.0, 0.0, 0.32))
        spine_pts, widths = [], []
        for i in range(7):
            s = i / 6.0
            r_out = 2.55 * s
            z = 0.55 * s - droop * (s ** 2.2)
            spine_pts.append(Vector((
                tip.x + r_out * math.cos(yaw),
                tip.y + r_out * math.sin(yaw),
                tip.z + z)))
            widths.append(0.10 + 0.62 * math.sin(math.pi * min(1.0, 0.18 + 0.9 * s)))
        prof = [(0.0, 0.0)] * 7  # placeholder replaced per-station below
        # hand-built blade: flat pleated ribbon with a midrib keel
        verts, faces = [], []
        for i, (p, w) in enumerate(zip(spine_pts, widths)):
            side = Vector((-math.sin(yaw), math.cos(yaw), 0.0))
            up = Vector((0.0, 0.0, 1.0))
            drop = Vector((0.0, 0.0, -0.10 * (i / 6.0)))
            verts.append(tuple(p + side * w + up * 0.055 + drop))
            verts.append(tuple(p + side * w * 0.34))
            verts.append(tuple(p - side * w * 0.34))
            verts.append(tuple(p - side * w + up * 0.055 + drop))
            verts.append(tuple(p + up * (0.10 if i else 0.0)))  # midrib keel
        for i in range(len(spine_pts) - 1):
            a, b = i * 5, (i + 1) * 5
            faces.append([a, a + 4, b + 4, b])           # right panel
            faces.append([a + 4, a + 1, b + 1, b + 4])   # right inner
            faces.append([a + 1, a + 2, b + 2, b + 1])   # midrib underside
            faces.append([a + 2, a + 4, b + 4, b + 2])   # left inner
            faces.append([a + 4, a + 3, b + 3, b + 4])   # left panel
        frond = add_obj("Palm_Frond_%02d" % k, verts, faces, m, col,
                        smooth_faces=[False] * len(faces))
        objs.append(frond)
        del prof

    # Coconuts tucked under the crown.
    for j, (dx, dy) in enumerate([(0.22, 0.10), (-0.20, 0.16), (0.02, -0.24)]):
        c = lathe("Palm_Coconut_%d" % j,
                  [(0.0, -0.16), (0.14, -0.11), (0.185, 0.0), (0.14, 0.11), (0.0, 0.16)],
                  m_coco, col, segments=8)
        c.location = top + Vector((dx, dy, -0.28))
        objs.append(c)

    root = finish_asset(col, objs, "Palm_Root")
    print("palm: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


# ---------------------------------------------------------------------------
# Rock (asymmetric faceted boulder; ground base at z=0)
# ---------------------------------------------------------------------------

def build_rock():
    col = asset_collection("Rock")
    objs = []
    m_rock = mat("Rock_Stone", (0.62, 0.58, 0.52), rough=0.9)
    m_moss = mat("Rock_Moss", PAL["frond_dark"], rough=0.85)

    # Irregular faceted boulder: hand-shaped vertex lattice (no primitive,
    # no noise operator) with an explicit flat-cut base.
    rings = [
        # (z, scale, per-vertex radial jitter factors around the ring)
        (0.00, 0.74, [1.00, 0.88, 0.94, 1.06, 0.90, 1.02, 0.96, 1.00]),
        (0.42, 1.00, [0.94, 1.08, 0.90, 1.00, 1.12, 0.86, 1.04, 0.92]),
        (0.86, 0.92, [1.06, 0.92, 1.10, 0.88, 1.00, 1.08, 0.90, 1.04]),
        (1.30, 0.62, [0.90, 1.04, 0.84, 1.10, 0.94, 1.00, 1.06, 0.88]),
        (1.62, 0.30, [1.00, 0.84, 1.08, 0.92, 1.04, 0.90, 1.00, 0.96]),
        (1.78, 0.00, None),
    ]
    R = 1.30
    verts, faces = [], []
    top_i = None
    for ri, (z, s, jit) in enumerate(rings):
        if jit is None:
            top_i = len(verts)
            verts.append((0.06, -0.10, z))  # off-center peak for asymmetry
            continue
        for j in range(8):
            a = 2 * math.pi * j / 8.0 + (0.25 if ri % 2 else 0.0)
            r = R * s * jit[j]
            verts.append((r * math.cos(a), r * math.sin(a) * 0.88, z))
    for ri in range(len(rings) - 2):
        a = ri * 8
        b = (ri + 1) * 8
        for j in range(8):
            j2 = (j + 1) % 8
            faces.append([a + j, a + j2, b + j2, b + j])
    for j in range(8):  # faceted crown cone
        j2 = (j + 1) % 8
        faces.append([32 + j2, 32 + j, top_i])
    faces.append(list(range(8)))  # flat cut base at z=0 (closed solid)
    rock = add_obj("Rock_Boulder", verts, faces, m_rock, col, smooth_faces=None)
    objs.append(rock)

    # Small companion stone so the prop reads as a cluster.
    small = box("Rock_Pebble", (1.35, 0.55, 0.22), (0.66, 0.52, 0.44), m_rock, col)
    small.rotation_euler = (0.0, 0.0, 0.6)
    objs.append(small)
    moss = box("Rock_Moss_Patch", (-0.30, -0.24, 0.66), (0.72, 0.55, 0.10), m_moss, col)
    moss.rotation_euler = (0.42, -0.30, 0.5)  # lies tangent on the slope
    objs.append(moss)

    root = finish_asset(col, objs, "Rock_Root")
    print("rock: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


# ---------------------------------------------------------------------------
# Buoy (striped float with cage lantern; waterline at z=0)
# ---------------------------------------------------------------------------

def build_buoy():
    col = asset_collection("Buoy")
    objs = []
    m_coral = mat("Buoy_Coral", PAL["coral"], rough=0.55)
    m_cream = mat("Buoy_Cream", PAL["cream"], rough=0.6)
    m_teal = mat("Buoy_Teal", PAL["teal"], rough=0.5)
    m_metal = mat("Buoy_Metal", PAL["wood_dark"], rough=0.4, metal=0.35)
    m_glow = mat("Buoy_Lantern_Glow", PAL["glow"], rough=0.35)

    # Shaped float: lathe profile with bulged body, tapering to a stern cone
    # that sits below the waterline for a moored look.
    body = lathe("Buoy_Body",
                 [(0.42, -0.30), (0.52, -0.24), (0.86, -0.02), (0.90, 0.28),
                  (0.80, 0.62), (0.55, 0.88), (0.30, 1.02), (0.30, 1.12)],
                 m_coral, col, segments=14)
    objs.append(body)
    stripe = lathe("Buoy_Stripe",
                   [(0.845, 0.30), (0.90, 0.42), (0.855, 0.56)],
                   m_cream, col, segments=14)
    objs.append(stripe)

    # Deck collar and lantern post.
    collar = lathe("Buoy_Collar",
                   [(0.36, 1.10), (0.36, 1.22), (0.24, 1.26), (0.0, 1.26)],
                   m_teal, col, segments=12)
    objs.append(collar)
    post = tube("Buoy_Post", (0.0, 0.0, 1.24), (0.0, 0.0, 2.02), 0.06, m_metal, col, segments=6)
    objs.append(post)

    # Modeled cage lantern: frame of vertical bars + top cap + glowing core.
    lz = 2.06
    for j in range(6):
        a = 2 * math.pi * j / 6.0
        bar = tube("Buoy_Lantern_Bar_%d" % j,
                   (0.16 * math.cos(a), 0.16 * math.sin(a), lz),
                   (0.11 * math.cos(a), 0.11 * math.sin(a), lz + 0.34),
                   0.022, m_metal, col, segments=5)
        objs.append(bar)
    cage = lathe("Buoy_Lantern_Cage",
                 [(0.17, lz), (0.17, lz + 0.02), (0.12, lz + 0.36), (0.02, lz + 0.42),
                  (0.0, lz + 0.42)],
                 m_metal, col, segments=10)
    objs.append(cage)
    core = lathe("Buoy_Lantern_Core",
                 [(0.0, lz + 0.05), (0.10, lz + 0.12), (0.10, lz + 0.28),
                  (0.0, lz + 0.34)],
                 m_glow, col, segments=8)
    objs.append(core)
    cap = lathe("Buoy_Lantern_Cap",
                [(0.0, lz + 0.40), (0.09, lz + 0.44), (0.13, lz + 0.50), (0.0, lz + 0.54)],
                m_coral, col, segments=8)
    objs.append(cap)

    # Mooring eyelet pad on the bow-side shoulder (flat ring, no object
    # rotation: the lathe bakes its origin into mesh space, and rotating the
    # object would sweep the ring through the waterline).
    ring = lathe("Buoy_Mooring_Ring",
                 [(0.14, 0.0), (0.14, 0.05), (0.06, 0.05), (0.06, 0.0)],
                 m_metal, col, segments=10, origin=(0.78, 0.0, 0.34))
    objs.append(ring)
    bolt = tube("Buoy_Mooring_Bolt", (0.78, 0.0, 0.30), (0.78, 0.0, 0.36),
                0.045, m_metal, col, segments=6)
    objs.append(bolt)

    root = finish_asset(col, objs, "Buoy_Root")
    print("buoy: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]



# ---------------------------------------------------------------------------
# Watchtower (~15 high warm sandstone, coral roof, lookout)
# ---------------------------------------------------------------------------

def build_watchtower():
    col = asset_collection("Watchtower")
    objs = []
    m_stone = mat("Tower_Stone", PAL["stone"], rough=0.85)
    m_sand = mat("Tower_Sand", PAL["sand"], rough=0.80)
    m_coral = mat("Tower_Coral", PAL["coral"], rough=0.55)
    m_wood = mat("Tower_Wood", PAL["wood"], rough=0.70)
    m_trim = mat("Tower_Trim", PAL["coral_deep"], rough=0.60)
    m_teal = mat("Tower_Teal", PAL["teal"], rough=0.55)

    objs.append(box("Tower_Plinth", (0.0, 0.0, 0.32), (4.6, 4.6, 0.64), m_sand, col))
    objs.append(box("Tower_Step", (0.0, 0.0, 0.78), (3.7, 3.7, 0.36), m_stone, col))
    objs.append(lathe("Tower_Shaft",
                      [(1.72, 0.96), (1.72, 1.20), (1.58, 6.2), (1.50, 11.15),
                       (1.50, 11.55)],
                      m_stone, col, segments=8, smooth=False))
    objs.append(lathe("Tower_Belt_Low",
                      [(1.80, 4.15), (1.80, 4.48), (1.60, 4.48)],
                      m_sand, col, segments=8, smooth=False))
    objs.append(lathe("Tower_Belt_High",
                      [(1.64, 9.25), (1.70, 9.58), (1.52, 9.58)],
                      m_sand, col, segments=8, smooth=False))
    objs.append(box("Tower_Door_Frame", (0.0, -1.78, 2.45), (1.16, 0.14, 2.50), m_trim, col))
    objs.append(box("Tower_Door", (0.0, -1.86, 2.35), (0.88, 0.10, 2.16), m_wood, col))
    objs.append(box("Tower_Slit_S", (0.0, -1.58, 5.55), (0.26, 0.16, 0.92), m_wood, col))
    objs.append(box("Tower_Slit_N", (0.0, 1.58, 7.70), (0.26, 0.16, 0.92), m_wood, col))
    objs.append(box("Tower_Slit_E", (1.58, 0.0, 6.55), (0.16, 0.26, 0.92), m_wood, col))
    objs.append(lathe("Tower_Deck",
                      [(2.18, 11.50), (2.18, 11.72), (1.38, 11.72)],
                      m_wood, col, segments=8, smooth=False))
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        x, y = 2.02 * math.cos(a), 2.02 * math.sin(a)
        objs.append(tube("Tower_RailPost_%d" % i,
                         (x, y, 11.72), (x, y, 12.52), 0.055, m_wood, col, segments=5))
    objs.append(lathe("Tower_Rail",
                      [(2.08, 12.46), (2.12, 12.60), (1.94, 12.60)],
                      m_coral, col, segments=8, smooth=False))
    objs.append(lathe("Tower_Cabin",
                      [(1.08, 11.72), (1.08, 13.35), (0.96, 13.52)],
                      m_stone, col, segments=8, smooth=False))
    objs.append(box("Tower_Lookout_Frame", (0.0, -1.10, 12.62), (0.82, 0.12, 0.78), m_wood, col))
    objs.append(box("Tower_Lookout_Pane", (0.0, -1.16, 12.62), (0.58, 0.08, 0.54), m_teal, col))
    objs.append(lathe("Tower_Roof",
                      [(1.58, 13.40), (1.74, 13.52), (1.18, 14.18),
                       (0.52, 14.72), (0.10, 14.96), (0.0, 14.96)],
                      m_coral, col, segments=8, smooth=False))
    objs.append(lathe("Tower_Finial",
                      [(0.0, 14.90), (0.11, 15.02), (0.05, 15.32), (0.0, 15.40)],
                      m_trim, col, segments=6))

    root = finish_asset(col, objs, "Watchtower_Root")
    print("watchtower: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


# ---------------------------------------------------------------------------
# Ruin arch (~10 high true open stepped sandstone)
# ---------------------------------------------------------------------------

def build_ruin_arch():
    col = asset_collection("RuinArch")
    objs = []
    m_sand = mat("Arch_Sand", PAL["sand"], rough=0.85)
    m_stone = mat("Arch_Stone", PAL["stone"], rough=0.80)
    m_moss = mat("Arch_Moss", PAL["frond_dark"], rough=0.75)
    m_coral = mat("Arch_Accent", PAL["coral_deep"], rough=0.70)

    objs.append(box("Arch_Plinth", (0.0, 0.0, 0.20), (7.4, 2.8, 0.40), m_sand, col))
    for side, sx in (("L", -2.45), ("R", 2.45)):
        objs.append(box("Arch_PierBase_%s" % side, (sx, 0.0, 0.85), (1.80, 2.05, 0.95), m_stone, col))
        objs.append(box("Arch_Pier_%s" % side, (sx, 0.0, 3.55), (1.38, 1.62, 4.45), m_sand, col))
        objs.append(box("Arch_PierCap_%s" % side, (sx, 0.0, 5.92), (1.62, 1.82, 0.32), m_stone, col))

    # True open semicircular arch in the XZ plane, extruded in Y.
    segs, y0, y1 = 12, -0.72, 0.72
    rin, rout, z0 = 1.62, 2.42, 5.76
    verts, faces = [], []

    def ring_pts(r, y):
        pts = []
        for i in range(segs + 1):
            ang = math.pi - math.pi * i / segs
            pts.append((r * math.cos(ang), y, z0 + r * math.sin(ang)))
        return pts

    inner_f, outer_f = ring_pts(rin, y0), ring_pts(rout, y0)
    inner_b, outer_b = ring_pts(rin, y1), ring_pts(rout, y1)
    for ring in (inner_f, outer_f, inner_b, outer_b):
        verts.extend(ring)
    n = segs + 1
    if0, of0, ib0, ob0 = 0, n, 2 * n, 3 * n
    for i in range(segs):
        faces.append([of0 + i, of0 + i + 1, if0 + i + 1, if0 + i])  # front
        faces.append([ib0 + i, ib0 + i + 1, ob0 + i + 1, ob0 + i])  # back
        faces.append([if0 + i, if0 + i + 1, ib0 + i + 1, ib0 + i])  # inner
        faces.append([ob0 + i, ob0 + i + 1, of0 + i + 1, of0 + i])  # outer
    faces.append([if0, of0, ob0, ib0])
    faces.append([if0 + segs, ib0 + segs, ob0 + segs, of0 + segs])
    objs.append(add_obj("Arch_Ring", verts, faces, m_sand, col))

    objs.append(box("Arch_Keystone", (0.0, 0.0, 8.28), (0.70, 1.70, 0.55), m_stone, col))
    objs.append(box("Arch_Attic", (0.0, 0.0, 8.85), (5.4, 1.85, 0.55), m_sand, col))
    objs.append(box("Arch_Cornice", (0.0, 0.0, 9.32), (5.9, 2.05, 0.28), m_stone, col))
    objs.append(box("Arch_Crest_L", (-1.55, 0.05, 9.72), (1.35, 1.40, 0.55), m_sand, col))
    objs.append(box("Arch_Crest_R", (1.70, -0.08, 9.68), (1.15, 1.25, 0.48), m_sand, col))
    objs.append(box("Arch_RuinBlock", (2.85, 0.55, 9.55), (0.70, 0.55, 0.42), m_stone, col))
    objs.append(box("Arch_Moss_L", (-2.55, 0.70, 2.4), (0.55, 0.22, 1.10), m_moss, col))
    objs.append(box("Arch_Moss_R", (2.40, -0.78, 4.8), (0.48, 0.20, 0.80), m_moss, col))
    objs.append(box("Arch_Inlay", (0.0, 0.82, 8.28), (0.42, 0.12, 0.42), m_coral, col))

    root = finish_asset(col, objs, "RuinArch_Root")
    print("ruin_arch: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


# ---------------------------------------------------------------------------
# House (~7 high cream stucco, coral pitched roof, wood door/windows)
# ---------------------------------------------------------------------------

def build_house():
    col = asset_collection("House")
    objs = []
    m_stucco = mat("House_Stucco", PAL["stucco"], rough=0.80)
    m_sand = mat("House_Sand", PAL["sand"], rough=0.80)
    m_coral = mat("House_Roof", PAL["coral"], rough=0.55)
    m_wood = mat("House_Wood", PAL["wood"], rough=0.70)
    m_wood_d = mat("House_WoodDark", PAL["wood_dark"], rough=0.70)
    m_teal = mat("House_Shutter", PAL["teal"], rough=0.60)
    m_cream = mat("House_Trim", PAL["cream"], rough=0.65)

    objs.append(box("House_Plinth", (0.0, 0.0, 0.16), (4.9, 6.0, 0.32), m_sand, col))
    objs.append(box("House_Body", (0.0, 0.0, 1.95), (4.4, 5.5, 3.50), m_stucco, col))

    z_eave, z_peak, half_w = 3.70, 6.95, 2.55
    rise, run = z_peak - z_eave, half_w
    slab_len = math.hypot(run, rise)
    ang = math.atan2(rise, run)
    mid_z = 0.5 * (z_eave + z_peak)
    # box() bakes center into mesh verts; rotate around object origin instead.
    # +Y rotation maps local +X toward -Z, so left needs -ang and right +ang.
    roof_l = box("House_Roof_L", (0.0, 0.0, 0.0), (slab_len, 6.2, 0.18), m_coral, col)
    roof_l.location = (-0.5 * run, 0.0, mid_z)
    roof_l.rotation_euler = (0.0, -ang, 0.0)
    objs.append(roof_l)
    roof_r = box("House_Roof_R", (0.0, 0.0, 0.0), (slab_len, 6.2, 0.18), m_coral, col)
    roof_r.location = (0.5 * run, 0.0, mid_z)
    roof_r.rotation_euler = (0.0, ang, 0.0)
    objs.append(roof_r)
    objs.append(box("House_Ridge", (0.0, 0.0, z_peak), (0.22, 6.25, 0.16), m_cream, col))

    def gable(name, y):
        t = 0.12
        verts = [
            (-half_w + 0.15, y - t, z_eave), (half_w - 0.15, y - t, z_eave),
            (0.0, y - t, z_peak - 0.06),
            (-half_w + 0.15, y + t, z_eave), (half_w - 0.15, y + t, z_eave),
            (0.0, y + t, z_peak - 0.06),
        ]
        faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
        return add_obj(name, verts, faces, m_stucco, col)

    objs.append(gable("House_Gable_S", -2.75))
    objs.append(gable("House_Gable_N", 2.75))

    objs.append(box("House_Chimney", (1.45, -1.55, 5.55), (0.58, 0.58, 1.70), m_sand, col))
    objs.append(box("House_Chimney_Cap", (1.45, -1.55, 6.48), (0.72, 0.72, 0.14), m_coral, col))

    objs.append(box("House_Door_Frame", (0.0, -2.80, 1.55), (1.18, 0.14, 2.45), m_wood, col))
    objs.append(box("House_Door", (0.0, -2.88, 1.50), (0.92, 0.10, 2.20), m_wood_d, col))
    objs.append(box("House_Door_Knob", (0.32, -2.96, 1.45), (0.08, 0.08, 0.08), m_cream, col))

    def window(tag, cx, cy, cz):
        objs.append(box("House_WinFrame_%s" % tag, (cx, cy, cz), (0.95, 0.12, 0.95), m_wood, col))
        objs.append(box("House_WinPane_%s" % tag, (cx, cy - 0.04 if cy < 0 else cy + 0.04, cz),
                        (0.68, 0.08, 0.68), m_teal, col))
        objs.append(box("House_ShutterL_%s" % tag, (cx - 0.62, cy, cz), (0.22, 0.08, 0.90), m_teal, col))
        objs.append(box("House_ShutterR_%s" % tag, (cx + 0.62, cy, cz), (0.22, 0.08, 0.90), m_teal, col))

    window("S1", -1.35, -2.78, 2.55)
    window("S2", 1.35, -2.78, 2.55)
    window("E", 2.22, 0.8, 2.45)

    objs.append(box("House_Steps", (0.0, -3.15, 0.22), (1.40, 0.70, 0.28), m_sand, col))

    root = finish_asset(col, objs, "House_Root")
    print("house: %d objects in collection %s" % (len(objs) + 1, col.name))
    return objs + [root]


ASSET_BUILDERS = {
    "boat": build_boat,
    "palm": build_palm,
    "rock": build_rock,
    "buoy": build_buoy,
    "watchtower": build_watchtower,
    "ruin_arch": build_ruin_arch,
    "house": build_house,
}


# ---------------------------------------------------------------------------
# Static-prop merge export (one combined mesh per material; boat is exempt)
# ---------------------------------------------------------------------------

def build_merged_meshes(name, objects, col):
    """Build one temporary combined mesh object per material from `objects`,
    baking each object's world transform into vertex positions and preserving
    polygon smooth flags. Originals stay untouched for the source .blend.
    Returns [neutral_root, temp1, temp2, ...]."""
    root = bpy.data.objects.new(name + "_MergeRoot", None)
    col.objects.link(root)
    # Fresh world matrices: rotation_euler/location edits after object
    # creation do not propagate to matrix_world until the depsgraph runs.
    dg = bpy.context.evaluated_depsgraph_get()
    bpy.context.view_layer.update()
    groups = {}
    for obj in objects:
        if obj.type != "MESH" or not obj.data.materials:
            continue
        m = obj.data.materials[0]
        groups.setdefault(m.name, (m, []))[1].append(obj)
    temps = []
    for mname in sorted(groups):
        m, members = groups[mname]
        verts, faces, smooth = [], [], []
        for obj in members:
            mw = obj.matrix_world
            base = len(verts)
            mesh = obj.data
            for v in mesh.vertices:
                verts.append(tuple(mw @ v.co))
            for poly in mesh.polygons:
                faces.append([mesh.loops[li].vertex_index + base
                              for li in range(poly.loop_start,
                                              poly.loop_start + poly.loop_total)])
                smooth.append(bool(poly.use_smooth))
        me = bpy.data.meshes.new("%s__%s" % (name, mname))
        me.from_pydata(verts, [], faces)
        me.validate(verbose=False, clean_customdata=False)
        me.materials.append(m)
        for i, f in enumerate(me.polygons):
            f.use_smooth = smooth[i]
        temp = bpy.data.objects.new("%s__%s" % (name, mname), me)
        col.objects.link(temp)
        temp.parent = root
        temps.append(temp)
    return [root] + temps


def export_asset(name, objects):
    """Export a GLB. Static props export one merged mesh per material (keeps
    Godot node counts low); the boat exports its full hierarchy because
    Boat_Sail / Boat_Sail_Emblem / Boat_Flag must stay named and separate."""
    if name == "boat":
        export_glb(name, objects)
        return
    col = objects[0].users_collection[0]
    temps = build_merged_meshes(name, objects, col)
    try:
        export_glb(name, temps)
    finally:
        for t in temps:
            me = t.data if t.type == "MESH" else None
            bpy.data.objects.remove(t)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)


def export_glb(name, objects):
    os.makedirs(MODELS_DIR, exist_ok=True)
    path = os.path.join(MODELS_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True,
                  export_apply=True, export_animations=True)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs = dict(filepath=path, export_format="GLB", use_selection=True)
        bpy.ops.export_scene.gltf(**kwargs)
    size = os.path.getsize(path)
    print("exported %s (%d bytes)" % (path, size))
    return path


def main():
    try:
        import io_scene_gltf2  # noqa: F401
    except Exception:
        try:
            bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
        except Exception as exc:
            print("[warn] glTF addon enable failed: %s" % exc)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 49
    for name, builder in ASSET_BUILDERS.items():
        print("building %s ..." % name)
        objects = builder()
        export_asset(name, objects)
    save_source_blend()
    print("done: %d asset(s)" % len(ASSET_BUILDERS))


def save_source_blend():
    """Write labeled seven-asset .blend after GLB export. .gdignore first.

    Originals stay overlapping at the origin during export so each GLB root
    is waterline/ground-neutral. After exports, offset only top-level *_Root
    empties onto a spaced XY display grid for a usable source file. Factory
    reset at the start of main() keeps offsets from accumulating.
    """
    os.makedirs(SOURCE_DIR, exist_ok=True)
    gdignore = os.path.join(SOURCE_DIR, ".gdignore")
    if not os.path.exists(gdignore):
        with open(gdignore, "w", encoding="utf-8") as fh:
            fh.write("# Keep Blender source out of the Godot importer.\n*\n")
    try:
        bpy.context.preferences.filepaths.save_version = 0
    except Exception:
        pass
    roots = [obj for obj in bpy.data.objects
             if obj.parent is None and obj.name.endswith("_Root")]
    roots.sort(key=lambda o: o.name)
    spacing = 18.0
    cols = 4
    for i, root in enumerate(roots):
        root.location = ((i % cols) * spacing, (i // cols) * spacing, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("saved source blend %s (%d roots laid out)" % (BLEND_PATH, len(roots)))


if __name__ == "__main__":
    main()
