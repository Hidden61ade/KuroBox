class_name AudioService
extends Node

var volume: float = 0.65
var music_volume: float = 0.35
var muted: bool = false
var _voices: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _music: AudioStreamPlayer
const EVENTS := ["ui_confirm", "ui_back", "place", "undo", "punch", "goal"]

func _ready() -> void:
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for event: String in EVENTS:
		var path := "res://assets/audio/" + event + ".ogg"
		if ResourceLoader.exists(path):
			_streams[event] = load(path)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	if ResourceLoader.exists("res://assets/audio/music.ogg"):
		_music.stream = load("res://assets/audio/music.ogg").duplicate()
		_music.stream.loop = true
		_music.play()
	set_levels(volume, music_volume)

func set_levels(sound_level: float, music_level: float) -> void:
	volume = clampf(sound_level, 0.0, 1.0)
	music_volume = clampf(music_level, 0.0, 1.0)
	if is_instance_valid(_music):
		_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))

func set_muted(enabled: bool) -> void:
	muted = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), muted)

func play_event(event: String) -> void:
	if volume <= 0.0 or not _streams.has(event):
		return
	for voice: AudioStreamPlayer in _voices:
		if not voice.playing:
			voice.stream = _streams[event]
			voice.volume_db = linear_to_db(volume) - (5.0 if event == "place" else 0.0)
			voice.pitch_scale = 1.0
			voice.play()
			return

func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	stop_all()
	_streams.clear()
