class_name Road
extends Node3D
## The street floor between the fences as a real heightfield: old asphalt that
## gives way to stretches of dirt road with wheel ruts, bumps and potholes
## (puddles in the deep ones), a soil verge, and ground flush with the fences.
## Surface info goes to the ground shader through vertex colour:
## R carriageway, G dirt, B puddle, A rut.

const HALF := 4.0                 # mesh spans x in [-HALF, HALF] (fence to fence)
const DX := 0.2
const DZ := 0.5

var z_top := 0.0
var z_bottom := 0.0
var material: Material
var mesh_chunks := 0

var _dirt_segments: Array[Vector2] = []     # (z_start, z_end), z_start > z_end
var _potholes := {}                          # bucket (int) -> Array of [Vector2 xz, radius, depth, wet]
var _n_large := FastNoiseLite.new()
var _n_small := FastNoiseLite.new()
var _n_edge := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _tmp := PackedFloat32Array([0.0])


func _init() -> void:
	_n_large.seed = 11
	_n_large.frequency = 0.03
	_n_small.seed = 12
	_n_small.frequency = 0.55
	_n_small.fractal_octaves = 2
	_n_edge.seed = 13
	_n_edge.frequency = 0.12


func build(top: float, bottom: float, mat: Material) -> void:
	z_top = top
	z_bottom = bottom
	material = mat
	_rng.seed = 9090
	_layout()
	_build_mesh()


# ------------------------------------------------------------------- layout

func _layout() -> void:
	# The entrance is asphalt (like the reference photo); further on the road
	# alternates between worn asphalt and dirt.
	# A first short dirt stretch right where the leaf quest happens.
	_dirt_segments.append(Vector2(-18.0, -52.0))
	var z := -52.0
	while z > z_bottom:
		var asphalt := _rng.randf_range(35.0, 80.0)
		var dirt := _rng.randf_range(22.0, 55.0)
		_dirt_segments.append(Vector2(z - asphalt, z - asphalt - dirt))
		z -= asphalt + dirt
	# Potholes: more and deeper on dirt stretches.
	z = z_top - 5.0
	while z > z_bottom + 5.0:
		var d := dirt_at(z)
		if _rng.randf() < 0.25 + d * 0.6:
			var p := Vector2(_rng.randf_range(-1.9, 1.9), z)
			var r := _rng.randf_range(0.25, 0.75) * (1.0 + d * 0.4)
			var depth := _rng.randf_range(0.03, 0.06) + d * _rng.randf_range(0.0, 0.05)
			var wet := depth > 0.055 and _rng.randf() < 0.7
			var bucket := floori(p.y / 10.0)
			if not _potholes.has(bucket):
				_potholes[bucket] = []
			_potholes[bucket].append([p, r, depth, wet])
		z -= _rng.randf_range(1.5, 5.0)


## 0 = asphalt, 1 = dirt road, smooth 8 m transitions.
func dirt_at(z: float) -> float:
	var d := 0.0
	for s in _dirt_segments:
		if z < s.x + 8.0 and z > s.y - 8.0:
			var a := clampf((s.x + 8.0 - z) / 8.0, 0.0, 1.0)
			var b := clampf((z - (s.y - 8.0)) / 8.0, 0.0, 1.0)
			d = maxf(d, minf(a, b))
	return d


func half_width_at(z: float) -> float:
	return 2.3 + _n_edge.get_noise_1d(z) * 0.25


