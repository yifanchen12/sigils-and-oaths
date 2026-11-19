extends Node

signal cue_started(cue: String)

const COUNCIL = preload("res://assets/audio/council.ogg")
const BATTLE = preload("res://assets/audio/battle.ogg")
const CastArt = preload("res://scripts/cast_art.gd")
const SKY_CUES := {"rain":"rainfall","snow":"snowfall","sun":"sunbreak","fog":"mistroll",
	"tailwind":"windrush","lanterns":"paperlights","clear":"clearair"}
const FIELD_CUES := {CastArt.Stroke.SHIELD:"guard", CastArt.Stroke.RIDE:"canter", CastArt.Stroke.ARROW:"bowstring",
	CastArt.Stroke.FIRE:"flare", CastArt.Stroke.LEAVES:"sprout", CastArt.Stroke.ICE:"rime"}
const CUES: Dictionary = {
	"move": preload("res://assets/audio/move.wav"),
	"deploy": preload("res://assets/audio/deploy.wav"),
	"attack": preload("res://assets/audio/attack.wav"),
	"cast": preload("res://assets/audio/cast.wav"),
	"bulwark": preload("res://assets/audio/bulwark.wav"),
	"comet": preload("res://assets/audio/comet.wav"),
	"willow": preload("res://assets/audio/willow.wav"),
	"canter": preload("res://assets/audio/canter.wav"),
	"bowstring": preload("res://assets/audio/bowstring.wav"),
	"rime": preload("res://assets/audio/rime.wav"),
	"sprout": preload("res://assets/audio/sprout.wav"),
	"flare": preload("res://assets/audio/flare.wav"),
	"rainfall": preload("res://assets/audio/rainfall.wav"),
	"snowfall": preload("res://assets/audio/snowfall.wav"),
	"sunbreak": preload("res://assets/audio/sunbreak.wav"),
	"mistroll": preload("res://assets/audio/mistroll.wav"),
	"windrush": preload("res://assets/audio/windrush.wav"),
	"paperlights": preload("res://assets/audio/paperlights.wav"),
	"clearair": preload("res://assets/audio/clearair.wav"),
	"guard": preload("res://assets/audio/guard.wav"),
	"trap": preload("res://assets/audio/trap.wav"),
	"turn": preload("res://assets/audio/turn.wav"),
	"victory": preload("res://assets/audio/victory.wav"),
	"defeat": preload("res://assets/audio/defeat.wav"),
}

var music_players: Array[AudioStreamPlayer] = []
var sfx: Node
var scene_index: int = -1
var fade: Tween
var stopping: bool = false

func _ready() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) >= 0: continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	for stream: AudioStreamOggVorbis in [COUNCIL, BATTLE]:
		stream.loop = true
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.stream = stream
		player.volume_linear = 0.0
		add_child(player)
		music_players.append(player)
	sfx = Node.new()
	add_child(sfx)

func _exit_tree() -> void:
	stop_playback()

func stop_playback() -> void:
	if stopping: return
	stopping = true
	if fade != null:
		fade.kill()
		fade = null
	for player: AudioStreamPlayer in music_players:
		player.stop()
	for player: AudioStreamPlayer in sfx.get_children():
		player.stop()
		player.queue_free()

func set_levels(music_level: int, effects_level: int) -> void:
	_apply_bus("Music", music_level)
	_apply_bus("SFX", effects_level)

func _apply_bus(bus_name: String, percent: int) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, percent == 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, pow(percent / 100.0, 1.55))))

func set_battle_music(in_battle: bool) -> void:
	if stopping: return
	var next: int = int(in_battle)
	if next == scene_index: return
	scene_index = next
	if fade != null: fade.kill()
	var incoming: AudioStreamPlayer = music_players[next]
	var outgoing: AudioStreamPlayer = music_players[1 - next]
	if DisplayServer.get_name() == "headless": return
	if not incoming.playing: incoming.play()
	fade = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(incoming, "volume_linear", 1.0, 0.68)
	fade.tween_property(outgoing, "volume_linear", 0.0, 0.68)
	fade.finished.connect(outgoing.stop)

func feedback(action: Dictionary, battle: Battle, acting_side: int) -> void:
	var style := CastArt.style_for(action)
	var stroke := CastArt.field_stroke(action, style)
	if not battle.last_trap_events.is_empty() and not battle.last_trap_events.any(func(event: Dictionary) -> bool: return event.triggered):
		_play("trap")
	elif action.get("combat", {}).get("intercepted", false):
		_play("guard")
	elif not battle.last_order_event.is_empty():
		_play("sprout" if battle.last_order_event.support else "attack")
	elif style == "weather_cast":
		_play(SKY_CUES[battle.weather])
	elif style == "fire_area":
		_play("attack" if action.has("cast_color") else "flare")
	elif FIELD_CUES.has(stroke):
		_play(FIELD_CUES[stroke])
	else:
		match str(action.type):
			"attack": _play("attack")
			"move": _play("move")
			"hero": _play({"blessing":"bulwark", "firestrike":"comet", "renewal":"willow"}.get(action.get("effect_kind"), "cast"))
			"unit_skill": _play("guard" if action.get("unit_kind") == "spear" else "cast")
			"play":
				match str(action.get("card_type", "")):
					"unit": _play("deploy")
					"trap":
						if acting_side == 0: _play("trap")
					_: _play("cast")
			"end_turn":
				if battle.active_side == 0 and battle.winner == -1: _play("turn")
	if battle.winner != -1: _play("victory" if battle.winner == 0 else "defeat")

func play_trap_contact() -> void:
	_play("trap")

func _play(cue: String) -> void:
	if stopping or DisplayServer.get_name() == "headless" or AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")): return
	if sfx.get_child_count() >= 8: return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = CUES[cue]
	player.pitch_scale = randf_range(0.94, 1.05) if cue in ["move", "attack", "deploy"] else 1.0
	sfx.add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
	cue_started.emit(cue)
