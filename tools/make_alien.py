"""Builds the alien (a tall, thin visitor in a long dark coat) as a .glb.

Run:  <venv>/bin/python tools/make_alien.py
Same conventions as make_characters.py: one object per body part with its
origin at the joint (Body at the hips, Head at the neck, Arm_* at the
shoulders, Leg_* at the hips), character faces -Y in Blender, Z up.
Materials: skin, coat, eye.
"""
import math
import os

import bpy  # noqa: F401,I001  (must be imported before bmesh/mathutils)
from mathutils import Quaternion, Vector

from make_characters import (apply_mods, cone, join, material, paint, parent, reset, set_origin,
                             smooth, sphere, subsurf)

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "characters")

SKIN = (0.56, 0.63, 0.55)
SKIN_DARK = (0.36, 0.42, 0.37)
COAT = (0.12, 0.12, 0.13)
HIP = 0.92
NECK = 1.5


def limb(name, a, b, r0, r1):
    """Tapered capsule from a to b."""
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    ob = cone(name, r0, r1, length, 16)
    ob.location = (a + b) / 2
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    return ob


def build():
    # ------------------------------------------------------------ legs (trousers + shoes)
    legs = []
    for side in (-1, 1):
        x = side * 0.1
        thigh = limb("thigh", (x, 0, HIP), (x * 0.9, 0, 0.48), 0.065, 0.05)
        knee = sphere("knee", 0.05, (1, 1, 1), 12, 8)
        knee.location = (x * 0.9, 0, 0.48)
        shin = limb("shin", (x * 0.9, 0, 0.48), (x * 0.85, 0, 0.08), 0.048, 0.036)
        shoe = sphere("shoe", 0.05, (0.9, 2.1, 0.62), 16, 10)
        shoe.location = (x * 0.85, -0.05, 0.036)
        leg = join([thigh, knee, shin, shoe], f"Leg_{'L' if side < 0 else 'R'}")
        set_origin(leg, (x, 0, HIP))
        legs.append(leg)

    # ------------------------------------------------------------ body: long straight coat with shoulders
    coat = cone("coat", 0.25, 0.19, 0.98, 32)
    coat.location = (0, 0.01, 0.95)
    shoulders = sphere("shoulders", 0.21, (1.0, 0.58, 0.42), 24, 14)
    shoulders.location = (0, 0.01, 1.42)
    hem = cone("hem", 0.255, 0.25, 0.03, 32)
    hem.location = (0, 0.01, 0.47)
    collar = cone("collar", 0.11, 0.07, 0.13, 20)
    collar.location = (0, 0, 1.5)
    neck = limb("neck", (0, 0, 1.45), (0, 0, NECK + 0.06), 0.035, 0.03)
    body = join([coat, shoulders, hem, collar, neck], "Body")
    smooth(body)
    set_origin(body, (0, 0, HIP))

    # ------------------------------------------------------------ arms: too long, three long fingers
    arms = []
    for side in (-1, 1):
        sx = side * 0.22
        shoulder = sphere("shoulder", 0.055, (1, 1, 1), 12, 8)
        shoulder.location = (sx, 0, 1.42)
        upper = limb("upper", (sx, 0, 1.42), (sx * 1.12, 0.02, 1.06), 0.05, 0.04)
        elbow = sphere("elbow", 0.04, (1, 1, 1), 12, 8)
        elbow.location = (sx * 1.12, 0.02, 1.06)
        fore = limb("fore", (sx * 1.12, 0.02, 1.06), (sx * 1.16, -0.02, 0.72), 0.04, 0.028)
        hand = sphere("hand", 0.035, (1.0, 0.7, 1.2), 12, 8)
        hand.location = (sx * 1.16, -0.02, 0.69)
        fingers = []
        for k in range(3):
            f = limb("finger", (sx * 1.16 + (k - 1) * 0.015, -0.02, 0.67), (sx * 1.16 + (k - 1) * 0.025, -0.03, 0.55),
                     0.008, 0.004)
            fingers.append(f)
        arm = join([shoulder, upper, elbow, fore, hand] + fingers, f"Arm_{'L' if side < 0 else 'R'}")
        set_origin(arm, (sx, 0, 1.42))
        arms.append(arm)

    # ------------------------------------------------------------ head: big cranium, narrow chin
    head = sphere("Head", 0.14, (0.95, 0.95, 1.08), 40, 28)
    head.location = (0, 0, NECK + 0.2)
    sd = head.modifiers.new("taper", "SIMPLE_DEFORM")
    sd.deform_method = "TAPER"
    sd.factor = 0.55
    sd.deform_axis = "Z"
    apply_mods(head)
    head.location = (0, 0, NECK + 0.2)
    smooth(head)
    set_origin(head, (0, 0, NECK))

    # Eyes: big glossy almond lenses lying on the face, slanted, wrapping
    # slightly around the sides of the head.
    eyes = []
    hc = Vector((0, 0, NECK + 0.2))
    for side in (-1, 1):
        d = Vector((side * 0.5, -0.86, -0.06)).normalized()
        e = sphere(f"Eye_{'L' if side < 0 else 'R'}", 0.05, (1.0, 0.36, 0.56), 28, 16)
        q = Vector((0, -1, 0)).rotation_difference(d)
        roll = Quaternion(d, math.radians(side * -24))
        e.rotation_mode = "QUATERNION"
        e.rotation_quaternion = roll @ q
        e.location = hc + Vector((d.x * 0.128, d.y * 0.128, d.z * 0.14))
        eyes.append(e)
    for ob in eyes:
        smooth(ob)

    # Small face details: two nostril pits and a thin lipless mouth.
    face = []
    for side in (-1, 1):
        n = sphere("nostril", 0.004, (1.0, 0.6, 1.6), 8, 6)
        n.location = hc + Vector((side * 0.009, -0.125, -0.06))
        face.append(n)
    mouth = sphere("mouth", 0.016, (1.0, 0.25, 0.12), 12, 6)
    mouth.location = hc + Vector((0, -0.112, -0.105))
    face.append(mouth)
    face_parts = join(face, "Face")
    material(face_parts, "eye")

    # Coat details: buttons down the front, a belt.
    deco = []
    for k in range(4):
        b = sphere("button", 0.012, (1, 0.5, 1), 8, 6)
        b.location = (0.0, -0.205 - k * 0.006, 1.32 - k * 0.17)
        deco.append(b)
    belt = cone("belt", 0.232, 0.229, 0.05, 32)
    belt.location = (0, 0.01, 1.02)
    deco.append(belt)
    coat_deco = join(deco, "CoatDeco")
    material(coat_deco, "eye")
    parent(coat_deco, body)

    for ob in legs + [body] + arms:
        smooth(ob)
    subsurf(head, 1)
    smooth(head)

    def body_col(p, n):
        # Coat from the collar down to the knees, skin on the neck.
        if p.z > 1.52:
            return SKIN
        return COAT

    def head_col(p, n):
        local = p - Vector((0, 0, NECK + 0.2))
        c = Vector(SKIN)
        # Darker around the eye sockets and on the chin.
        for side in (-1, 1):
            d = (local - Vector((side * 0.062, -0.1, -0.01))).length
            if d < 0.075:
                c = c.lerp(Vector(SKIN_DARK), (0.075 - d) / 0.075 * 0.8)
        if local.z < -0.12:
            c = c.lerp(Vector(SKIN_DARK), 0.4)
        return tuple(c)

    def leg_col(p, n):
        return (0.06, 0.06, 0.06) if p.z < 0.08 else (0.16, 0.16, 0.18)

    def arm_col(p, n):
        return SKIN if p.z < 0.75 else COAT

    paint(body, body_col)
    paint(head, head_col)
    for ob in legs:
        paint(ob, leg_col)
    for ob in arms:
        paint(ob, arm_col)
    for ob in eyes:
        paint(ob, lambda p, n: (0.02, 0.02, 0.025))

    for ob in [body] + legs + arms:
        material(ob, "coat")
    material(head, "skin")
    for ob in eyes:
        material(ob, "eye")

    root = bpy.data.objects.new("alien", None)
    bpy.context.scene.collection.objects.link(root)
    parent(body, root)
    for ob in legs + arms + [head]:
        parent(ob, body)
    for ob in eyes + [face_parts]:
        parent(ob, head)


def export():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "alien.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_vertex_color="ACTIVE", export_materials="PLACEHOLDER", export_yup=True)
    print("exported", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    reset()
    build()
    export()
