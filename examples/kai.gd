extends SceneTree

## kai — Structured zero-output-token game AI decision (`POST /v1/decisions`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/kai.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var res := client.decide_choice(
		{
			"npc_id": "stalker_01",
			"health_pct": 0.78,
			"ammo": 12,
			"player_visible": true,
			"distance_m": 9.4,
		},
		{
			"patrol": "continue along patrol route when no threat is present",
			"investigate": "search last known sound location cautiously",
			"engage": "press attack when target is visible and health/ammo are sufficient",
			"retreat": "break line of sight when critically wounded or out of ammo",
		},
		"Choose the best immediate tactical action for this 3D NPC."
	)
	if not bool(res.get("ok", false)):
		printerr("kai failed: %s" % client.last_error)
		quit(1)
		return

	print("model    %s" % str(res.get("model", "")))
	print("choice   %s (confidence %.3f)" % [str(res.get("choice", "")), float(res.get("confidence", 0.0))])
	print("latency  %.1f ms" % float(res.get("latency_ms", 0.0)))
	quit(0)
