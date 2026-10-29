"""Builds the two heroes in Blender (bpy module) and exports them as .glb.

Run:  <venv>/bin/python tools/make_characters.py
Every body part is its own object with the origin at its joint, so the game
can animate them procedurally (walk, ear flop, blink) without skeletons.
Colours live in vertex colours; the fur look comes from the shell shader in Godot.
Blender convention: character faces -Y, Z up (glTF export turns it into +Z forward, Y up).
"""
import math
import os
import random

import bpy  # noqa: I001  (must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector, noise

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "characters")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(c):
    """sRGB 0..1 to linear (vertex colours are stored linear)."""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def sphere(name, radius, scale=(1, 1, 1), segs=32, rings=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return new_obj(name, bm)


def cone(name, r1, r2, depth, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    return new_obj(name, bm)


def apply_mods(ob):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def subsurf(ob, levels=2):
    m = ob.modifiers.new("ss", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    apply_mods(ob)


def smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def sync():
    """Blender only recomputes matrix_world on a depsgraph update; without this,
    freshly set location/rotation would be ignored when baking geometry."""
    bpy.context.view_layer.update()


def join(objs, name):
    """Merges meshes (in world space) into the first object."""
    sync()
    base = objs[0]
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    bm = bmesh.new()
    for o in objs:
        bm.from_mesh(o.data)
    for o in objs[1:]:
        bpy.data.objects.remove(o)
    bm.to_mesh(base.data)
    bm.free()
    base.name = name
    base.data.name = name
    return base


def set_origin(ob, point):
    """Moves the object origin to `point` (world) keeping geometry in place."""
    sync()
    off = Vector(point) - ob.matrix_world.translation
    ob.data.transform(Matrix.Translation(-off))
    ob.matrix_world = Matrix.Translation(ob.matrix_world.translation + off)


def paint(ob, fn):
    """fn(world_pos, world_normal) -> rgb or rgba (sRGB). Alpha masks fur length
    (0 = bare skin) so fur does not grow over the eyes and mouth."""
    sync()
    me = ob.data
    if "Col" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Col"])
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    me.color_attributes.active_color = attr
    mw = ob.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            p = mw @ v.co
            n = (nm @ v.normal).normalized()
            out = fn(p, n)
            c = lin(out[:3])
            a = out[3] if len(out) > 3 else 1.0
            attr.data[li].color = (c[0], c[1], c[2], a)


def material(ob, name):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def parent(child, par):
    sync()
    mw = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = mw


def spot_field(seed, count, radius):
    rnd = random.Random(seed)
    return [(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized(),
             radius * rnd.uniform(0.7, 1.3)) for _ in range(count)]


def build(name, base, belly, dark, inner_ear, girl):
    """Builds one hero. Heights in metres; total ~0.42 m."""
    random.seed(name)
    H = {"hip": 0.075, "neck": 0.205, "head_c": 0.30}

    # ------------------------------------------------------------ body
    body = sphere("Body", 0.075, (1.0, 0.92, 1.25), 32, 20)
    body.location = (0, 0, 0.14)
    sm = body.modifiers.new("taper", "SIMPLE_DEFORM")
    sm.deform_method = "TAPER"
    sm.factor = -0.35
    sm.deform_axis = "Z"
    apply_mods(body)
    spots = spot_field(hash(name) % 1000, 9, 0.38)

    def body_col(p, n):
        local = (p - Vector((0, 0, 0.14)))
        front = max(0.0, -n.y) * max(0.0, 1.0 - abs(n.x) * 1.6)
        c = Vector(base).lerp(Vector(belly), min(1.0, max(0.0, (front - 0.35) * 2.6)))
        d = local.normalized()
        for sd, r in spots:
            if (d - sd).length < r and front < 0.4:
                c = c.lerp(Vector(dark), 0.75)
        return tuple(c)

    # ------------------------------------------------------------ legs
    legs = []
    for side in (-1, 1):
        leg = sphere(f"Leg_{'L' if side < 0 else 'R'}", 0.033, (1.0, 1.0, 1.4), 20, 14)
        leg.location = (side * 0.04, 0.0, 0.05)
        foot = sphere("foot", 0.034, (1.0, 1.35, 0.55), 20, 12)
        foot.location = (side * 0.042, -0.012, 0.016)
        toes = []
        for t in range(3):
            toe = sphere("toe", 0.011, (1, 1, 0.8), 12, 8)
            toe.location = (side * 0.042 + (t - 1) * 0.016, -0.052, 0.012)
            toes.append(toe)
        leg = join([leg, foot] + toes, leg.name)
        set_origin(leg, (side * 0.04, 0.0, H["hip"]))
        legs.append(leg)

    # ------------------------------------------------------------ arms
    arms = []
    for side in (-1, 1):
        arm = sphere(f"Arm_{'L' if side < 0 else 'R'}", 0.021, (1.0, 1.0, 2.1), 16, 12)
        arm.location = (side * 0.06, -0.035, 0.16)
        arm.rotation_euler = (math.radians(55), math.radians(side * 30), 0)
        hand = sphere("hand", 0.024, (1.1, 0.9, 0.95), 16, 12)
        hand.location = (side * 0.022, -0.075, 0.165)
        arm = join([arm, hand], arm.name)
        set_origin(arm, (side * 0.068, -0.005, 0.19))
        arms.append(arm)

    # ------------------------------------------------------------ tail
    tail = sphere("Tail", 0.022, (0.9, 0.9, 1.9), 16, 12)
    tail.location = (0, 0.07, 0.11)
    tail.rotation_euler = (math.radians(-50), 0, 0)
    bend = tail.modifiers.new("bend", "SIMPLE_DEFORM")
    bend.deform_method = "BEND"
    bend.angle = math.radians(60)
    bend.deform_axis = "X"
    apply_mods(tail)
    set_origin(tail, (0, 0.06, 0.1))

    # ------------------------------------------------------------ head
    head = sphere("Head", 0.115, (1.08, 0.95, 0.92), 40, 26)
    head.location = (0, 0, H["head_c"])
    # Cheeks / muzzle bulge.
    muzzle = sphere("muzzle", 0.038, (1.3, 0.62, 0.6), 24, 16)
    muzzle.location = (0, -0.085, H["head_c"] - 0.05)
    horns = []
    for side in (-1, 1):
        h = cone("horn", 0.022, 0.006, 0.05, 16)
        h.location = (side * 0.06, 0.01, H["head_c"] + 0.105)
        h.rotation_euler = (math.radians(-10), math.radians(side * 25), 0)
        horns.append(h)
    tuft = []
    for i in range(6 if not girl else 5):
        t = cone("tuft", 0.01, 0.0015, 0.045 + random.uniform(-0.01, 0.015), 8)
        t.location = (random.uniform(-0.02, 0.02), random.uniform(-0.02, 0.01), H["head_c"] + 0.1)
        t.rotation_euler = (math.radians(random.uniform(-30, 10)), math.radians(random.uniform(-35, 35)), 0)
        tuft.append(t)
    head = join([head, muzzle] + horns + tuft, "Head")
    smooth(head)
    set_origin(head, (0, 0, H["neck"]))

    def head_col(p, n):
        local = p - Vector((0, 0, H["head_c"]))
        c = Vector(base)
        # Lighter muzzle and cheeks.
        muz = Vector((local.x / 1.3, local.y + 0.085, local.z + 0.05))
        if muz.length < 0.04 and n.y < -0.3:
            c = c.lerp(Vector(belly), min(0.75, (0.04 - muz.length) * 35))
        # Brows: dark arcs above the eyes.
        for side in (-1, 1):
            b = Vector(((local.x - side * 0.056) * 0.55, local.y + 0.085, (local.z - 0.072) * 1.6))
            if b.length < 0.016 and n.y < -0.35:
                c = c.lerp(Vector(dark), 0.85)
        # Darker horn tips.
        if local.z > 0.115:
            c = c.lerp(Vector(dark), min(1.0, (local.z - 0.115) * 30))
        fur = 1.0
        for side in (-1, 1):
            d = (local - Vector((side * 0.05, -0.085, 0.016))).length
            fur = min(fur, max(0.0, min(1.0, (d - 0.043) / 0.012)))
        if muz.length < 0.04:
            fur = min(fur, 0.35 + muz.length * 10)
        return (c.x, c.y, c.z, fur)

    # ------------------------------------------------------------ ears (long, floppy)
    # Thin in X, wide in Y, long in Z; hanging down the sides of the head,
    # wider toward the tip, tips flared slightly outward.
    ears = []
    for side in (-1, 1):
        ear = sphere(f"Ear_{'L' if side < 0 else 'R'}", 0.05, (0.2, 0.62, 1.45), 24, 16)
        tp = ear.modifiers.new("taper", "SIMPLE_DEFORM")
        tp.deform_method = "TAPER"
        tp.factor = -0.45
        tp.deform_axis = "Z"
        apply_mods(ear)
        ear.location = (side * 0.128, 0.005, H["head_c"] - 0.045)
        ear.rotation_euler = (math.radians(6), -side * math.radians(16), 0)
        sync()
        ear.data.transform(ear.matrix_world)
        ear.matrix_world = Matrix.Identity(4)
        smooth(ear)
        set_origin(ear, (side * 0.105, 0.0, H["head_c"] + 0.035))
        ears.append(ear)

    def ear_col_for(side):
        def f(p, n):
            # Inner side faces the head (normal toward -x*side) and slightly forward.
            inner = (-n.x * side) * 0.8 + (-n.y) * 0.3
            return tuple(Vector(base).lerp(Vector(inner_ear), min(1.0, max(0.0, (inner - 0.25) * 2.2))))
        return f

    # ------------------------------------------------------------ eyes
    eyes = []
    for side in (-1, 1):
        e = sphere(f"Eye_{'L' if side < 0 else 'R'}", 0.041, (1.0, 0.82, 1.1), 32, 20)
        e.location = (side * 0.05, -0.085, H["head_c"] + 0.016)
        e.rotation_euler = (0, 0, math.radians(side * -14))
        eyes.append(e)

    # ------------------------------------------------------------ mouth (small smile)
    bm = bmesh.new()
    pts = []
    mc = Vector((0, -0.085, H["head_c"] - 0.05))
    mr = Vector((0.038 * 1.3, 0.038 * 0.62, 0.038 * 0.6))
    for i in range(13):
        t = i / 12.0
        x = (t - 0.5) * 0.042
        dz = -0.004 - 0.007 * math.sin(t * math.pi) + 0.006 * (abs(t - 0.5) * 2) ** 2
        k = max(0.0, 1.0 - (x / mr.x) ** 2 - (dz / mr.z) ** 2)
        y = mc.y - mr.y * math.sqrt(k) - 0.0008
        pts.append(Vector((x, y, mc.z + dz)))
    rings = []
    for i, p in enumerate(pts):
        r = 0.0022 * (0.6 + 0.4 * math.sin(i / 12.0 * math.pi))
        ring = []
        for k in range(6):
            a = k / 6.0 * math.tau
            ring.append(bm.verts.new(p + Vector((0, math.cos(a) * r, math.sin(a) * r))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(6):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % 6], rings[i + 1][(k + 1) % 6], rings[i + 1][k]))
    mouth = new_obj("Mouth", bm)

    extra = []
    if girl:
        # Eyelashes: three thin curved spikes above each eye.
        for side in (-1, 1):
            for k in range(3):
                la = cone("lash", 0.003, 0.0006, 0.016, 6)
                la.location = (side * (0.07 + k * 0.007), -0.096 + k * 0.006, H["head_c"] + 0.048 - k * 0.008)
                la.rotation_euler = (math.radians(-70), math.radians(side * (40 + k * 18)), 0)
                extra.append(la)
        lashes = join(extra, "Lashes")
        material(lashes, "mouth")
        paint(lashes, lambda p, n: (0.08, 0.04, 0.12))
        # Flower on the left ear root.
        petals = []
        fc = Vector((-0.09, -0.035, H["head_c"] + 0.075))
        for k in range(5):
            a = k / 5 * math.tau
            pe = sphere("petal", 0.017, (1.0, 0.5, 0.35), 12, 8)
            pe.location = fc + Vector((math.cos(a) * 0.017, -0.004, math.sin(a) * 0.017))
            pe.rotation_euler = (math.radians(90), 0, a)
            petals.append(pe)
        center = sphere("center", 0.006, (1, 0.6, 1), 10, 8)
        center.location = fc + Vector((0, -0.008, 0))
        flower = join(petals + [center], "Flower")
        smooth(flower)
        material(flower, "flower")
        paint(flower, lambda p, n: (0.98, 0.85, 0.3) if (p - (fc + Vector((0, -0.008, 0)))).length < 0.008 else (0.93, 0.38, 0.72))
        extra = [lashes, flower]

    # ------------------------------------------------------------ finish
    for ob in [body, head] + legs + arms + ears + [tail]:
        subsurf(ob, 1)
        smooth(ob)
    for ob in eyes:
        smooth(ob)
    smooth(mouth)
    paint(body, body_col)
    for ob in legs + arms + [tail]:
        paint(ob, lambda p, n: tuple(Vector(base).lerp(Vector(dark), 0.25 * max(0.0, noise.noise(p * 60.0)))))
    paint(head, head_col)
    for side, ear in zip((-1, 1), ears):
        paint(ear, ear_col_for(side))
    for ob in eyes:
        paint(ob, lambda p, n: (1, 1, 1))
    paint(mouth, lambda p, n: dark)

    for ob in [body, head] + legs + arms + [tail]:
        material(ob, "fur")
    for ob in ears:
        material(ob, "fur_ear")
    for ob in eyes:
        material(ob, "eye")
    material(mouth, "mouth")

    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    parent(body, root)
    for ob in legs + [tail]:
        parent(ob, body)
    for ob in arms:
        parent(ob, body)
    parent(head, body)
    for ob in ears + eyes + [mouth] + extra:
        parent(ob, head)
    if girl:
        parent(extra[1], head)
    return root


def export(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                              export_apply=True, export_vertex_color="ACTIVE", export_normals=True,
                              export_materials="PLACEHOLDER", export_yup=True)
    print("exported", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    reset()
    build("busik", base=(0.22, 0.42, 0.95), belly=(0.78, 0.84, 0.98), dark=(0.1, 0.2, 0.6),
          inner_ear=(0.62, 0.66, 0.95), girl=False)
    export("busik")
    reset()
    build("fialka", base=(0.6, 0.38, 0.88), belly=(0.86, 0.76, 0.96), dark=(0.38, 0.18, 0.6),
          inner_ear=(0.98, 0.7, 0.86), girl=True)
    export("fialka")