## Height and surface mask at a point. Returns Color(road, dirt, puddle, rut)
## and writes the height into out[0] (avoids allocating in the hot loop).
func sample(x: float, z: float, out: PackedFloat32Array) -> Color:
	var ax := absf(x)
	var hw := half_width_at(z)
	var road := 1.0 - smoothstep(hw - 0.15, hw + 0.15, ax)
	var dirt := dirt_at(z)
	var t := clampf(ax / hw, 0.0, 1.0)
	var h := 0.0
	# Asphalt slab sits a few cm above the soil; dirt road is level with it.
	h += road * lerpf(0.04, 0.01, dirt)
	h += road * 0.025 * (1.0 - t * t)                                   # crown
	h += _n_large.get_noise_2d(x, z) * 0.07                              # long waves
	var bumps := _n_small.get_noise_2d(x, z)
	h += bumps * lerpf(0.012, 0.035, dirt) * road
	# Wheel ruts and the grassy hump between them.
	var rut := exp(-pow((ax - 0.85) / 0.22, 2.0)) * dirt * road
	h -= 0.045 * rut
	h += 0.018 * dirt * road * exp(-pow(x / 0.35, 2.0))
	# Verge: uneven soil.
	h += (1.0 - road) * (0.02 + bumps * 0.025)
	# Potholes.
	var puddle := 0.0
	var bucket := floori(z / 10.0)
	for b in [bucket - 1, bucket, bucket + 1]:
		if not _potholes.has(b):
			continue
		for ph: Array in _potholes[b]:
			var c: Vector2 = ph[0]
			var r: float = ph[1]
			var dist := Vector2(x - c.x, z - c.y).length()
			if dist < r:
				var k := 1.0 - (dist / r) * (dist / r)
				h -= float(ph[2]) * k * (1.5 - 0.5 * k)
				if ph[3]:
					puddle = maxf(puddle, smoothstep(0.25, 0.55, k))
	# Flush with the flat yards at the fences and at both ends of the strip.
	h *= 1.0 - smoothstep(3.55, 3.95, ax)
	h *= clampf((z_top - z) / 3.0, 0.0, 1.0) * clampf((z - z_bottom) / 3.0, 0.0, 1.0)
	out[0] = h
	return Color(road, dirt, puddle, rut)


func height_at(x: float, z: float) -> float:
	sample(x, z, _tmp)
	return _tmp[0]


# --------------------------------------------------------------------- mesh

func _build_mesh() -> void:
	var cols := int(round(HALF * 2.0 / DX)) + 1
	var rows_total := int(ceil((z_top - z_bottom) / DZ)) + 1
	var rows_per_chunk := int(MeshKit.CHUNK_LEN / DZ)
	# Sample the whole grid once.
	var heights := PackedFloat32Array()
	heights.resize(cols * rows_total)
	var colors := PackedColorArray()
	colors.resize(cols * rows_total)
	var out := PackedFloat32Array([0.0])
	for j in rows_total:
		var z := z_top - j * DZ
		for i in cols:
			var x := -HALF + i * DX
			colors[j * cols + i] = sample(x, z, out)
			heights[j * cols + i] = out[0]

	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	add_child(body)
	var j0 := 0
	while j0 < rows_total - 1:
		var j1 := mini(j0 + rows_per_chunk, rows_total - 1)
		_chunk(j0, j1, cols, heights, colors, body)
		j0 = j1


func _chunk(j0: int, j1: int, cols: int, heights: PackedFloat32Array, colors: PackedColorArray, body: StaticBody3D) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols_out := PackedColorArray()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var idx := PackedInt32Array()
	var rows := j1 - j0 + 1
	for j in range(j0, j1 + 1):
		var z := z_top - j * DZ
		for i in cols:
			var x := -HALF + i * DX
			var k := j * cols + i
			verts.append(Vector3(x, heights[k], z))
			# Central differences (clamped at the borders).
			var hl := heights[j * cols + maxi(i - 1, 0)]
			var hr := heights[j * cols + mini(i + 1, cols - 1)]
			var hu := heights[maxi(j - 1, 0) * cols + i]
			var hd := heights[mini(j + 1, heights.size() / cols - 1) * cols + i]
			normals.append(Vector3((hl - hr) / (2.0 * DX), 1.0, (hd - hu) / (2.0 * DZ)).normalized())
			cols_out.append(colors[k])
			uvs.append(Vector2(x, z))
			# Tangent along +X (the U direction) so detail normal maps work.
			var nrm := normals[normals.size() - 1]
			var tan := (Vector3.RIGHT - nrm * nrm.x).normalized()
			tangents.append_array([tan.x, tan.y, tan.z, 1.0])
	for j in rows - 1:
		for i in cols - 1:
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			# Godot front faces are clockwise; seen from above a-b-d-c runs
			# counter-clockwise, so emit the reverse.
			idx.append_array([a, d, b, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols_out
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "RoadChunk_%d" % j0
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mesh_chunks += 1
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
