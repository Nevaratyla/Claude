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
const COVER_CHUNK := 50.0

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
	"tomato": {"h": 1.3, "trunk_r": 0.015, "crown": "col", "cr": 0.3, "cbase": 0.1, "cards": 70, "card": 0.35,
		"tile": 5, "leaf": Color(0.2, 0.34, 0.1), "autumn": 0.0, "bark": 9, "branches": 3, "flex": 0.2},
	"cucumber": {"h": 1.6, "trunk_r": 0.01, "crown": "col", "cr": 0.25, "cbase": 0.05, "cards": 80, "card": 0.4,
		"tile": 0, "leaf": Color(0.22, 0.38, 0.1), "autumn": 0.0, "bark": 9, "branches": 2, "flex": 0.2},
	"potato": {"h": 0.5, "trunk_r": 0.01, "crown": "ell", "cr": 0.3, "cbase": 0.1, "cards": 40, "card": 0.25,
		"tile": 0, "leaf": Color(0.2, 0.33, 0.1), "autumn": 0.03, "bark": 9, "branches": 3, "flex": 0.3},
	"lilac": {"h": 2.4, "trunk_r": 0.04, "crown": "ell", "cr": 1.3, "cbase": 0.12, "cards": 200, "card": 0.7,
		"tile": 0, "leaf": Color(0.2, 0.33, 0.12), "autumn": 0.05, "bark": 9, "branches": 5, "flex": 0.3},
}

var rng := RandomNumberGenerator.new()
var _meshes := {}            # species -> {trunk: ArrayMesh, leaves: ArrayMesh}
var _instances := {}         # "species|chunk" -> Array[Transform3D]
var _bark_mats := {}
var _leaf_mats := {}
var multimesh_count := 0
var tree_count := 0
var burdock_spots: Array[Vector3] = []
var _grass_mmis: Array[MultiMeshInstance3D] = []
var _grass_mats: Array[ShaderMaterial] = []
var _near_leaves: Array[MultiMeshInstance3D] = []
var _far_leaves: Array[MultiMeshInstance3D] = []
var _cover: Array = []                       # [MultiMeshInstance3D, full draw distance]
var _lumps: Array = []


## Vine leaves and dark grape bunches on top of granny's pergola, with a few
## shoots hanging down the posts.
func _grape_canopy(pg: Dictionary) -> void:
	var c: Vector3 = pg.c
	var su: float = pg.su
	var sv: float = pg.sv
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 420:
		var hanging := i % 6 == 0
		var p := c + Vector3(rng.randf_range(-su, su) * 0.5, rng.randf_range(-0.05, 0.12), rng.randf_range(-sv, sv) * 0.55)
		if hanging:
			p.y -= rng.randf_range(0.2, 0.9)
		var n := (Vector3.UP + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))).normalized()
		if hanging:
			n = Vector3(rng.randf_range(-1, 1), 0.2, rng.randf_range(-1, 1)).normalized()
		var t := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
		var b := n.cross(t)
		var s := rng.randf_range(0.35, 0.55)
		var shade := rng.randf_range(0.85, 1.15)
		st.set_color(Color(0.24 * shade, 0.4 * shade, 0.12 * shade, 0.9))
		st.set_normal((n + Vector3.UP).normalized())
		var c0 := p - t * s * 0.5 - b * s * 0.5
		var corners := [[c0, Vector2(0, 1)], [c0 + t * s, Vector2(1, 1)], [c0 + t * s + b * s, Vector2(1, 0)], [c0 + b * s, Vector2(0, 0)]]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_uv(corners[k][1])
			st.add_vertex(corners[k][0])
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE
	mat.set_shader_parameter("tile", 5)                   # leaves with round fruit
	mat.set_shader_parameter("fruit_color", Color(0.2, 0.06, 0.24))
	mat.set_shader_parameter("autumn", 0.06)
	mat.set_shader_parameter("flex", 0.1)
	var mi := MeshInstance3D.new()
	mi.name = "GrapeVine"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _clear_of_garden(p: Dictionary, pos: Vector3, r: float) -> bool:
	if p.has("greenhouse") and Vector2(pos.x - p.greenhouse[0].x, pos.z - p.greenhouse[0].z).length() < p.greenhouse[1] * 0.5 + 1.5 + r:
		return false
	for b: Array in p.get("beds", []):
		if Vector2(pos.x - b[0].x, pos.z - b[0].z).length() < b[1] * 0.5 + r:
			return false
	return true


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
	_ground_cover(street)
	Game.quality_changed.connect(_apply_quality)
	Game.settings_changed.connect(_apply_quality)
	_apply_quality()


