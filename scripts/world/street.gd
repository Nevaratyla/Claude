class_name Street
extends Node3D
## Procedural dacha street: ~1 km lane between fences with plots on both sides.
## Deterministic (fixed seed) so every run and every player sees the same street.

const SURFACE := preload("res://shaders/surface.gdshader")
const GROUND := preload("res://shaders/ground.gdshader")
const CHAINLINK := preload("res://shaders/chainlink.gdshader")
const WINDOW := preload("res://shaders/window.gdshader")

const LENGTH := 1000.0
const FENCE_X := 4.0
const START_Z := 6.0
const PLOT_DEPTH := 28.0

const PROF_COLORS := [Color(0.12, 0.3, 0.19), Color(0.3, 0.18, 0.12), Color(0.45, 0.47, 0.48),
	Color(0.16, 0.27, 0.45), Color(0.45, 0.11, 0.1), Color(0.62, 0.56, 0.45)]
const PAINT_COLORS := [Color(0.2, 0.42, 0.22), Color(0.25, 0.42, 0.62), Color(0.55, 0.7, 0.78),
	Color(0.78, 0.62, 0.25), Color(0.38, 0.24, 0.15), Color(0.88, 0.87, 0.82)]
const WALL_COLORS := [Color(0.93, 0.92, 0.88), Color(0.86, 0.78, 0.62), Color(0.92, 0.86, 0.6),
	Color(0.7, 0.8, 0.66), Color(0.68, 0.78, 0.86), Color(0.7, 0.7, 0.68), Color(0.72, 0.55, 0.38)]
const ROOF_COLORS := [Color(0.1, 0.3, 0.2), Color(0.3, 0.17, 0.12), Color(0.42, 0.12, 0.1),
	Color(0.15, 0.25, 0.42), Color(0.35, 0.36, 0.37)]

var rng := RandomNumberGenerator.new()
var mk := MeshKit.new()
var plots: Array[Dictionary] = []
var pole_positions: Array[Vector3] = []
var draw_batches := 0


func build() -> void:
	rng.seed = 20261029
	_make_materials()
	_ground()
	_layout_plots()
	for p in plots:
		_plot_fence(p)
		_side_fence(p)
		if p.kind != "empty":
			_house(p)
		_yard(p)
	_poles_and_wires()
	_entrance()
	draw_batches = mk.build(self)
	_collision()


# ---------------------------------------------------------------- materials

