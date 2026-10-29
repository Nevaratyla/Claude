class_name Vegetation
extends Node3D
## Trees, bushes, grass and flowers. Every species is generated once as a mesh
## (trunk + leaf cards) and placed through chunked MultiMeshes, so hundreds of
## trees cost a handful of draw calls and off-screen chunks are culled.

const SURFACE := preload("res://shaders/surface.gdshader")
const FOLIAGE := preload("res://shaders/foliage.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const ATLAS := preload("res://shaders/leaf_atlas.gdshader")

const CHUNK := 100.0
const GRASS_CHUNK := 25.0
const LOD_DIST := 140.0

# Species: crown "ell" ellipsoid, "cone", "col" column. tile: leaf atlas tile.
const SPECIES := {
	"birch": {"h": 12.0, "trunk_r": 0.16, "crown": "ell", "cr": 2.6, "cbase": 0.45, "cards": 520, "card": 0.9,
		"tile": 1, "leaf": Color(0.3, 0.42, 0.13), "autumn": 0.12, "bark": 10, "branches": 9, "flex": 0.5},
	"apple": {"h": 4.2, "trunk_r": 0.12, "crown": "ell", "cr": 2.3, "cbase": 0.32, "cards": 380, "card": 0.85,
		"tile": 0, "leaf": Color(0.19, 0.3, 0.09), "autumn": 0.05, "bark": 9, "branches": 7, "flex": 0.25},
	"rowan": {"h": 6.5, "trunk_r": 0.12, "crown": "ell", "cr": 2.4, "cbase": 0.35, "cards": 420, "card": 0.9,
		"tile": 3, "leaf": Color(0.3, 0.36, 0.1), "autumn": 0.6, "bark": 9, "branches": 8, "flex": 0.35},
	"maple": {"h": 10.0, "trunk_r": 0.22, "crown": "ell", "cr": 3.6, "cbase": 0.3, "cards": 650, "card": 1.15,
		"tile": 0, "leaf": Color(0.21, 0.32, 0.09), "autumn": 0.08, "bark": 9, "branches": 10, "flex": 0.3},
	"thuja": {"h": 3.6, "trunk_r": 0.05, "crown": "col", "cr": 0.55, "cbase": 0.03, "cards": 260, "card": 0.55,
		"tile": 4, "leaf": Color(0.13, 0.25, 0.1), "autumn": 0.0, "bark": 9, "branches": 0, "flex": 0.12},
	"spruce": {"h": 11.0, "trunk_r": 0.2, "crown": "cone", "cr": 2.6, "cbase": 0.08, "cards": 900, "card": 1.3,
		"tile": 2, "leaf": Color(0.1, 0.2, 0.12), "autumn": 0.0, "bark": 9, "branches": 0, "flex": 0.15},
	"lilac": {"h": 2.4, "trunk_r": 0.04, "crown": "ell", "cr": 1.3, "cbase": 0.12, "cards": 200, "card": 0.7,
		"tile": 0, "leaf": Color(0.2, 0.33, 0.12), "autumn": 0.05, "bark": 9, "branches": 5, "flex": 0.3},
	"raspberry": {"h": 1.3, "trunk_r": 0.012, "crown": "ell", "cr": 0.8, "cbase": 0.2, "cards": 110, "card": 0.55,
		"tile": 5, "leaf": Color(0.24, 0.36, 0.13), "autumn": 0.05, "bark": 9, "branches": 6, "flex": 0.5},
}

var rng := RandomNumberGenerator.new()
var _meshes := {}            # species -> {trunk: ArrayMesh, leaves: ArrayMesh}
var _instances := {}         # "species|chunk" -> Array[Transform3D]
var _bark_mats := {}
var _leaf_mats := {}
var multimesh_count := 0
var tree_count := 0
var berry_spots: Array[Vector3] = []
var _lumps: Array = []


func _rand_unit() -> Vector3:
	var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	while v.length() > 1.0 or v.length() < 0.01:
		v = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return v.normalized()


## Bakes the leaf atlas on the GPU. Must be awaited before build().
static func bake_atlas(host: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 1024)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var mat := ShaderMaterial.new()
	mat.shader = ATLAS
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("g_leaf_atlas", tex)
	vp.queue_free()


func build(street: Street) -> void:
	rng.seed = 777
	for sp: String in SPECIES:
		_meshes[sp] = _make_species(sp, SPECIES[sp])
	_place(street)
	_commit_trees()
	_grass(street)


# ------------------------------------------------------------------ species

func _bark_mat(kind: int) -> ShaderMaterial:
	if not _bark_mats.has(kind):
		var m := ShaderMaterial.new()
		m.shader = SURFACE
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("albedo", Color(0.42, 0.36, 0.3) if kind == 9 else Color(1, 1, 1))
		m.set_shader_parameter("roughness", 0.9)
		m.set_shader_parameter("grime", 0.2)
		_bark_mats[kind] = m
	return _bark_mats[kind]


func _leaf_mat(sp: String, d: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE
	m.set_shader_parameter("tile", d.tile)
	m.set_shader_parameter("autumn", d.autumn)
	m.set_shader_parameter("flex", d.flex)
	m.set_shader_parameter("autumn_color", Color(0.95, 0.42, 0.06) if sp == "rowan" else Color(0.85, 0.62, 0.1))
	m.set_shader_parameter("translucency", 0.35 if d.tile in [2, 4] else 0.6)
	# Thin needles lose coverage in the mipmaps; a lower cut keeps spruces full.
	m.set_shader_parameter("alpha_cut", 0.25 if d.tile == 2 else 0.45)
	return m


func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, segs: int) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	side = axis.cross(Vector3.RIGHT).normalized() if side.length() < 0.5 else side
	var fwd := axis.cross(side)
	var h := a.distance_to(b)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		var circ := TAU * r0
		var quad := [[a + d0 * r0, d0, Vector2(circ * i / segs, h)], [a + d1 * r0, d1, Vector2(circ * (i + 1) / segs, h)],
			[b + d1 * r1, d1, Vector2(circ * (i + 1) / segs, 0)], [b + d0 * r1, d0, Vector2(circ * i / segs, 0)]]
		# Clockwise front faces in Godot: emit 0,2,1 / 0,3,2 when seen from outside.
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


func _crown_point(d: Dictionary, h: float) -> Vector3:
	var cb: float = d.cbase * h
	var ch := h - cb
	var r: float = d.cr
	match d.crown:
		"cone":
			var t := pow(rng.randf(), 0.8)
			var y := cb + t * ch
			var rad := r * (1.0 - t) * (0.55 + 0.45 * sqrt(rng.randf()))
			var a := rng.randf() * TAU
			return Vector3(cos(a) * rad, y, sin(a) * rad)
		"col":
			var t := rng.randf()
			var y := cb + t * ch
			var rad := r * sin(clampf(t, 0.02, 1.0) * PI * 0.85 + 0.25) * (0.7 + 0.3 * sqrt(rng.randf()))
			var a := rng.randf() * TAU
			return Vector3(cos(a) * rad, y, sin(a) * rad)
		_:
			# Irregular crowns: leaves sit on several overlapping lumps, not one sphere.
			var lump: Array = _lumps[rng.randi_range(0, _lumps.size() - 1)]
			var v := _rand_unit() * (0.6 + 0.4 * pow(rng.randf(), 0.4))
			return lump[0] + v * float(lump[1])


func _make_species(sp: String, d: Dictionary) -> Dictionary:
	var h: float = d.h
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cb: float = d.cbase * h
	var crown_c := Vector3(0, cb + (h - cb) * 0.5, 0)
	_lumps.clear()
	if d.crown == "ell":
		var lumps := rng.randi_range(6, 9)
		for i in lumps:
			var u := _rand_unit()
			u.y = u.y * 0.8 + 0.15
			var c := crown_c + Vector3(u.x * d.cr * 0.55, u.y * (h - cb) * 0.3, u.z * d.cr * 0.55)
			_lumps.append([c, d.cr * rng.randf_range(0.45, 0.62)])
	# Slightly bent trunk in three pieces.
	var pts: Array[Vector3] = [Vector3.ZERO]
	var tip_h := h * (0.85 if d.crown != "ell" else 0.7)
	for i in 3:
		var y := tip_h * (i + 1) / 3.0
		pts.append(Vector3(rng.randf_range(-0.15, 0.15) * h * 0.04, y, rng.randf_range(-0.15, 0.15) * h * 0.04))
	var r0: float = d.trunk_r
	for i in 3:
		_cyl(trunk, pts[i], pts[i + 1], r0 * (1.0 - i * 0.28), r0 * (1.0 - (i + 1) * 0.28), 7 if sp != "raspberry" else 4)
	# Main branches from the crown base out toward the crown surface.
	for i in int(d.branches):
		var start := pts[1].lerp(pts[2], rng.randf()) if sp != "raspberry" else Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var end := _crown_point(d, h)
		end = crown_c + (end - crown_c) * 0.8
		_cyl(trunk, start, end, r0 * 0.35, r0 * 0.08, 5 if sp != "raspberry" else 3)
	trunk.generate_tangents()
	var trunk_mesh := trunk.commit()

	# Leaf cards: full set for near trees, a sparse set of bigger cards for far LOD.
	var leaf_mesh := _leaf_cards(d, h, crown_c, int(d.cards), 1.0)
	var far_mesh := _leaf_cards(d, h, crown_c, maxi(24, int(d.cards) / 4), 1.75)
	_leaf_mats[sp] = _leaf_mat(sp, d)
	return {"trunk": trunk_mesh, "leaves": leaf_mesh, "leaves_far": far_mesh, "bark": _bark_mat(d.bark)}


func _leaf_cards(d: Dictionary, h: float, crown_c: Vector3, count: int, card_scale: float) -> ArrayMesh:
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col: Color = d.leaf
	var card: float = d.card * card_scale
	for i in count:
		var p := _crown_point(d, h)
		var radial := (p - crown_c)
		if d.crown != "ell":
			radial = Vector3(p.x, 0.25, p.z)
		radial = radial.normalized() if radial.length() > 0.001 else Vector3.UP
		var n := (radial + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.4, 0.9), rng.randf_range(-0.8, 0.8))).normalized()
		if d.tile == 2:
			n = (Vector3(0, 1, 0) + radial * 0.4).normalized()
		var t := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
		var b := n.cross(t)
		var spin := rng.randf() * TAU
		var u := t * cos(spin) + b * sin(spin)
		var v := n.cross(u)
		var s := card * rng.randf_range(0.75, 1.25)
		var shade := rng.randf_range(0.85, 1.15)
		var col := Color(base_col.r * shade, base_col.g * shade, base_col.b * shade, clampf(p.y / h, 0.0, 1.0))
		var bent := (n * 0.25 + radial * 0.75).normalized()
		var c0 := p - u * s * 0.5 - v * s * 0.5
		var corners := [[c0, Vector2(0, 1)], [c0 + u * s, Vector2(1, 1)], [c0 + u * s + v * s, Vector2(1, 0)], [c0 + v * s, Vector2(0, 0)]]
		leaves.set_color(col)
		leaves.set_normal(bent)
		for k: int in [0, 2, 1, 0, 3, 2]:
			leaves.set_uv(corners[k][1])
			leaves.add_vertex(corners[k][0])
	return leaves.commit()