## Draw distances stay full by default, so nothing pops in near the camera.
## Only the "Экономная дальность" option (for very weak PCs) shortens them:
## grass closer and at half density, crowns switch to the light LOD sooner.
func _apply_quality(_q := 0) -> void:
	var saver := Game.lod_saver
	var grass_end := 24.0 if saver else 46.0
	for mat: ShaderMaterial in _grass_mats:
		mat.set_shader_parameter("fade_start", grass_end - 12.0)
		mat.set_shader_parameter("fade_end", grass_end - 2.0)
	for mmi: MultiMeshInstance3D in _grass_mmis:
		mmi.visibility_range_end = grass_end
		mmi.multimesh.visible_instance_count = int(mmi.multimesh.instance_count * (0.5 if saver else 1.0))
	var lod := 70.0 if saver else LOD_DIST
	for mmi: MultiMeshInstance3D in _near_leaves:
		mmi.visibility_range_end = lod
	for mmi: MultiMeshInstance3D in _far_leaves:
		mmi.visibility_range_begin = lod
	for item: Array in _cover:
		var mmi: MultiMeshInstance3D = item[0]
		mmi.visibility_range_end = float(item[1]) * (0.5 if saver else 1.0)
		mmi.visibility_range_end_margin = mmi.visibility_range_end * 0.15


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
		_cyl(trunk, pts[i], pts[i + 1], r0 * (1.0 - i * 0.28), r0 * (1.0 - (i + 1) * 0.28), 7)
	# Main branches from the crown base out toward the crown surface.
	for i in int(d.branches):
		var start := pts[1].lerp(pts[2], rng.randf())
		var end := _crown_point(d, h)
		end = crown_c + (end - crown_c) * 0.8
		_cyl(trunk, start, end, r0 * 0.35, r0 * 0.08, 5)
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
		# Granny's plot follows the sketch exactly: only its own trees, the vines.
		if p.get("granny", false):
			for t: Array in p.granny_trees:
				_add(t[0], t[1], t[2])
			_grape_canopy(p.pergola)
			continue
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
			_add("lilac", pos, rng.randf_range(0.8, 1.3))
		# Garden trees: every plot gets at least two, retrying until they fit.
		var trees := rng.randi_range(2, 5)
		var planted := 0
		for attempt in 16:
			if planted >= trees:
				break
			var pos := Vector3(s * (fx + rng.randf_range(3.0, Street.PLOT_DEPTH - 1.5)), 0, lerpf(z0 - 1.0, z1 + 1.0, rng.randf()))
			var sp: String = ["apple", "apple", "rowan", "birch", "maple", "spruce"][rng.randi_range(0, 5)]
			if free.call(pos, 2.0) and _clear_of_garden(p, pos, 2.0):
				_add(sp, pos, rng.randf_range(0.8, 1.2))
				planted += 1
		# Tomatoes and cucumbers in the greenhouse, potatoes on the beds.
		if p.has("greenhouse"):
			var gc: Vector3 = p.greenhouse[0]
			var gl: float = p.greenhouse[1]
			for row: float in [-0.6, 0.6]:
				var x := -gl * 0.5 + 0.4
				while x < gl * 0.5 - 0.3:
					_add("tomato" if row < 0.0 else "cucumber", gc + Vector3(x, 0, row), rng.randf_range(0.85, 1.1))
					x += 0.45
		for b: Array in p.get("beds", []):
			var bc: Vector3 = b[0]
			var bl: float = b[1]
			var bw: float = b[2]
			for row in 2:
				var rz := (row - 0.5) * bw * 0.5
				var x := -bl * 0.5 + 0.3
				while x < bl * 0.5 - 0.2:
					_add("potato", bc + Vector3(x, 0.12, rz), rng.randf_range(0.8, 1.2))
					x += 0.4
	# Burdocks on the verge are the stage-1 collectibles (see Director): a dense
	# run near the start, more than needed, so missing a few is no problem.
	var bz := -6.0
	while bz > -125.0:
		var bside := -1 if rng.randf() < 0.5 else 1
		burdock_spots.append(Vector3(bside * rng.randf_range(fx - 0.75, fx - 0.4), 0, bz))
		bz -= rng.randf_range(4.0, 6.5)
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
		# leaves_shadow: the sparse far crown, used only to cast the shadow of
		# nearby trees (4x fewer cards in the shadow pass, same look).
		for part: String in ["trunk", "leaves", "leaves_far", "leaves_shadow"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = m["leaves_far" if part == "leaves_shadow" else part]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [key.replace("|", "_"), part]
			mmi.multimesh = mm
			mmi.material_override = m.bark if part == "trunk" else _leaf_mats[sp]
			if part == "leaves" or part == "leaves_shadow":
				_near_leaves.append(mmi)
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part == "leaves" \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				mmi.visibility_range_end = LOD_DIST
				mmi.visibility_range_end_margin = 20.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif part == "leaves_far":
				_far_leaves.append(mmi)
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
	_grass_mats.append(mat)
	_grass_mats.append(fmat)
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
		# [side, x from, x to, clumps per m²]: the verges and the front of the yards.
		for zone: Array in [[-1, 2.75, Street.FENCE_X - 0.05, 30.0], [1, 2.75, Street.FENCE_X - 0.05, 30.0],
				[-1, Street.FENCE_X + 0.1, Street.FENCE_X + 7.0, 6.0], [1, Street.FENCE_X + 0.1, Street.FENCE_X + 7.0, 6.0]]:
			var side: int = zone[0]
			var x0: float = zone[1]
			var x1: float = zone[2]
			var count := int(GRASS_CHUNK * (x1 - x0) * float(zone[3]))
			for i in count:
				var x := side * rng.randf_range(x0, x1)
				var zz := z - rng.randf() * GRASS_CHUNK
				# Keep the collectible burdocks in the open, not buried in grass.
				if zz > -135.0 and _near_spot(x, zz, 0.7):
					continue
				var near_fence := absf(x) > Street.FENCE_X - 0.5
				var gy := street.height_at(x, zz) - 0.01
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), Vector3(x, gy, zz))
				var col: Color = palette[rng.randi_range(0, palette.size() - 1)]
				if near_fence and rng.randf() < 0.35:
					tall_x.append([xf, col])
				else:
					short.append([xf, col])
				if rng.randf() < 0.04:
					flowers.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.5)), Vector3(x, gy, zz)),
						flower_cols[rng.randi_range(0, flower_cols.size() - 1)]])
		for set: Array in [[clump, short, "grass", mat], [tall, tall_x, "weeds", mat], [flower, flowers, "flowers", fmat]]:
			_grass_chunk(set[0], set[1], set[3], "%s_%d" % [set[2], int(-z)])
		z -= GRASS_CHUNK


