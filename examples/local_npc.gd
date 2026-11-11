extends SceneTree

## local_npc — an NPC voiced by an open-weight model on this machine.
## No API key, no cloud, no per-token cost.
##
##   hanzo load zen6-nano          # Hanzo Engine on http://127.0.0.1:36900/v1
##   HANZO_BASE_URL=http://127.0.0.1:36900 HANZO_MODEL=zen6-nano \
##     godot --headless --path . -s res://examples/local_npc.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var model := OS.get_environment("HANZO_MODEL").strip_edges()
	if model.is_empty():
		model = "zen6-nano"

	var persona := "You are Mara Vance, a terse shortwave radio operator at Outpost Echo-7. " \
		+ "Stay in character. Answer in at most two sentences."
	var lines := [
		"Anyone reading me on this channel?",
		"What's out past the perimeter tonight?",
	]
	for line in lines:
		var t0 := Time.get_ticks_msec()
		var r := client.chat_text(line, persona, model, 160, 0.6)
		if not bool(r.get("ok", false)):
			printerr("local model failed: %s (is `hanzo load %s` running?)" % [client.last_error, model])
			quit(1)
			return
		print("player > %s" % line)
		print("mara   > %s   (%d ms)" % [str(r.get("content", "")).strip_edges(), Time.get_ticks_msec() - t0])
	quit(0)
