extends SceneTree

## game_backend — Complete serverless Godot 4 game backend powered by https://api.hanzo.ai:
##   1. Revisioned Cloud KV save-game & player progression (`/v1/kv/{bucket}/{key}` + `/history`)
##   2. Zero-output-token AI Director / NPC tactic via Kai (`POST /v1/decisions`, model `kai`)
##   3. State-grounded dynamic NPC dialogue via Zen 6 (`POST /v1/chat/completions`, model `zen6-flash`)
##   4. Playable spatial 3D voice synthesis via Zen Voice (`POST /v1/audio/speech`, model `zen-voice` -> `AudioStreamMP3`)
##   5. Bounded-budget Cloud Game Master agent (`POST /v1/agent` -> `/v1/agent/{ref}/run` -> `DELETE`)


func _initialize() -> void:
	randomize()
	var client := HanzoClient.from_env()
	if client.api_key.is_empty():
		printerr("HANZO_API_KEY is required")
		quit(1)
		return

	var suffix := "%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	var bucket := "godot_game_saves_" + suffix
	var exit_code := 0

	# 1. Create a revisioned Cloud KV bucket (keeps last 5 save revisions per slot)
	var b_res := client.create_kv_bucket(bucket, 5)
	if not bool(b_res.get("ok", false)):
		printerr("create_kv_bucket failed: ", client.last_error)
		quit(1)
		return

	# Write two checkpoints into slot_1 and verify revision history
	var save_v1 := {"player_id": "ranger_07", "zone": "outpost_alpha", "hp": 100, "ammo": 24, "threat_level": 0.25}
	var save_v2 := {"player_id": "ranger_07", "zone": "reactor_breach", "hp": 38, "ammo": 6, "threat_level": 0.85}
	client.put_kv(bucket, "slot_1", save_v1)
	var put_v2 := client.put_kv(bucket, "slot_1", save_v2)
	var loaded := client.get_kv(bucket, "slot_1")
	var hist := client.get_kv_history(bucket, "slot_1")
	if not bool(loaded.get("ok", false)) or not (loaded.get("data") is Dictionary):
		printerr("get_kv failed: ", client.last_error)
		client.delete_kv_bucket(bucket)
		quit(1)
		return

	var player_state := loaded["data"] as Dictionary
	print("1. cloud_save   bucket=%s rev=%d history_count=%d zone=%s hp=%s" % [
		bucket,
		int(put_v2.get("revision", 0)),
		int(hist.get("count", 0)),
		str(player_state.get("zone", "")),
		str(player_state.get("hp", 0)),
	])

	# 2. Zero-output-token AI Director / NPC decision from loaded save state via Kai
	var decision := client.decide_choice(
		player_state,
		{
			"dispatch_medevac": "send emergency supply drop when player hp < 45 in a high-threat zone",
			"spawn_ambush": "escalate encounter when player hp > 75 and ammo is plentiful",
			"hold_watch": "observe quietly when threat is low",
		},
		"Choose the Game Director action that keeps tension balanced for the current player save state."
	)
	if not bool(decision.get("ok", false)):
		printerr("decide_choice failed: ", client.last_error)
		exit_code = 1
	else:
		var usage: Dictionary = decision.get("usage", {}) if decision.get("usage") is Dictionary else {}
		print("2. kai_director choice=%s confidence=%.3f output_tokens=%d latency=%.1fms" % [
			str(decision.get("choice", "")),
			float(decision.get("confidence", 0.0)),
			int(usage.get("output_tokens", 0)),
			float(decision.get("latency_ms", 0.0)),
		])

	# 3. Dynamic Zen 6 radio transmission grounded in save state + Kai decision
	var chat := client.chat_text(
		"Player state: %s. Director action: %s. Transmit one terse radio sentence to the player." % [
			JSON.stringify(player_state),
			str(decision.get("choice", "dispatch_medevac")),
		],
		"Transmit a single concise tactical radio line in under 20 words.",
		"zen6-flash",
		300,
		0.3
	)
	var radio_line := str(chat.get("content", "")).strip_edges()
	if not bool(chat.get("ok", false)) or radio_line.is_empty():
		printerr("chat_text failed: ", client.last_error)
		exit_code = 1
	else:
		print("3. zen6_radio   (%s): %s" % [str(chat.get("model", "")), radio_line])

	# 4. Synthesize spatial 3D MP3 voice audio via Zen Voice and mount on HanzoAgent3D
	var tts := client.speech(radio_line if not radio_line.is_empty() else "Supply drop inbound to reactor breach.", "alloy", "zen-voice")
	var mp3 := tts.get("audio_stream") as AudioStreamMP3
	if not bool(tts.get("ok", false)) or mp3 == null:
		printerr("speech failed: ", client.last_error)
		exit_code = 1
	else:
		var npc_3d := HanzoAgent3D.new()
		npc_3d.auto_play_speech = false
		root.add_child(npc_3d)
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.stream = mp3
		npc_3d.add_child(player_3d)
		print("4. zen_voice_3d bytes=%d duration=%.2fs stream=%s" % [
			int(tts.get("bytes", 0)),
			mp3.get_length(),
			mp3.get_class(),
		])
		npc_3d.free()

	# 5. Clean up cloud save bucket
	var del_res := client.delete_kv_bucket(bucket)
	print("5. cleanup      deleted=%s status=%d" % [bucket, int(del_res.get("status", 0))])
	quit(exit_code)
