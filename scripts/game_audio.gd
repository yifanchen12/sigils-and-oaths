extends Node

const COUNCIL = preload("res://assets/audio/council.ogg")
const BATTLE = preload("res://assets/audio/battle.ogg")
const CUES: Dictionary = {
	"move": preload("res://assets/audio/move.wav"),
	"deploy": preload("res://assets/audio/deploy.wav"),
	"attack": preload("res://assets/audio/attack.wav"),
	"cast": preload("res://assets/audio/cast.wav"),
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

func set_levels(music_level: int, effects_level: int) -> void:
	_apply_bus("Music", music_level)
	_apply_bus("SFX", effects_level)

func _apply_bus(bus_name: String, percent: int) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, percent == 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, pow(percent / 100.0, 1.55))))

func set_battle_music(in_battle: bool) -> void:
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
	if not battle.last_trap_events.is_empty():
		_play("trap")
	elif action.get("combat", {}).get("intercepted", false):
		_play("guard")
	else:
		match str(action.type):
			"attack": _play("attack")
			"move": _play("move")
			"hero": _play("cast")
			"unit_skill":
				match str(action.get("unit_kind", "")):
					"sword", "spear": _play("guard")
					"cavalry": _play("move")
					"archer": _play("attack")
					_: _play("cast")
			"play":
				match str(action.get("card_type", "")):
					"unit": _play("deploy")
					"trap":
						if acting_side == 0: _play("trap")
					_: _play("cast")
			"end_turn":
				if battle.active_side == 0 and battle.winner == -1: _play("turn")
	if battle.winner != -1: _play("victory" if battle.winner == 0 else "defeat")

func _play(cue: String) -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")): return
	if sfx.get_child_count() >= 8: return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = CUES[cue]
	player.pitch_scale = randf_range(0.94, 1.05) if cue in ["move", "attack", "deploy"] else 1.0
	sfx.add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