# ---------------------------------------------------------------- placement

func _add(sp: String, pos: Vector3, scale := 1.0) -> void:
	var key := "%s|%d" % [sp, floori(-pos.z / CHUNK)]
	if not _instances.has(key):
		_instances[key] = []
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
	_instances[key].append(Transform3D(basis, pos))
	tree_count += 1


func _place(street: Street) -> void:
	var fx := Street.FENCE_X
	for p in street.plots:
		var s: int = p.side
		var z0: float = p.z0
		var z1: float = p.z1
		var house_pos: Vector3 = p.house.pos if p.has("house") else Vector3(1e6, 0, 0)
		var free := func(pos: Vector3, r: float) -> bool:
			return Vector2(pos.x - house_pos.x, pos.z - house_pos.z).length() > 5.0 + r
		# Thuja row along the front fence (as in the reference photo).
		if rng.randf() < 0.3:
			var n := rng.randi_range(3, 6)
			var start := lerpf(z0, z1, rng.randf_range(0.05, 0.4))
			for i in n:
				var pos := Vector3(s * (fx + 0.9), 0, start - i * 1.3)
				if pos.z > z1 + 0.5:
					_add("thuja", pos, rng.randf_range(0.8, 1.2))
		# Bushes inside the fence.
		for i in rng.randi_range(0, 3):
			var pos := Vector3(s * (fx + rng.randf_range(0.8, 2.5)), 0, lerpf(z0, z1, rng.randf()))
			_add("lilac" if rng.randf() < 0.6 else "raspberry", pos, rng.randf_range(0.8, 1.3))
		# Garden trees.
		var trees := rng.randi_range(1, 5)
		for i in trees:
			var pos := Vector3(s * (fx + rng.randf_range(3.0, Street.PLOT_DEPTH - 1.5)), 0, lerpf(z0 - 1.0, z1 + 1.0, rng.randf()))
			var sp: String = ["apple", "apple", "rowan", "birch", "maple", "spruce"][rng.randi_range(0, 5)]
			if free.call(pos, 2.0):
				_add(sp, pos, rng.randf_range(0.8, 1.2))
		# Raspberry patches near the fence (berries for the quest).
		if rng.randf() < 0.2:
			for i in rng.randi_range(3, 6):
				_add("raspberry", Vector3(s * (fx + rng.randf_range(0.5, 1.6)), 0, lerpf(z0, z1, rng.randf_range(0.6, 0.95)) - i * 0.6), rng.randf_range(0.9, 1.2))
	# Raspberry canes growing through the fences onto the verge; the berries
	# hanging on them are the stage-1 collectibles (see Director).
	var bz := -10.0
	while bz > -330.0:
		var bside := -1 if rng.randf() < 0.5 else 1
		_add("raspberry", Vector3(bside * (fx - 0.35), 0, bz), rng.randf_range(0.65, 0.85))
		berry_spots.append(Vector3(bside * (fx - 0.55), 0, bz + rng.randf_range(-0.3, 0.3)))
		bz -= rng.randf_range(11.0, 22.0)
	# Copse behind the entrance gate, where the heroes come from.
	for i in 90:
		var x := rng.randf_range(-45.0, 45.0)
		if absf(x) < 4.0:
			x += signf(x) * 5.0 if x != 0.0 else 5.0
		_add(["birch", "spruce", "maple"][rng.randi_range(0, 2)], Vector3(x, 0, Street.START_Z + rng.randf_range(14.0, 70.0)), rng.randf_range(0.9, 1.3))
	# Tree belts behind the plots hide the horizon.
	for side: int in [-1, 1]:
		var z := Street.START_Z + 40.0
		while z > -Street.LENGTH - 80.0:
			for row in 3:
				var x := side * (fx + Street.PLOT_DEPTH + 4.0 + row * 9.0 + rng.randf_range(-3.0, 3.0))
				var sp: String = ["birch", "maple", "spruce", "birch", "spruce"][rng.randi_range(0, 4)]
				_add(sp, Vector3(x, 0, z + rng.randf_range(-3.0, 3.0)), rng.randf_range(0.9, 1.4))
			z -= rng.randf_range(7.0, 11.0)


