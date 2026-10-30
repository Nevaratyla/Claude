class_name Burdock
extends RefCounted
## Burdock (лопух) and plantain meshes: rosettes of big curved leaves drawn
## with the burdock tile of the leaf atlas. Optional flower stalk with burrs.
## Meshes carry their own surface materials so MultiMesh can use them as is.

const FOLIAGE := preload("res://shaders/foliage.gdshader")

static var _leaf_mat: ShaderMaterial
static var _plantain_mat: ShaderMaterial
static var _stalk_mat: StandardMaterial3D


static func leaf_material(plantain := false) -> ShaderMaterial:
	if _leaf_mat == null:
		for i in 2:
			var m := ShaderMaterial.new()
			m.shader = FOLIAGE
			m.set_shader_parameter("tile", 7)
			m.set_shader_parameter("random_flip", false)
			m.set_shader_parameter("autumn", 0.06 if i == 0 else 0.0)
			m.set_shader_parameter("autumn_color", Color(0.55, 0.45, 0.2))
			m.set_shader_parameter("flex", 0.12)
			m.set_shader_parameter("translucency", 0.5)
			m.set_shader_parameter("alpha_cut", 0.4)
			if i == 0:
				_leaf_mat = m
			else:
				_plantain_mat = m
	return _plantain_mat if plantain else _leaf_mat


static func _stalk_material() -> StandardMaterial3D:
	if _stalk_mat == null:
		_stalk_mat = StandardMaterial3D.new()
		_stalk_mat.vertex_color_use_as_albedo = true
		_stalk_mat.roughness = 0.8
		# Thin stems and tiny burrs: render both sides rather than fuss over winding.
		_stalk_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _stalk_mat


## leaves: count, size: leaf length in metres, tint: leaf colour.
static func make_mesh(rng: RandomNumberGenerator, leaves: int, size: float, tint: Color,
		stalk := false, plantain := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_angle := rng.randf() * TAU
	for i in leaves:
		var a := start_angle + TAU * i / leaves + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP)
		var length := size * rng.randf_range(0.75, 1.15)
		var width := length * (0.72 if not plantain else 0.55)
		# Leaves rise from the centre and droop toward the tip.
		var elev0 := deg_to_rad(rng.randf_range(58.0, 80.0) if not plantain else rng.randf_range(10.0, 25.0))
		var elev1 := deg_to_rad(rng.randf_range(-25.0, -5.0))
		var segs := 4
		var p := dir * size * 0.08 + Vector3(0, size * 0.05, 0)
		var rows: Array = []
		for k in segs + 1:
			var t := float(k) / segs
			rows.append([p, t])
			var elev := lerpf(elev0, elev1, t)
			p += (dir * cos(elev) + Vector3.UP * sin(elev)) * length / segs
		var shade := rng.randf_range(0.85, 1.12)
		for k in segs:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			var c0: Vector3 = r0[0]
			var c1: Vector3 = r1[0]
			var t0: float = r0[1]
			var t1: float = r1[1]
			# Leaf blade cupped slightly: edges a bit lower than the midrib.
			var cup := Vector3(0, -width * 0.08, 0)
			var hw := width * 0.5
			var l0 := c0 - side * hw + cup
			var rr0 := c0 + side * hw + cup
			var l1 := c1 - side * hw + cup
			var rr1 := c1 + side * hw + cup
			var n := (c1 - c0).cross(side).normalized()
			if n.y < 0.0:
				n = -n
			var bent := (n + Vector3.UP * 0.6).normalized()
			var col := Color(tint.r * shade, tint.g * shade, tint.b * shade, clampf(0.2 + t1, 0.0, 1.0))
			st.set_color(col)
			st.set_normal(bent)
			for v: Array in [[l0, Vector2(0, 1.0 - t0)], [rr1, Vector2(1, 1.0 - t1)], [rr0, Vector2(1, 1.0 - t0)],
					[l0, Vector2(0, 1.0 - t0)], [l1, Vector2(0, 1.0 - t1)], [rr1, Vector2(1, 1.0 - t1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, leaf_material(plantain))
	if stalk:
		_add_stalk(mesh, rng, size)
	return mesh


## Tall flower stalk with clusters of hooked burrs (purple tips), late summer.
static func _add_stalk(mesh: ArrayMesh, rng: RandomNumberGenerator, size: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * rng.randf_range(1.8, 2.4)
	var stem_col := Color(0.32, 0.3, 0.16)
	_tube(st, Vector3.ZERO, Vector3(0.02, h, 0.01), 0.012, 0.006, stem_col)
	for b in rng.randi_range(4, 7):
		var y := h * rng.randf_range(0.6, 1.0)
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.08, y + 0.04, sin(a) * 0.08)
		_tube(st, Vector3(0.02 * y / h, y, 0.0), tip, 0.004, 0.003, stem_col)
		_ball(st, tip, 0.018, Color(0.36, 0.33, 0.18))
		_ball(st, tip + Vector3(0, 0.014, 0), 0.008, Color(0.55, 0.2, 0.5))
	var arrays := st.commit_to_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(1, _stalk_material())


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	var fwd := axis.cross(side)
	st.set_color(col)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		for v: Array in [[a + d0 * r0, d0], [b + d1 * r1, d1], [a + d1 * r0, d1],
				[a + d0 * r0, d0], [b + d0 * r1, d0], [b + d1 * r1, d1]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])


static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	st.set_color(col)
	var rings := 4
	var segs := 6
	for j in rings:
		var t0 := PI * j / rings
		var t1 := PI * (j + 1) / rings
		for i in segs:
			var p0 := TAU * i / segs
			var p1 := TAU * (i + 1) / segs
			var v := func(t: float, ph: float) -> Vector3:
				return Vector3(sin(t) * cos(ph), cos(t), sin(t) * sin(ph))
			var q: Array[Vector3] = [v.call(t0, p0), v.call(t0, p1), v.call(t1, p1), v.call(t1, p0)]
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_normal(q[k])
				st.add_vertex(c + q[k] * r)
