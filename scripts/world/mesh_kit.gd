class_name MeshKit
extends RefCounted
## Batches procedural geometry into one mesh per (street chunk, material).
## A kilometre of fences, houses and props ends up as a few hundred draw calls.
## UVs are in metres so materials tile at real-world scale.

const CHUNK_LEN := 50.0

var materials := {}          # name -> Material
var visibility := {}         # name -> max distance (0 = always)
var shadows := {}            # name -> bool
var _tools := {}             # "chunk|mat" -> SurfaceTool
var _counts := {}            # "chunk|mat" -> vertex count


func add_material(mat_name: String, mat: Material, cast_shadow := true, vis_range := 0.0) -> void:
	materials[mat_name] = mat
	shadows[mat_name] = cast_shadow
	visibility[mat_name] = vis_range


func _st(mat_name: String, at: Vector3) -> SurfaceTool:
	assert(materials.has(mat_name), "Unknown material " + mat_name)
	var chunk := floori(-at.z / CHUNK_LEN)
	var key := "%d|%s" % [chunk, mat_name]
	var st: SurfaceTool = _tools.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		_counts[key] = 0
	_counts[key] += 1
	return st


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, n: Vector3, col: Color) -> void:
	# a-b-c-d counter-clockwise when seen from the normal side.
	st.set_color(col)
	st.set_normal(n)
	for v in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])


## Axis-aligned box in local space of `xf`, centred at xf.origin, size in metres.
## skip: bitmask of faces to omit (1:+X 2:-X 4:+Y 8:-Y 16:+Z 32:-Z) to save triangles.
func box(mat_name: String, xf: Transform3D, size: Vector3, col := Color.WHITE, skip := 8) -> void:
	var st := _st(mat_name, xf.origin)
	var h := size * 0.5
	var b := xf.basis
	var o := xf.origin
	var faces := [
		[Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP, h.x, size.z, size.y, 1],
		[Vector3.LEFT, Vector3(0, 0, 1), Vector3.UP, h.x, size.z, size.y, 2],
		[Vector3.UP, Vector3.RIGHT, Vector3(0, 0, -1), h.y, size.x, size.z, 4],
		[Vector3.DOWN, Vector3.RIGHT, Vector3(0, 0, 1), h.y, size.x, size.z, 8],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP, h.z, size.x, size.y, 16],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP, h.z, size.x, size.y, 32],
	]
	for f in faces:
		if skip & f[6]:
			continue
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var c := n * float(f[3])
		var p0 := o + b * (c - u * hu - v * hv)
		var p1 := o + b * (c + u * hu - v * hv)
		var p2 := o + b * (c + u * hu + v * hv)
		var p3 := o + b * (c - u * hu + v * hv)
		var w: float = f[4]
		var hh: float = f[5]
		_quad(st, p0, p1, p2, p3, Vector2(0, hh), Vector2(w, hh), Vector2(w, 0), Vector2(0, 0),
			(b * n).normalized(), col)


## Arbitrary planar quad given in world space (corners counter-clockwise from the front).
func quad(mat_name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col := Color.WHITE,
		double_sided := false) -> void:
	var st := _st(mat_name, (a + c) * 0.5)
	var n := (b - a).cross(d - a).normalized()
	var w := a.distance_to(b)
	var h := a.distance_to(d)
	_quad(st, a, b, c, d, Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0), n, col)
	if double_sided:
		_quad(st, b, a, d, c, Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0), -n, col)


## Triangle (gable ends etc.), UV from planar projection.
func tri(mat_name: String, a: Vector3, b: Vector3, c: Vector3, col := Color.WHITE) -> void:
	var st := _st(mat_name, (a + b + c) / 3.0)
	var n := (b - a).cross(c - a).normalized()
	var ax := (b - a).normalized()
	var ay := n.cross(ax)
	st.set_color(col)
	st.set_normal(n)
	for p: Vector3 in [a, c, b]:
		st.set_uv(Vector2((p - a).dot(ax), -(p - a).dot(ay)))
		st.add_vertex(p)


## Tapered cylinder along local +Y of xf. Used for posts, trunks, pipes.
func cylinder(mat_name: String, xf: Transform3D, r0: float, r1: float, height: float,
		segs := 8, col := Color.WHITE, caps := true) -> void:
	var st := _st(mat_name, xf.origin)
	var circ := TAU * maxf(r0, r1)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var slope := (r0 - r1) / height
		var n0 := (xf.basis * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (xf.basis * (d1 + Vector3(0, slope, 0))).normalized()
		var p0 := xf * (d0 * r0)
		var p1 := xf * (d1 * r0)
		var p2 := xf * (d1 * r1 + Vector3(0, height, 0))
		var p3 := xf * (d0 * r1 + Vector3(0, height, 0))
		var u0 := circ * i / segs
		var u1 := circ * (i + 1) / segs
		st.set_color(col)
		for v in [[p0, Vector2(u0, height), n0], [p1, Vector2(u1, height), n1], [p2, Vector2(u1, 0), n1],
				[p0, Vector2(u0, height), n0], [p2, Vector2(u1, 0), n1], [p3, Vector2(u0, 0), n0]]:
			st.set_normal(v[2])
			st.set_uv(v[1])
			st.add_vertex(v[0])
		if caps and r1 > 0.0:
			var top := xf * Vector3(0, height, 0)
			var tn := (xf.basis * Vector3.UP).normalized()
			st.set_normal(tn)
			for p: Vector3 in [top, p3, p2]:
				st.set_uv(Vector2((p - top).x, (p - top).z))
				st.add_vertex(p)


## Commits everything as MeshInstance3D children of `parent`. Returns draw-call count.
func build(parent: Node3D) -> int:
	var made := 0
	for key: String in _tools:
		var parts := key.split("|")
		var mat_name := parts[1]
		var st: SurfaceTool = _tools[key]
		st.index()
		st.generate_tangents()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Batch_%s_%s" % [parts[0], mat_name]
		mi.mesh = mesh
		mi.material_override = materials[mat_name]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows[mat_name] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var vr: float = visibility[mat_name]
		if vr > 0.0:
			mi.visibility_range_end = vr
			mi.visibility_range_end_margin = vr * 0.1
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
		made += 1
	_tools.clear()
	_counts.clear()
	return made
