"""Builds three parked car models (sedan, hatchback, crossover) as .glb.

Run:  <venv>/bin/python tools/make_cars.py
Body = side profile extruded across the width, bevelled and subdivided, with
wheel arches cut by booleans. Cabin glass is a narrower extruded profile.
Material names map to Godot materials in scripts/world/cars.gd:
paint (recoloured per car), glass, rubber, rim, trim, light_front, light_rear, plate.
Blender: +X forward, Z up (glTF: +X forward, Y up).
"""
import math
import os

import bpy  # noqa: I001  (must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "cars")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_bm(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def mat(ob, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    ob.data.materials.append(m)
    return len(ob.data.materials) - 1


def extrude_profile(name, pts, width):
    """pts: list of (x, z) counter-clockwise side profile. Extruded along Y (+-width/2)."""
    bm = bmesh.new()
    left = [bm.verts.new((x, -width / 2, z)) for x, z in pts]
    right = [bm.verts.new((x, width / 2, z)) for x, z in pts]
    bm.faces.new(left[::-1])
    bm.faces.new(right)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def cylinder(name, r, depth, segs=24, loc=(0, 0, 0), axis="Y"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=depth)
    ob = obj_from_bm(name, bm)
    if axis == "Y":
        ob.rotation_euler = (math.radians(90), 0, 0)
    ob.location = loc
    return ob


def box(name, size, loc):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = obj_from_bm(name, bm)
    ob.location = loc
    return ob


def bake(ob):
    # matrix_world is stale until the depsgraph updates after setting location.
    bpy.context.view_layer.update()
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)


