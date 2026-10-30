extends Node
## Global state: input map, shared noise texture, graphics quality, story progress.

signal leaves_changed(count: int)
signal quality_changed(level: int)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const QUALITY_NAMES := ["Низко", "Средне", "Высоко", "Ультра"]
const SETTINGS_PATH := "user://settings.cfg"

var quality: int = Quality.HIGH
var leaves: int = 0
var flags := {}

var noise_texture: ImageTexture
var _fps_label: Label


func _enter_tree() -> void:
	_setup_input()
	_build_noise_texture()
	quality = _load_quality()


func add_leaves(n: int) -> void:
	leaves += n
	leaves_changed.emit(leaves)


## First launch: integrated GPUs (Intel/AMD APU in laptops) start on LOW,
## discrete cards on HIGH. After that the choice from the pause menu is kept.
func _load_quality() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("video", "quality"):
		return clampi(int(cfg.get_value("video", "quality")), Quality.LOW, Quality.ULTRA)
	var t := RenderingServer.get_video_adapter_type()
	if t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return Quality.HIGH
	return Quality.LOW


func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.ULTRA)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "quality", quality)
	cfg.save(SETTINGS_PATH)
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 8192][quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	var vp := get_viewport()
	# FSR 1 is a cheap upscaler that works well on integrated graphics.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if quality <= Quality.MEDIUM else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.77, 0.87, 1.0, 1.0][quality]
	vp.fsr_sharpness = 0.4
	vp.use_taa = quality >= Quality.HIGH
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality <= Quality.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0][quality]
	quality_changed.emit(quality)


## F3: frame-rate counter, to check how the game runs on your machine.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		if _fps_label == null:
			var layer := CanvasLayer.new()
			layer.layer = 20
			add_child(layer)
			_fps_label = Label.new()
			_fps_label.position = Vector2(12, 1040)
			_fps_label.add_theme_font_size_override("font_size", 18)
			_fps_label.add_theme_constant_override("outline_size", 4)
			_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
			layer.add_child(_fps_label)
			_fps_label.visible = false
		_fps_label.visible = not _fps_label.visible


func _process(_delta: float) -> void:
	if _fps_label and _fps_label.visible:
		_fps_label.text = "%d FPS · %s · %s" % [Engine.get_frames_per_second(), QUALITY_NAMES[quality],
			RenderingServer.get_video_adapter_name()]
		_fps_label.position.y = get_viewport().get_visible_rect().size.y - 34


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
