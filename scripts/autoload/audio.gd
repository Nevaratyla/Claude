extends Node
## Sound: ambience with crossfades, one-shot effects (2D and positional) and
## looping sources attached to moving things. Streams are synthesised offline
## by tools/make_sounds.py.

const LOOPED := ["ambient_day", "ambient_evening", "engine_loop", "tires_loop", "heartbeat"]

var _streams := {}
var _ambient: Array[AudioStreamPlayer] = []
var _amb_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Two buses so the player can set ambience and effects separately.
	for bus in ["Ambient", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = "Ambient"
		add_child(p)
		_ambient.append(p)
	Game.settings_changed.connect(_apply_volumes)
	_apply_volumes()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear_to_db(maxf(Game.vol_ambient, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Game.vol_sfx, 0.0001)))


## Cached stream; looping clips are set to loop over their whole length.
func stream(sound: String) -> AudioStreamWAV:
	if not _streams.has(sound):
		var s: AudioStreamWAV = load("res://assets/sounds/%s.wav" % sound)
		if sound in LOOPED:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_streams[sound] = s
	return _streams[sound]


## Crossfades the background ambience to another loop.
func ambient(sound: String, volume_db := -8.0, fade := 3.0) -> void:
	var old := _ambient[_amb_index]
	_amb_index = 1 - _amb_index
	var new := _ambient[_amb_index]
	new.stream = stream(sound)
	new.volume_db = -60.0
	new.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(new, "volume_db", volume_db, fade)
	tw.tween_property(old, "volume_db", -60.0, fade)
	tw.chain().tween_callback(old.stop)


## Non-positional one-shot (UI, stings).
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = "SFX"
	add_child(p)
	p.play()
	if not sound in LOOPED:
		p.finished.connect(p.queue_free)
	return p


## Positional one-shot at a world point.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 3.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = unit_size
	p.bus = "SFX"
	p.max_distance = 60.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Looping positional source that follows `parent`.
func attach_loop(sound: String, parent: Node3D, volume_db := 0.0, unit_size := 6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.bus = "SFX"
	p.max_distance = 140.0
	parent.add_child(p)
	p.play()
	return p
