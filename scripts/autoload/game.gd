extends Node
## Global state: input map, shared noise texture, graphics quality, story progress.

signal berries_changed(count: int)
signal quality_changed(level: int)

enum Quality { MEDIUM, HIGH, ULTRA }

const QUALITY_NAMES := ["Средне", "Высоко", "Ультра"]

var quality: int = Quality.HIGH
var berries: int = 0
var flags := {}

var noise_texture: ImageTexture


func _enter_tree() -> void:
	_setup_input()
	_build_noise_texture()


func add_berries(n: int) -> void:
	berries += n
	berries_changed.emit(berries)


func set_quality(level: int) -> void:
	quality = clampi(level, Quality.MEDIUM, Quality.ULTRA)
	var shadow_size: int = [2048, 4096, 8192][quality]
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if quality == Quality.MEDIUM else Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 0.75 if quality == Quality.MEDIUM else 1.0
	get_viewport().use_taa = quality != Quality.MEDIUM
	quality_changed.emit(quality)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"interact": [KEY_E],
		"crouch": [KEY_C, KEY_CTRL],
		"pause": [KEY_ESCAPE],
		"fullscreen": [KEY_F11],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


## One seamless RGBA noise texture shared by every shader through the `g_noise` global.
## R: large fbm, G: fine fbm, B: cellular distance (cracks, stones), A: white-ish noise.
func _build_noise_texture() -> void:
	const SIZE := 512
	var layers: Array[Image] = []
	var specs := [
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 5, FastNoiseLite.RETURN_DISTANCE],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.06, 4, FastNoiseLite.RETURN_DISTANCE],
		[FastNoiseLite.TYPE_CELLULAR, 0.03, 1, FastNoiseLite.RETURN_DISTANCE2_SUB],
		[FastNoiseLite.TYPE_VALUE, 0.5, 1, FastNoiseLite.RETURN_DISTANCE],
	]
	for i in specs.size():
		var n := FastNoiseLite.new()
		n.seed = 1337 + i * 17
		n.noise_type = specs[i][0]
		n.frequency = specs[i][1]
		n.fractal_octaves = specs[i][2]
		n.fractal_type = FastNoiseLite.FRACTAL_FBM if specs[i][2] > 1 else FastNoiseLite.FRACTAL_NONE
		n.cellular_return_type = specs[i][3]
		layers.append(n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true))
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var r := layers[0].get_data()
	var g := layers[1].get_data()
	var b := layers[2].get_data()
	var a := layers[3].get_data()
	var bpp := r.size() / (SIZE * SIZE)
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	for p in SIZE * SIZE:
		data[p * 4] = r[p * bpp]
		data[p * 4 + 1] = g[p * bpp]
		data[p * 4 + 2] = b[p * bpp]
		data[p * 4 + 3] = a[p * bpp]
	out.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	noise_texture = ImageTexture.create_from_image(out)
	RenderingServer.global_shader_parameter_set("g_noise", noise_texture)