func _surf(kind: int, albedo: Color, rough := 0.7, metal := 0.0, grime := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("grime", grime)
	return m


func _make_materials() -> void:
	var g := ShaderMaterial.new()
	g.shader = GROUND
	mk.add_material("ground", g, false)
	mk.add_material("wood", _surf(1, Color(1, 1, 1), 0.8))
	mk.add_material("metal_sheet", _surf(2, Color(1, 1, 1), 0.42, 0.35, 0.35))
	mk.add_material("brick", _surf(3, Color(1, 1, 1), 0.85))
	mk.add_material("concrete", _surf(4, Color(1, 1, 1), 0.9, 0.0, 0.7))
	mk.add_material("roof_tile", _surf(5, Color(1, 1, 1), 0.38, 0.4, 0.1))
	mk.add_material("siding", _surf(6, Color(1, 1, 1), 0.55, 0.0, 0.4))
	mk.add_material("slate", _surf(7, Color(0.62, 0.62, 0.6), 0.9, 0.0, 0.2))
	mk.add_material("paint", _surf(0, Color(1, 1, 1), 0.5, 0.0, 0.3))
	mk.add_material("metal", _surf(0, Color(1, 1, 1), 0.45, 0.75, 0.3))
	var cl := ShaderMaterial.new()
	cl.shader = CHAINLINK
	mk.add_material("chainlink", cl, true, 160.0)
	var w := ShaderMaterial.new()
	w.shader = WINDOW
	mk.add_material("glass", w, false)
	var wire := _surf(0, Color(0.08, 0.08, 0.08), 0.6, 0.2, 0.0)
	mk.add_material("wire", wire, false)
	var poly := StandardMaterial3D.new()
	poly.albedo_color = Color(0.9, 0.95, 0.95, 0.35)
	poly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	poly.roughness = 0.15
	poly.cull_mode = BaseMaterial3D.CULL_DISABLED
	poly.vertex_color_use_as_albedo = false
	mk.add_material("polycarbonate", poly, false, 220.0)


# ------------------------------------------------------------------- helpers

## Basis whose X runs along `dir` (XZ plane), Y up, Z = X × Y.
static func run_basis(dir: Vector3) -> Basis:
	var x := Vector3(dir.x, 0, dir.z).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


func _tri_out(mat: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		mk.tri(mat, a, c, b, col)
	else:
		mk.tri(mat, a, b, c, col)


func _pick(arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


func _jit(c: Color, amount := 0.06) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(c.r * f, c.g * f, c.b * f)


# -------------------------------------------------------------------- ground

func _ground() -> void:
	var z := START_Z + 30.0
	while z > -LENGTH - 60.0:
		var z1 := z - MeshKit.CHUNK_LEN
		mk.quad("ground", Vector3(-60, 0, z), Vector3(60, 0, z), Vector3(60, 0, z1), Vector3(-60, 0, z1))
		z = z1
	# Far fields out to the horizon (hidden by the tree belts and fog).
	var zf0 := START_Z + 1500.0
	var zf1 := -LENGTH - 1500.0
	for x: Array in [[-1500.0, -60.0], [60.0, 1500.0]]:
		mk.quad("ground", Vector3(x[0], 0, zf0), Vector3(x[1], 0, zf0), Vector3(x[1], 0, zf1), Vector3(x[0], 0, zf1))
	for zz: Array in [[zf0, START_Z + 30.0], [z, zf1]]:
		mk.quad("ground", Vector3(-60, 0, zz[0]), Vector3(60, 0, zz[0]), Vector3(60, 0, zz[1]), Vector3(-60, 0, zz[1]))


# --------------------------------------------------------------------- plots

func _layout_plots() -> void:
	var kinds := ["picket", "prof", "prof", "brick", "euro", "rabitsa", "ranch", "old", "picket", "prof"]
	for side: int in [-1, 1]:
		var z := START_Z - 4.0 - rng.randf_range(0.0, 8.0)
		var idx := 0
		while z > -LENGTH + 10.0:
			var w := rng.randf_range(17.0, 27.0)
			var p := {
				"side": side, "z0": z, "z1": z - w, "idx": idx,
				"fence": _pick(kinds),
				"kind": "house" if rng.randf() > 0.07 else "empty",
				"fh": rng.randf_range(1.55, 2.05),
				"gate_at": rng.randf_range(0.15, 0.6),
			}
			plots.append(p)
			z -= w
			idx += 1


## Returns positions of front fence gate opening (distance along run) so houses
## and drives line up with them.
func _plot_fence(p: Dictionary) -> void:
	var s: int = p.side
	var a: Vector3
	var b: Vector3
	# Run direction chosen so that local +Z points into the plot.
	if s > 0:
		a = Vector3(FENCE_X, 0, p.z0)
		b = Vector3(FENCE_X, 0, p.z1)
	else:
		a = Vector3(-FENCE_X, 0, p.z1)
		b = Vector3(-FENCE_X, 0, p.z0)
	var length := a.distance_to(b)
	var gate_start: float = length * p.gate_at
	var gate_len := 3.4
	# Fence before gate, gate itself, wicket and fence after.
	_fence_run(p.fence, a, b, 0.0, gate_start, p)
	_gate(p, a, b, gate_start, gate_len)
	_fence_run(p.fence, a, b, gate_start + gate_len + 1.1, length, p)
	p.gate_world = a.lerp(b, (gate_start + gate_len * 0.5) / length)


func _side_fence(p: Dictionary) -> void:
	var s: int = p.side
	var a := Vector3(s * FENCE_X, 0, p.z1)
	var b := Vector3(s * (FENCE_X + PLOT_DEPTH), 0, p.z1)
	if s < 0:
		var t := a
		a = b
		b = t
	var style: String = "rabitsa" if rng.randf() < 0.55 else ("old" if rng.randf() < 0.5 else p.fence)
	var sp := p.duplicate()
	sp.fh = minf(p.fh, 1.7)
	_fence_run(style, a, b, 0.0, a.distance_to(b), sp)


func _fence_run(style: String, a: Vector3, b: Vector3, d0: float, d1: float, p: Dictionary) -> void:
	if d1 - d0 < 0.3:
		return
	var dir := (b - a).normalized()
	var bs := run_basis(dir)
	var h: float = p.fh
	if not p.has("colors"):
		p.colors = {"prof": _pick(PROF_COLORS), "paint": _pick(PAINT_COLORS),
			"wood": _pick([Color(0.32, 0.2, 0.12), Color(0.45, 0.3, 0.18), Color(0.6, 0.47, 0.32)])}
	var cols: Dictionary = p.colors
	var at := func(d: float, y: float, z: float) -> Vector3:
		return a + dir * d + Vector3(0, y, 0) + bs.z * z
	var seg_len := d1 - d0

	match style:
		"picket", "old":
			var old := style == "old"
			var post_col: Color = cols.wood if not old else Color(0.48, 0.46, 0.42)
			var plank_col: Color = cols.wood if not old else Color(0.55, 0.53, 0.49)
			var pitch := 0.135 if not old else 0.16
			var pw := 0.095 if not old else 0.15
			_posts(a, dir, bs, d0, d1, 2.4, h + 0.05, 0.08, "wood", post_col)
			for ry: float in [0.3, h - 0.3]:
				mk.box("wood", Transform3D(bs, at.call((d0 + d1) * 0.5, ry, 0.045)),
					Vector3(seg_len, 0.05, 0.035), _jit(post_col))
			var d := d0 + 0.05
			while d < d1 - 0.05:
				if old and rng.randf() < 0.04:
					d += pitch
					continue
				var ph := h + rng.randf_range(-0.03, 0.03) if not old else h + rng.randf_range(-0.12, 0.05)
				var lean := Basis(bs.x, deg_to_rad(rng.randf_range(-1.5, 1.5))) * bs if old else bs
				var c: Vector3 = at.call(d, ph * 0.5 + 0.05, 0.0)
				mk.box("wood", Transform3D(lean, c), Vector3(pw, ph, 0.022), _jit(plank_col, 0.1), 8)
				if not old:
					# Pointed top.
					var top: Vector3 = c + Vector3(0, ph * 0.5, 0)
					var l := bs.x * pw * 0.5
					var tip := top + Vector3(0, 0.07, 0)
					_tri_out("wood", top - l - bs.z * 0.011, top + l - bs.z * 0.011, tip - bs.z * 0.011, -bs.z, plank_col)
					_tri_out("wood", top - l + bs.z * 0.011, top + l + bs.z * 0.011, tip + bs.z * 0.011, bs.z, plank_col)
				d += pitch
		"prof":
			_posts(a, dir, bs, d0, d1, 2.5, h, 0.06, "metal", Color(0.25, 0.25, 0.25))
			for ry: float in [0.35, h - 0.3]:
				mk.box("metal", Transform3D(bs, at.call((d0 + d1) * 0.5, ry, 0.05)),
					Vector3(seg_len, 0.04, 0.02), Color(0.3, 0.3, 0.3))
			# Sheets 1.15 m wide with tiny overlaps so seams read.
			var d := d0
			while d < d1 - 0.01:
				var sw := minf(1.15, d1 - d)
				mk.box("metal_sheet", Transform3D(bs, at.call(d + sw * 0.5, h * 0.5 + 0.04, -0.012 + fmod(d, 2.3) * 0.002)),
					Vector3(sw + 0.02, h - 0.04, 0.006), _jit(cols.prof, 0.03), 0)
				d += sw
		"brick":
			var span := 3.0
			var n := maxi(1, roundi(seg_len / span))
			var step_len := seg_len / n
			mk.box("concrete", Transform3D(bs, at.call((d0 + d1) * 0.5, 0.12, 0.0)),
				Vector3(seg_len, 0.25, 0.3), Color(0.7, 0.7, 0.68))
			for i in n + 1:
				var dd := d0 + i * step_len
				mk.box("brick", Transform3D(bs, at.call(dd, (h + 0.15) * 0.5, 0.0)),
					Vector3(0.38, h + 0.15, 0.38), Color(0.62, 0.27, 0.18) if p.idx % 2 == 0 else Color(0.85, 0.78, 0.62))
				mk.box("metal", Transform3D(bs, at.call(dd, h + 0.18, 0.0)), Vector3(0.46, 0.06, 0.46),
					Color(0.25, 0.25, 0.27), 0)
			var dd2 := d0 + 0.19
			while dd2 < d1 - 0.2:
				var sw := minf(step_len - 0.38, d1 - 0.19 - dd2)
				mk.box("metal_sheet", Transform3D(bs, at.call(dd2 + sw * 0.5, (h - 0.25) * 0.5 + 0.25, 0.0)),
					Vector3(sw, h - 0.3, 0.006), cols.prof, 0)
				dd2 += step_len
		"euro":
			var span := 2.0
			var col := Color(0.78, 0.76, 0.72) if rng.randf() < 0.6 else Color(0.82, 0.72, 0.55)
			var d := d0
			while d < d1 - 0.1:
				var sw := minf(span, d1 - d)
				mk.box("concrete", Transform3D(bs, at.call(d, (h + 0.1) * 0.5, 0.0)), Vector3(0.14, h + 0.1, 0.14), col)
				for k in 4:
					var yy := 0.05 + (h / 4.0) * (k + 0.5)
					var inset := 0.0 if k % 2 == 0 else 0.015
					mk.box("concrete", Transform3D(bs, at.call(d + sw * 0.5, yy, inset)),
						Vector3(sw - 0.14, h / 4.0 - 0.02, 0.05), _jit(col, 0.03))
				d += sw
		"rabitsa":
			_posts(a, dir, bs, d0, d1, 2.5, h, 0.0, "metal", Color(0.28, 0.3, 0.28), true)
			var p0: Vector3 = at.call(d0, 0.05, 0.0)
			var p1: Vector3 = at.call(d1, 0.05, 0.0)
			mk.quad("chainlink", p0, p1, p1 + Vector3(0, h - 0.1, 0), p0 + Vector3(0, h - 0.1, 0))
		"ranch":
			_posts(a, dir, bs, d0, d1, 2.2, h, 0.1, "wood", cols.paint.darkened(0.2))
			var y := 0.12
			while y < h - 0.1:
				mk.box("wood", Transform3D(bs, at.call((d0 + d1) * 0.5, y + 0.06, -0.06)),
					Vector3(seg_len, 0.12, 0.025), _jit(cols.paint, 0.05))
				y += 0.16


func _posts(a: Vector3, dir: Vector3, bs: Basis, d0: float, d1: float, spacing: float, h: float,
		size: float, mat: String, col: Color, round_posts := false) -> int:
	var n := maxi(1, ceili((d1 - d0) / spacing))
	var step_len := (d1 - d0) / n
	for i in n + 1:
		var c := a + dir * (d0 + i * step_len)
		if round_posts:
			mk.cylinder(mat, Transform3D(bs, c), 0.03, 0.03, h + 0.05, 6, col)
		else:
			mk.box(mat, Transform3D(bs, c + Vector3(0, h * 0.5, 0.04)), Vector3(size, h, size), _jit(col))
	return n + 1


func _gate(p: Dictionary, a: Vector3, b: Vector3, start: float, length: float) -> void:
	var dir := (b - a).normalized()
	var bs := run_basis(dir)
	var h: float = p.fh + 0.05
	var cols: Dictionary = p.colors
	var at := func(d: float, y: float, z: float) -> Vector3:
		return a + dir * d + Vector3(0, y, 0) + bs.z * z
	var metal: bool = p.fence in ["prof", "brick", "rabitsa", "euro"]
	# Gate posts.
	for d: float in [start, start + length, start + length + 1.1]:
		mk.box("metal", Transform3D(bs, at.call(d, h * 0.5, 0.0)), Vector3(0.08, h + 0.1, 0.08), Color(0.22, 0.22, 0.22))
	for leaf in 2:
		var ls := start + leaf * length * 0.5
		var lc: Vector3 = at.call(ls + length * 0.25, h * 0.5 + 0.06, 0.0)
		if metal:
			mk.box("metal_sheet", Transform3D(bs, lc), Vector3(length * 0.5 - 0.04, h - 0.1, 0.006),
				cols.prof if p.fence != "rabitsa" else Color(0.3, 0.32, 0.3), 0)
			mk.box("metal", Transform3D(bs, lc + bs.z * 0.03), Vector3(length * 0.5 - 0.04, 0.04, 0.03), Color(0.2, 0.2, 0.2))
		else:
			var d := ls + 0.06
			while d < ls + length * 0.5 - 0.05:
				mk.box("wood", Transform3D(bs, at.call(d, h * 0.5, 0.0)), Vector3(0.1, h - 0.08, 0.022), _jit(cols.wood, 0.08), 8)
				d += 0.135
			mk.box("wood", Transform3D(Basis(bs.z, atan2(h, length * 0.5)) * bs, lc + bs.z * 0.03),
				Vector3(sqrt(h * h + length * length * 0.25) - 0.1, 0.08, 0.03), cols.wood.darkened(0.1))
	# Wicket with handle.
	var wc: Vector3 = at.call(start + length + 0.55, h * 0.5 + 0.05, 0.0)
	if metal:
		mk.box("metal_sheet", Transform3D(bs, wc), Vector3(0.95, h - 0.1, 0.006), cols.prof, 0)
	else:
		mk.box("wood", Transform3D(bs, wc), Vector3(0.95, h - 0.1, 0.03), cols.wood)
	mk.box("metal", Transform3D(bs, wc + bs.x * 0.35 - bs.z * 0.03 + Vector3(0, -0.05, 0)),
		Vector3(0.12, 0.03, 0.03), Color(0.1, 0.1, 0.1))
	# Mailbox on some gates.
	if rng.randf() < 0.35:
		mk.box("paint", Transform3D(bs, wc + bs.x * 0.1 - bs.z * 0.08 + Vector3(0, 0.2, 0)),
			Vector3(0.28, 0.36, 0.1), Color(0.15, 0.35, 0.6))


# -------------------------------------------------------------------- houses

func _house(p: Dictionary) -> void:
	var s: int = p.side
	var plot_w: float = p.z0 - p.z1
	var setback := rng.randf_range(6.0, 12.0)
	var types := ["mansard", "gable", "gable", "old", "brick2"]
	var t: String = _pick(types)
	var w := rng.randf_range(5.5, 7.5)       # along ridge
	var d := rng.randf_range(5.0, 6.8)       # span
	var wall_h := rng.randf_range(2.5, 2.8)
	if t == "old":
		w = rng.randf_range(4.5, 6.0)
		d = rng.randf_range(4.0, 5.0)
		wall_h = 2.3
	elif t == "brick2":
		wall_h = 5.4
	var gable_to_street := rng.randf() < 0.55
	var cz: float = p.z1 + plot_w * rng.randf_range(0.35, 0.65)
	var cx := s * (FENCE_X + setback + (w if gable_to_street else d) * 0.5)
	var ridge_dir := Vector3(s, 0, 0) if gable_to_street else Vector3(0, 0, -1)
	var bs := run_basis(ridge_dir)   # local X along ridge, Z across span
	var origin := Vector3(cx, 0, cz)
	var base := Transform3D(bs, origin)
	p.house = {"type": t, "pos": origin, "basis": bs, "w": w, "d": d}

	var wall_col: Color = _pick(WALL_COLORS)
	var roof_col: Color = _pick(ROOF_COLORS)
	var wall_mat := "siding"
	if t == "brick2":
		wall_mat = "brick"
		wall_col = _pick([Color(0.62, 0.27, 0.18), Color(0.85, 0.78, 0.62), Color(0.55, 0.38, 0.3)])
	elif t == "old":
		wall_mat = "wood"
		wall_col = _pick(PAINT_COLORS)
	var roof_mat := "slate" if t == "old" or rng.randf() < 0.15 else "roof_tile"
	if roof_mat == "slate":
		roof_col = Color(1, 1, 1)

	# Foundation and walls.
	mk.box("concrete", base.translated_local(Vector3(0, 0.2, 0)), Vector3(w + 0.12, 0.4, d + 0.12), Color(0.66, 0.65, 0.62))
	mk.box(wall_mat, base.translated_local(Vector3(0, 0.4 + wall_h * 0.5, 0)), Vector3(w, wall_h, d), wall_col)
	var top := 0.4 + wall_h
	if t == "brick2":
		# Floor band between storeys.
		mk.box("concrete", base.translated_local(Vector3(0, 0.4 + wall_h * 0.5, 0)), Vector3(w + 0.04, 0.14, d + 0.04), Color(0.8, 0.79, 0.75))

	# Roof profile (across span, height above wall top).
	var half := d * 0.5
	var prof: Array[Vector2] = []
	if t == "mansard":
		var knee := half * 0.32
		var lower_h := 2.2
		var upper := (half - knee) * tan(deg_to_rad(24.0))
		prof = [Vector2(-half, 0), Vector2(-half + knee, lower_h), Vector2(0, lower_h + upper),
			Vector2(half - knee, lower_h), Vector2(half, 0)]
	else:
		var pitch := deg_to_rad(rng.randf_range(28.0, 40.0) if t != "old" else 32.0)
		if t == "brick2":
			pitch = deg_to_rad(24.0)
		prof = [Vector2(-half, 0), Vector2(0, half * tan(pitch)), Vector2(half, 0)]
	_roof(base, top, w, prof, roof_mat, roof_col)
	# Gable fill.
	for end: int in [-1, 1]:
		var ex := end * w * 0.5
		var cen := base * Vector3(ex, top, 0)
		var outward := bs.x * end
		for i in prof.size() - 1:
			var p0 := base * Vector3(ex, top + prof[i].y, prof[i].x)
			var p1 := base * Vector3(ex, top + prof[i + 1].y, prof[i + 1].x)
			_tri_out("siding" if wall_mat != "brick" else "brick", cen, p0, p1, outward,
				wall_col if wall_mat != "wood" else wall_col.lightened(0.2))

	# Windows on every wall; the gable/long wall facing the street gets more.
	var wcols := Color(rng.randf(), 1.0 if rng.randf() < 0.45 else 0.0, 0)
	var frame_col: Color = Color(0.95, 0.95, 0.93) if rng.randf() < 0.6 else Color(0.35, 0.22, 0.14)
	var storeys := 2 if t == "brick2" else 1
	for face in 4:
		var n_local: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][face]
		var span := d if face < 2 else w
		var off := (w if face < 2 else d) * 0.5
		var along: Vector3 = Vector3.BACK if face < 2 else Vector3.RIGHT
		var count := maxi(1, floori(span / 2.4))
		for st in storeys:
			for i in count:
				var u := (i + 0.5) / count * span - span * 0.5
				var y := 0.4 + 0.95 + st * 2.7
				if face < 2 or rng.randf() < 0.8:
					var wc := Color(rng.randf(), wcols.g * float(rng.randf() < 0.7), 0)
					_window(base, n_local * (off + 0.005) + along * u + Vector3(0, y, 0), n_local, along,
						1.05, 1.3, frame_col, wc, t == "old")
		# Attic window in the gables.
		if face < 2:
			_window(base, n_local * (off + 0.005) + Vector3(0, top + 0.5, 0), n_local, along, 0.8,
				0.95 if t != "mansard" else 1.3, frame_col, wcols, false)
	# Door facing the street side of the house.
	var to_street := (base.basis.inverse() * Vector3(-s, 0, 0)).round()
	var door_along := Vector3(to_street.z, 0, to_street.x).abs()
	var door_off := (w if absf(to_street.x) > 0.5 else d) * 0.5
	var dpos := base * (to_street * (door_off + 0.04) + door_along * (0.35 * (w if absf(to_street.x) < 0.5 else d) * 0.5) + Vector3(0, 0.4 + 1.0, 0))
	var dbs := run_basis(base.basis * door_along)
	mk.box("paint", Transform3D(dbs, dpos), Vector3(0.9, 2.0, 0.06), Color(0.4, 0.26, 0.16))
	mk.box("concrete", Transform3D(dbs, dpos + base.basis * to_street * 0.5 + Vector3(0, -1.2, 0)),
		Vector3(1.4, 0.4, 0.9), Color(0.7, 0.7, 0.68))
	# Chimney.
	if rng.randf() < 0.7:
		var ch := base * Vector3(w * rng.randf_range(-0.25, 0.25), 0, d * 0.15)
		var peak := top + prof[prof.size() / 2].y
		mk.box("brick", Transform3D(bs, Vector3(ch.x, (top + peak + 1.0) * 0.5 + 0.5, ch.z)),
			Vector3(0.45, peak - top + 1.0, 0.45), Color(0.6, 0.28, 0.2))


func _roof(base: Transform3D, top: float, length: float, prof: Array[Vector2], mat: String, col: Color) -> void:
	var over := 0.45
	var x_axis := base.basis.x
	for i in prof.size() - 1:
		var p0 := prof[i]
		var p1 := prof[i + 1]
		var dv := (p1 - p0)
		var dirn := dv.normalized()
		# Extend the eave segments outward.
		if i == 0:
			p0 -= dirn * over
		if i == prof.size() - 2:
			p1 += dirn * over
		var a := base * Vector3(0, top + p0.y, p0.x)
		var b := base * Vector3(0, top + p1.y, p1.x)
		var zdir := (b - a).normalized()
		var ydir := zdir.cross(x_axis).normalized()
		var bsr := Basis(x_axis, ydir, zdir)
		var c := (a + b) * 0.5 + ydir * 0.04
		mk.box(mat, Transform3D(bsr, c), Vector3(length + over * 2.0, 0.06, a.distance_to(b)), col, 0)
	# Ridge cap.
	var peak := prof[prof.size() / 2]
	mk.box("metal", Transform3D(base.basis, base * Vector3(0, top + peak.y + 0.07, peak.x)),
		Vector3(length + over * 2.0, 0.06, 0.25), col.darkened(0.2))


func _window(base: Transform3D, local_c: Vector3, n_local: Vector3, along_local: Vector3,
		ww: float, wh: float, frame_col: Color, glass_col: Color, carved: bool) -> void:
	var n := (base.basis * n_local).normalized()
	var u := (base.basis * along_local).normalized()
	var c := base * local_c
	# Make u point so that u x up == n (front-facing quad).
	if u.cross(Vector3.UP).dot(n) > 0.0:
		u = -u
	var hw := ww * 0.5
	var hh := wh * 0.5
	var g := c + n * 0.01
	mk.quad("glass", g - u * hw - Vector3(0, hh, 0), g + u * hw - Vector3(0, hh, 0),
		g + u * hw + Vector3(0, hh, 0), g - u * hw + Vector3(0, hh, 0), glass_col)
	var fb := Basis(u, Vector3.UP, u.cross(Vector3.UP))
	var t := 0.06
	for e: Array in [[Vector3(0, hh, 0), Vector3(ww + t, t, t)], [Vector3(0, -hh, 0), Vector3(ww + t, t, t)],
			[u * hw, Vector3(t, wh, t)], [-u * hw, Vector3(t, wh, t)], [Vector3.ZERO, Vector3(0.04, wh, 0.04)],
			[Vector3(0, hh * 0.35, 0), Vector3(ww, 0.04, 0.04)]]:
		mk.box("paint", Transform3D(fb, c + n * 0.03 + e[0]), e[1], frame_col)
	# Sill.
	mk.box("metal", Transform3D(fb, c + n * 0.07 + Vector3(0, -hh - 0.04, 0)), Vector3(ww + 0.12, 0.03, 0.14), Color(0.8, 0.8, 0.78))
	if carved:
		# Wide painted casings (nalichniki) typical for old village houses.
		for e: Array in [[Vector3(0, hh + 0.12, 0), Vector3(ww + 0.4, 0.2, 0.03)],
				[u * (hw + 0.1), Vector3(0.12, wh + 0.2, 0.03)], [-u * (hw + 0.1), Vector3(0.12, wh + 0.2, 0.03)],
				[Vector3(0, -hh - 0.1, 0), Vector3(ww + 0.3, 0.1, 0.03)]]:
			mk.box("paint", Transform3D(fb, c + n * 0.05 + e[0]), e[1], Color(0.95, 0.95, 0.92))


# ---------------------------------------------------------------------- yard

func _yard(p: Dictionary) -> void:
	var s: int = p.side
	var plot_w: float = p.z0 - p.z1
	# Greenhouse (polycarbonate arch) in ~40% of plots.
	if rng.randf() < 0.4:
		var gx := s * (FENCE_X + rng.randf_range(15.0, 22.0))
		var gz: float = p.z1 + plot_w * rng.randf_range(0.2, 0.8)
		_greenhouse(Vector3(gx, 0, gz), rng.randf_range(4.0, 6.0))
	# Shed.
	if rng.randf() < 0.55:
		var sx := s * (FENCE_X + rng.randf_range(18.0, 25.0))
		var sz: float = p.z1 + plot_w * rng.randf_range(0.1, 0.9)
		var sb := Transform3D(run_basis(Vector3(0, 0, -1)), Vector3(sx, 0, sz))
		var sw := rng.randf_range(2.0, 3.0)
		mk.box("wood", sb.translated_local(Vector3(0, 1.1, 0)), Vector3(sw, 2.2, 2.0), Color(0.5, 0.42, 0.32))
		_roof(sb, 2.2, sw, [Vector2(-1.0, 0), Vector2(0, 0.5), Vector2(1.0, 0)] as Array[Vector2], "slate", Color(1, 1, 1))
	# Blue water barrel near the fence.
	if rng.randf() < 0.35:
		var bx := s * (FENCE_X + rng.randf_range(1.0, 3.0))
		var bz: float = p.z1 + plot_w * rng.randf_range(0.1, 0.9)
		mk.cylinder("paint", Transform3D(Basis(), Vector3(bx, 0, bz)), 0.3, 0.3, 0.9, 12, Color(0.1, 0.25, 0.55))


func _greenhouse(c: Vector3, length: float) -> void:
	var r := 1.5
	var segs := 8
	var bs := run_basis(Vector3(1, 0, 0))
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(0, sin(a0) * r * 1.3, cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r * 1.3, cos(a1) * r)
		var hx := Vector3(length * 0.5, 0, 0)
		mk.quad("polycarbonate", c + bs * (p0 - hx), c + bs * (p0 + hx), c + bs * (p1 + hx), c + bs * (p1 - hx))
	# Arches.
	var k := 0.0
	while k <= length + 0.01:
		for i in segs:
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			var p0 := Vector3(k - length * 0.5, sin(a0) * r * 1.3, cos(a0) * r)
			var p1 := Vector3(k - length * 0.5, sin(a1) * r * 1.3, cos(a1) * r)
			var q0 := c + bs * p0
			var q1 := c + bs * p1
			var dirv := (q1 - q0).normalized()
			mk.box("metal", Transform3D(Basis(bs.x, dirv.cross(bs.x), dirv).orthonormalized(), (q0 + q1) * 0.5),
				Vector3(0.03, 0.03, q0.distance_to(q1)), Color(0.85, 0.85, 0.85), 0)
		k += 1.0


# --------------------------------------------------------------- power lines

func _poles_and_wires() -> void:
	var px := -FENCE_X + 0.45
	var z := START_Z - 3.0
	var poles: Array[Vector3] = []
	while z > -LENGTH:
		poles.append(Vector3(px + rng.randf_range(-0.05, 0.05), 0, z))
		z -= rng.randf_range(36.0, 42.0)
	pole_positions = poles
	var heights := [8.4, 8.1, 7.8, 7.5]
	for i in poles.size():
		var p: Vector3 = poles[i]
		var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(rng.randf_range(-1.5, 1.5)))
		var xf := Transform3D(tilt, p)
		# Concrete pole: tapered square section.
		mk.cylinder("concrete", xf, 0.14, 0.09, 9.0, 4, Color(0.72, 0.71, 0.68))
		# Crossarm and insulators.
		mk.box("metal", Transform3D(tilt, p + tilt * Vector3(0.25, 8.45, 0)), Vector3(1.0, 0.06, 0.06), Color(0.3, 0.3, 0.3))
		for k in 4:
			var ins := p + tilt * Vector3(-0.2 + k * 0.25, heights[k] + (0.0 if k < 2 else 0.0), 0)
			mk.cylinder("paint", Transform3D(tilt, ins - Vector3(0, 0.08, 0)), 0.03, 0.025, 0.1, 6, Color(0.92, 0.92, 0.9))
		if i % 3 == 1:
			# Street lamp arm over the road.
			var arm0 := p + tilt * Vector3(0, 7.2, 0)
			var arm1 := arm0 + Vector3(1.6, 0.25, 0)
			mk.box("metal", Transform3D(run_basis(Vector3(1, 0, 0)), (arm0 + arm1) * 0.5), Vector3(1.62, 0.05, 0.05), Color(0.35, 0.35, 0.35))
			mk.box("paint", Transform3D(run_basis(Vector3(1, 0, 0)), arm1 + Vector3(0.15, -0.06, 0)), Vector3(0.5, 0.12, 0.22), Color(0.25, 0.27, 0.3))
	# Catenary wires between poles.
	for i in poles.size() - 1:
		for k in 4:
			var a: Vector3 = poles[i] + Vector3(-0.2 + k * 0.25, heights[k] + 0.02, 0)
			var b: Vector3 = poles[i + 1] + Vector3(-0.2 + k * 0.25, heights[k] + 0.02, 0)
			_wire(a, b, 0.55 + k * 0.05)
	# Service drops to houses on the left side.
	for p in plots:
		if p.side < 0 and p.has("house") and rng.randf() < 0.7:
			var hp: Vector3 = p.house.pos
			var nearest: Vector3 = poles[0]
			for q in poles:
				if absf(q.z - hp.z) < absf(nearest.z - hp.z):
					nearest = q
			_wire(nearest + Vector3(-0.2, 7.5, 0), Vector3(hp.x + 2.5, 3.6, hp.z), 0.35)


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var segs := 10
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var dir := (p - prev).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var up := side.cross(dir)
		mk.box("wire", Transform3D(Basis(side, up, dir), (p + prev) * 0.5), Vector3(0.012, 0.012, prev.distance_to(p) + 0.01), Color.WHITE, 0)
		prev = p


# ------------------------------------------------------------------ entrance

func _entrance() -> void:
	# Big open metal gate of the SNT behind the players' starting point.
	var z := START_Z + 2.0
	for x: float in [-3.3, 3.3]:
		mk.box("metal", Transform3D(Basis(), Vector3(x, 1.4, z)), Vector3(0.12, 2.8, 0.12), Color(0.2, 0.22, 0.2))
	# Leaves swung open toward the fences.
	for sgn: int in [-1, 1]:
		var hinge := Vector3(sgn * 3.3, 1.2, z)
		var leaf_dir := Vector3(sgn * 0.25, 0, -1).normalized() * -1.0
		var c := hinge + leaf_dir * -1.6
		mk.box("metal_sheet", Transform3D(run_basis(leaf_dir), c), Vector3(3.1, 1.9, 0.01), Color(0.12, 0.3, 0.19), 0)
	# Sign board.
	var sign_pos := Vector3(-3.5, 2.1, z - 0.08)
	mk.box("paint", Transform3D(Basis(), sign_pos), Vector3(1.6, 0.8, 0.03), Color(0.92, 0.92, 0.9))
	var l1 := Label3D.new()
	l1.text = "СНТ «Рассвет»\n\nПОСТОРОННИМ\nВХОД ВОСПРЕЩЁН"
	l1.font_size = 64
	l1.pixel_size = 0.0022
	l1.modulate = Color(0.75, 0.08, 0.06)
	l1.outline_size = 0
	l1.position = sign_pos + Vector3(0, 0, -0.02)
	l1.rotation_degrees = Vector3(0, 180, 0)
	l1.shaded = true
	l1.double_sided = false
	add_child(l1)


# ----------------------------------------------------------------- collision

func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "StreetCollision"
	add_child(body)
	var shapes := [
		[Vector3(0, -0.5, -LENGTH * 0.5), Vector3(40, 1, LENGTH + 80)],
		[Vector3(FENCE_X + 0.15, 2, -LENGTH * 0.5), Vector3(0.3, 4, LENGTH + 80)],
		[Vector3(-FENCE_X - 0.15, 2, -LENGTH * 0.5), Vector3(0.3, 4, LENGTH + 80)],
		[Vector3(0, 2, START_Z + 4.0), Vector3(10, 4, 0.5)],
		[Vector3(0, 2, -LENGTH - 2.0), Vector3(10, 4, 0.5)],
	]
	for sdef in shapes:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sdef[1]
		cs.shape = bx
		cs.position = sdef[0]
		body.add_child(cs)
	for p: Vector3 in pole_positions:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.14
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 2.0, 0)
		body.add_child(cs)
