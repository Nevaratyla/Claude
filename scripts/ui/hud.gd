class_name Hud
extends CanvasLayer
## Everything on screen: story cards, objective, berry counter, subtitles,
## interaction prompt, pause menu. Built in code to keep the project text-only.

signal resumed

const NAME_COLORS := {"Бусик": Color(0.55, 0.72, 1.0), "Фиалка": Color(0.85, 0.6, 1.0)}

var fade: ColorRect
var card: Label
var objective_box: PanelContainer
var objective: Label
var berry_box: PanelContainer
var berry_label: Label
var subtitle_box: PanelContainer
var subtitle: RichTextLabel
var prompt: Label
var hint: Label
var pause_menu: Control
var _quality_btn: Button
var _sub_serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)

	objective_box = _panel(root, Control.PRESET_TOP_LEFT, Vector2(28, 24))
	var ov := VBoxContainer.new()
	objective_box.add_child(ov)
	var ot := Label.new()
	ot.text = "ЗАДАНИЕ"
	ot.add_theme_font_size_override("font_size", 15)
	ot.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	ov.add_child(ot)
	objective = Label.new()
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size = Vector2(380, 0)
	ov.add_child(objective)
	objective_box.modulate.a = 0.0

	berry_box = _panel(root, Control.PRESET_TOP_RIGHT, Vector2(-28, 24))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	berry_box.add_child(bh)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.75, 0.08, 0.14)
	dsb.set_corner_radius_all(11)
	dsb.border_color = Color(1, 0.6, 0.6, 0.6)
	dsb.set_border_width_all(2)
	dot.add_theme_stylebox_override("panel", dsb)
	bh.add_child(dot)
	berry_label = Label.new()
	berry_label.text = "0"
	bh.add_child(berry_label)
	berry_box.modulate.a = 0.0

	subtitle_box = PanelContainer.new()
	subtitle_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_box.position.y -= 90
	subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle_box)
	subtitle = RichTextLabel.new()
	subtitle.bbcode_enabled = true
	subtitle.fit_content = true
	subtitle.custom_minimum_size = Vector2(760, 0)
	subtitle.scroll_active = false
	subtitle.add_theme_font_size_override("normal_font_size", 24)
	subtitle.add_theme_font_size_override("bold_font_size", 24)
	subtitle_box.add_child(subtitle)
	subtitle_box.modulate.a = 0.0

	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y += 120
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.visible = false
	root.add_child(prompt)

	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(28, -28)
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hint.modulate.a = 0.0
	root.add_child(hint)

	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	card = Label.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_theme_font_size_override("font_size", 30)
	card.add_theme_constant_override("line_spacing", 10)
	card.modulate.a = 0.0
	root.add_child(card)

	_build_pause(root)
	Game.berries_changed.connect(func(n: int) -> void: berry_label.text = str(n))


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", Color(0.97, 0.96, 0.93))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	t.set_color("default_color", "RichTextLabel", Color(0.97, 0.96, 0.93))
	t.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "RichTextLabel", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.55)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.12, 0.14, 0.2, 0.9)
	bn.set_corner_radius_all(8)
	bn.content_margin_left = 20
	bn.content_margin_right = 20
	bn.content_margin_top = 10
	bn.content_margin_bottom = 10
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = Color(0.25, 0.3, 0.45, 0.95)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("focus", "Button", bh)
	t.set_stylebox("pressed", "Button", bh)
	t.set_font_size("font_size", "Button", 22)
	return t


func _panel(root: Control, preset: int, offset: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	if preset == Control.PRESET_TOP_RIGHT:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.position += offset
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p


func _build_pause(root: Control) -> void:
	pause_menu = ColorRect.new()
	(pause_menu as ColorRect).color = Color(0, 0, 0, 0.55)
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	root.add_child(pause_menu)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	pause_menu.add_child(box)
	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var cont := Button.new()
	cont.text = "Продолжить"
	cont.pressed.connect(func() -> void: set_paused(false))
	box.add_child(cont)
	_quality_btn = Button.new()
	_quality_btn.pressed.connect(func() -> void:
		Game.set_quality((Game.quality + 1) % Game.QUALITY_NAMES.size())
		_quality_btn.text = "Графика: " + Game.QUALITY_NAMES[Game.quality])
	_quality_btn.text = "Графика: " + Game.QUALITY_NAMES[Game.quality]
	box.add_child(_quality_btn)
	var fs := Button.new()
	fs.text = "Полный экран (F11)"
	fs.pressed.connect(toggle_fullscreen)
	box.add_child(fs)
	var quit := Button.new()
	quit.text = "Выйти из игры"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	var help := Label.new()
	help.text = "WASD — идти · Shift — бежать · Пробел — прыжок · C — красться\nE — действие · мышь — камера · колесо — приблизить · F3 — FPS"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 16)
	box.add_child(help)


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func set_paused(p: bool) -> void:
	get_tree().paused = p
	pause_menu.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if not p:
		resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
	elif event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ helpers

func fade_to(alpha: float, time := 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, time)
	await tw.finished


func show_card(text: String, hold := 3.5) -> void:
	card.text = text
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.8)
	tw.tween_interval(hold)
	tw.tween_property(card, "modulate:a", 0.0, 0.8)
	await tw.finished


func set_objective(text: String) -> void:
	objective.text = text
	var tw := create_tween()
	tw.tween_property(objective_box, "modulate:a", 0.0 if text == "" else 1.0, 0.5)


## Updates the objective text without the fade (for live counters).
func set_objective_text(text: String) -> void:
	objective.text = text


func show_berries(on: bool) -> void:
	create_tween().tween_property(berry_box, "modulate:a", 1.0 if on else 0.0, 0.5)


func say(speaker: String, text: String, time := 0.0) -> void:
	_sub_serial += 1
	var serial := _sub_serial
	var col: Color = NAME_COLORS.get(speaker, Color.WHITE)
	subtitle.text = "[b][color=#%s]%s:[/color][/b] %s" % [col.to_html(false), speaker, text]
	create_tween().tween_property(subtitle_box, "modulate:a", 1.0, 0.25)
	if time <= 0.0:
		time = 1.6 + text.length() * 0.055
	await get_tree().create_timer(time).timeout
	if serial == _sub_serial:
		create_tween().tween_property(subtitle_box, "modulate:a", 0.0, 0.4)


func show_hint(text: String, time := 9.0) -> void:
	hint.text = text
	var tw := create_tween()
	tw.tween_property(hint, "modulate:a", 1.0, 0.6)
	tw.tween_interval(time)
	tw.tween_property(hint, "modulate:a", 0.0, 1.0)


func set_prompt(text: String) -> void:
	prompt.visible = text != ""
	prompt.text = text