def join(objs, name):
    for o in objs:
        bake(o)
    bm = bmesh.new()
    # Keep material slots: remap per object.
    target = bpy.data.meshes.new(name)
    slot_names = []
    for o in objs:
        for m in o.data.materials:
            if m.name not in slot_names:
                slot_names.append(m.name)
    for o in objs:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        remap = [slot_names.index(m.name) for m in o.data.materials]
        for f in tmp.faces:
            if remap:
                f.material_index = remap[f.material_index]
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    bm.to_mesh(target)
    bm.free()
    for nm in slot_names:
        target.materials.append(bpy.data.materials[nm])
    for o in objs:
        bpy.data.objects.remove(o)
    ob = bpy.data.objects.new(name, target)
    bpy.context.scene.collection.objects.link(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def build_car(name, length, width, body_pts, cabin_pts, wheel_x, wheel_r, clearance):
    """body_pts/cabin_pts in metres, x from rear (0) to front (length)."""
    body = extrude_profile("body", body_pts, width)
    bev = body.modifiers.new("bev", "BEVEL")
    bev.width = 0.06
    bev.segments = 4
    bev.limit_method = "ANGLE"
    apply_mods(body)
    # Wheel arches.
    for wx in wheel_x:
        cut = cylinder("cut", wheel_r + 0.05, width + 0.4, 32, (wx, 0, wheel_r))
        b = body.modifiers.new("arch", "BOOLEAN")
        b.operation = "DIFFERENCE"
        b.object = cut
        b.solver = "EXACT"
        apply_mods(body)
        bpy.data.objects.remove(cut)
    # The boolean leaves an empty material slot from the cutter: start clean.
    body.data.materials.clear()
    mat(body, "paint")

    cabin = extrude_profile("cabin", cabin_pts, width * 0.84)
    bev2 = cabin.modifiers.new("bev", "BEVEL")
    bev2.width = 0.05
    bev2.segments = 3
    bev2.limit_method = "ANGLE"
    apply_mods(cabin)
    # Roof/pillars painted, sides glass: assign by face normal.
    mat(cabin, "glass")
    mat(cabin, "paint")
    for p in cabin.data.polygons:
        p.material_index = 1 if p.normal.z > 0.75 else 0

    parts = [body, cabin]
    # Pillars between side windows (B-pillar) and black trim strip.
    mid_x = (cabin_pts[1][0] + cabin_pts[2][0]) * 0.5 if len(cabin_pts) > 3 else length * 0.5
    for side in (-1, 1):
        pil = box("pillar", (0.08, 0.02, 0.4), (mid_x, side * width * 0.425, cabin_pts[0][1] + 0.22))
        mat(pil, "trim")
        parts.append(pil)
        mirror = box("mirror", (0.12, 0.1, 0.08), (cabin_pts[-1][0] - 0.05, side * (width * 0.5 + 0.04), cabin_pts[0][1] + 0.04))
        mat(mirror, "paint")
        parts.append(mirror)
        handle = box("handle", (0.14, 0.012, 0.025), (mid_x + 0.25, side * width * 0.5, cabin_pts[0][1] - 0.1))
        mat(handle, "trim")
        parts.append(handle)

    # Lights, bumpers, plates.
    front_z = clearance + 0.38
    for side in (-1, 1):
        hl = box("hl", (0.04, 0.24, 0.12), (length + 0.005, side * width * 0.34, front_z + 0.12))
        mat(hl, "light_front")
        tl = box("tl", (0.04, 0.22, 0.12), (-0.005, side * width * 0.36, front_z + 0.16))
        mat(tl, "light_rear")
        parts += [hl, tl]
    for x, z in ((length + 0.03, clearance + 0.12), (-0.03, clearance + 0.12)):
        bump = box("bumper", (0.1, width * 0.98, 0.16), (x, 0, z))
        mat(bump, "trim")
        plate = box("plate", (0.02, 0.52, 0.11), (x + (0.06 if x > 0 else -0.06), 0, z + 0.03))
        mat(plate, "plate")
        parts += [bump, plate]
    grille = box("grille", (0.03, width * 0.4, 0.12), (length + 0.01, 0, front_z + 0.1))
    mat(grille, "trim")
    parts.append(grille)

    # Wheels: tyre + rim with spokes, each wheel its own object (origin at the
    # hub) so the game can spin them when the car drives.
    wheels = []
    for wx in wheel_x:
        for side in (-1, 1):
            parts_before = len(parts)
            y = side * (width * 0.5 - 0.11)
            tyre = cylinder("tyre", wheel_r, 0.2, 32, (wx, y, wheel_r))
            bv = tyre.modifiers.new("bev", "BEVEL")
            bv.width = 0.045
            bv.segments = 3
            apply_mods(tyre)
            mat(tyre, "rubber")
            rim = cylinder("rim", wheel_r * 0.62, 0.21, 24, (wx, y + side * 0.002, wheel_r))
            mat(rim, "rim")
            parts += [tyre, rim]
            for k in range(5):
                a = k / 5 * math.tau
                sp = box("spoke", (0.05, 0.02, wheel_r * 0.55), (wx, y + side * 0.108, wheel_r))
                sp.rotation_euler = (0, a, 0)
                mat(sp, "rim")
                parts.append(sp)
            nm = "Wheel_%s%s" % ("F" if wx > length / 2 else "R", "L" if side > 0 else "R")
            wheels.append((join(parts[parts_before:], nm), Vector((wx, y, wheel_r))))
            del parts[parts_before:]
    car = join(parts, name)
    # Centre the car on its footprint, origin on the ground.
    car.data.transform(Matrix.Translation((-length / 2, 0, 0)))
    for w, hub in wheels:
        w.data.transform(Matrix.Translation(-hub))
        w.location = hub - Vector((length / 2, 0, 0))
        w.parent = car
    return car


def export(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_materials="PLACEHOLDER", export_yup=True)
    print("exported", path, os.path.getsize(path))


CARS = {
    # Boxy Soviet-style sedan.
    "sedan": dict(length=4.12, width=1.62, wheel_x=(0.78, 3.2), wheel_r=0.3, clearance=0.18,
                  body_pts=[(0.0, 0.2), (4.12, 0.2), (4.12, 0.72), (3.1, 0.8), (1.0, 0.8), (0.0, 0.8)],
                  cabin_pts=[(1.05, 0.8), (2.95, 0.8), (2.5, 1.38), (1.4, 1.38)]),
    "hatch": dict(length=3.9, width=1.68, wheel_x=(0.68, 3.1), wheel_r=0.31, clearance=0.17,
                  body_pts=[(0.0, 0.2), (3.9, 0.2), (3.9, 0.66), (3.0, 0.82), (0.0, 0.86)],
                  cabin_pts=[(0.12, 0.84), (2.9, 0.82), (2.15, 1.42), (0.35, 1.42)]),
    "crossover": dict(length=4.5, width=1.84, wheel_x=(0.85, 3.55), wheel_r=0.36, clearance=0.22,
                      body_pts=[(0.0, 0.26), (4.5, 0.26), (4.5, 0.82), (3.45, 0.98), (0.0, 1.0)],
                      cabin_pts=[(0.15, 0.98), (3.35, 0.97), (2.45, 1.62), (0.35, 1.62)]),
}

if __name__ == "__main__":
    for nm, spec in CARS.items():
        reset()
        build_car(nm, **spec)
        export(nm)