func _commit_trees() -> void:
	for key: String in _instances:
		var sp := key.split("|")[0]
		var xforms: Array = _instances[key]
		var m: Dictionary = _meshes[sp]
		for part: String in ["trunk", "leaves", "leaves_far"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = m[part]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [key.replace("|", "_"), part]
			mmi.multimesh = mm
			mmi.material_override = m.bark if part == "trunk" else _leaf_mats[sp]
			if part == "leaves":
				mmi.visibility_range_end = LOD_DIST
				mmi.visibility_range_end_margin = 20.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif part == "leaves_far":
				mmi.visibility_range_begin = LOD_DIST
				mmi.visibility_range_begin_margin = 20.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
			multimesh_count += 1


# -------------------------------------------------------------------- grass

func _grass_clump_mesh(blades: int, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP)
		var h := height * rng.randf_range(0.6, 1.2)
		var w := rng.randf_range(0.008, 0.014)
		var lean := rng.randf_range(0.1, 0.35) * h
		var segs := 3
		var prev_l := off - side * w
		var prev_r := off + side * w
		for sgi in segs:
			var t := float(sgi + 1) / segs
			var c := off + Vector3(0, h * t, 0) + dir * lean * t * t
			var ww := w * (1.0 - t * 0.9)
			var l := c - side * ww
			var r := c + side * ww
			var n := (dir.cross(side) * -1.0 + dir * 0.3).normalized()
			var t0 := float(sgi) / segs
			for v: Array in [[prev_l, t0], [r, t], [prev_r, t0], [prev_l, t0], [l, t], [r, t]]:
				st.set_normal(n)
				st.set_uv(Vector2(0, v[1]))
				st.add_vertex(v[0])
			prev_l = l
			prev_r = r
	return st.commit()


func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stem.
	for v: Array in [[Vector3(-0.004, 0, 0), 0.0], [Vector3(0.004, 0.42, 0), 0.9], [Vector3(0.004, 0, 0), 0.0],
			[Vector3(-0.004, 0, 0), 0.0], [Vector3(-0.004, 0.42, 0), 0.9], [Vector3(0.004, 0.42, 0), 0.9]]:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0, v[1]))
		st.add_vertex(v[0])
	# Head: two crossed quads; UV.x >= 2 flags petals (shader cuts the flower shape).
	var c := Vector3(0, 0.44, 0)
	for k in 2:
		var u := Vector3(0.04, 0, 0) if k == 0 else Vector3(0, 0, 0.04)
		var v := Vector3(0, 0.012, 0.04) if k == 0 else Vector3(0.04, 0.012, 0)
		for q: Array in [[c - u - v, Vector2(0, 1)], [c + u + v, Vector2(1, 0)], [c + u - v, Vector2(1, 1)],
				[c - u - v, Vector2(0, 1)], [c - u + v, Vector2(0, 0)], [c + u + v, Vector2(1, 0)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(q[1] + Vector2(2, 0))
			st.add_vertex(q[0])
	return st.commit()


func _grass(street: Street) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS
	var fmat := ShaderMaterial.new()
	fmat.shader = GRASS
	fmat.set_shader_parameter("flower_mode", true)
	var clump := _grass_clump_mesh(9, 0.32)
	var tall := _grass_clump_mesh(6, 0.75)
	var flower := _flower_mesh()
	var palette := [Color(0.2, 0.32, 0.08), Color(0.25, 0.36, 0.1), Color(0.3, 0.38, 0.11), Color(0.42, 0.42, 0.18), Color(0.17, 0.28, 0.07)]
	var flower_cols := [Color(0.95, 0.85, 0.15), Color(0.95, 0.95, 0.92), Color(0.45, 0.55, 0.95), Color(0.85, 0.35, 0.6)]
	var z := Street.START_Z + 4.0
	while z > -Street.LENGTH:
		var short: Array = []
		var tall_x: Array = []
		var flowers: Array = []
		for zone: Array in [[-1, 2.75, Street.FENCE_X - 0.05, 30.0], [1, 2.75, Street.FENCE_X - 0.05, 30.0],
				[-1, Street.FENCE_X + 0.1, Street.FENCE_X + 7.0, 6.0], [1, Street.FENCE_X + 0.1, Street.FENCE_X + 7.0, 6.0]]:
			var side: int = zone[0]
			var x0: float = zone[1]
			var x1: float = zone[2]
			var count := int(GRASS_CHUNK * (x1 - x0) * float(zone[3]))
			for i in count:
				var x := side * rng.randf_range(x0, x1)
				var zz := z - rng.randf() * GRASS_CHUNK
				var near_fence := absf(x) > Street.FENCE_X - 0.5
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), Vector3(x, 0, zz))
				var col: Color = palette[rng.randi_range(0, palette.size() - 1)]
				if near_fence and rng.randf() < 0.35:
					tall_x.append([xf, col])
				else:
					short.append([xf, col])
				if rng.randf() < 0.04:
					flowers.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), Vector3(x, 0, zz)),
						flower_cols[rng.randi_range(0, flower_cols.size() - 1)]])
		for set: Array in [[clump, short, "grass", mat], [tall, tall_x, "weeds", mat], [flower, flowers, "flowers", fmat]]:
			_grass_chunk(set[0], set[1], set[3], "%s_%d" % [set[2], int(-z)])
		z -= GRASS_CHUNK


func _grass_chunk(mesh: Mesh, items: Array, mat: Material, nm: String) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 46.0
	mmi.visibility_range_end_margin = 4.0
	add_child(mmi)
	multimesh_count += 1