func _near_spot(x: float, z: float, r: float) -> bool:
	for sp in burdock_spots:
		if absf(sp.z - z) < r and absf(sp.x - x) < r:
			return true
	return false


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
	_grass_mmis.append(mmi)
	multimesh_count += 1


# ------------------------------------------------------------- ground cover

## Burdocks along the fences, plantain on the dirt road, stones and pebbles.
func _ground_cover(street: Street) -> void:
	var burdocks: Array[ArrayMesh] = []
	for i in 4:
		burdocks.append(Burdock.make_mesh(rng, rng.randi_range(7, 10), rng.randf_range(0.42, 0.6),
			Color(0.2, 0.32, 0.1), i >= 2))
	var plantain := Burdock.make_mesh(rng, 6, 0.13, Color(0.16, 0.26, 0.08), false, true)
	var stones: Array[ArrayMesh] = []
	for i in 3:
		stones.append(_stone_mesh())
	var stone_mat := StandardMaterial3D.new()
	stone_mat.vertex_color_use_as_albedo = true
	stone_mat.roughness = 0.88

	var fx := Street.FENCE_X
	var z := Street.START_Z + 4.0
	while z > -Street.LENGTH:
		var z1 := z - COVER_CHUNK
		var burd: Array = [[], [], [], []]
		var plant: Array = []
		var stone: Array = [[], [], []]
		# Burdocks: on the verge past the quest area, inside the yards near the fence everywhere.
		var bz := z
		while bz > z1:
			var side := -1 if rng.randf() < 0.5 else 1
			var inside := bz > -130.0 or rng.randf() < 0.4
			var x := side * (fx + rng.randf_range(0.3, 1.2) if inside else fx - rng.randf_range(0.35, 0.8))
			var y := street.height_at(x, bz) - 0.02
			burd[rng.randi_range(0, 3)].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), Vector3(x, y, bz)))
			bz -= rng.randf_range(3.0, 9.0)
		# Plantain and stones on the road; stones also on the gravel shoulder.
		for i in int(COVER_CHUNK * 9.0):
			var zz := z - rng.randf() * COVER_CHUNK
			var d := street.road.dirt_at(zz)
			var x := rng.randf_range(-2.9, 2.9)
			var ax := absf(x)
			var hw := street.road.half_width_at(zz)
			var on_road := ax < hw
			var y := street.height_at(x, zz)
			# Plantain pushes through the cracks along the broken asphalt edge.
			if on_road and ax > hw - 0.45 and rng.randf() < 0.3:
				plant.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), Vector3(x, y - 0.005, zz)))
			elif (on_road and d > 0.25 and rng.randf() < d * 1.6) or (not on_road and ax < 3.1):
				var size := rng.randf_range(0.015, 0.045) if rng.randf() < 0.85 else rng.randf_range(0.06, 0.12)
				var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(
					Vector3(size, size * rng.randf_range(0.5, 0.8), size * rng.randf_range(0.7, 1.1)))
				var g := rng.randf_range(0.38, 0.62)
				stone[rng.randi_range(0, 2)].append([Transform3D(b, Vector3(x, y - size * 0.25, zz)),
					Color(g, g * 0.97, g * 0.92)])
		for i in 4:
			_cover_mm(burdocks[i], burd[i], null, "burdock%d_%d" % [i, int(-z)], 120.0, true)
		_cover_mm(plantain, plant, null, "plantain_%d" % int(-z), 60.0, false)
		for i in 3:
			_cover_mm(stones[i], stone[i], stone_mat, "stones%d_%d" % [i, int(-z)], 50.0, false)
		z = z1


func _cover_mm(mesh: Mesh, items: Array, mat: Material, nm: String, vis_end: float, shadow: bool) -> void:
	if items.is_empty():
		return
	var colored: bool = items[0] is Array
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		if colored:
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		else:
			mm.set_instance_transform(i, items[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = vis_end * 0.1
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	_cover.append([mmi, vis_end])
	multimesh_count += 1


## Unit-size lumpy pebble: a low-poly sphere with jittered vertices.
func _stone_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 5
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var seed_off := rng.randf() * 100.0
	for i in verts.size():
		var v := verts[i]
		# Same jitter for duplicated seam vertices: derive it from the position.
		var k := 0.82 + 0.3 * (sin(v.x * 7.1 + seed_off) * sin(v.y * 5.3 + seed_off * 0.7) * sin(v.z * 6.7) * 0.5 + 0.5)
		verts[i] = v * k
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()
