extends SceneTree

## chat — One Zen 6 completion (`POST /v1/chat/completions`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/chat.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var model := OS.get_environment("HANZO_MODEL").strip_edges()
	if model.is_empty():
		model = HanzoClient.DEFAULT_CHAT_MODEL

	var reply := client.chat_text("Say hello from Godot in one short sentence.", "", model, 900, 0.7)
	if not bool(reply.get("ok", false)):
		printerr("chat failed: %s" % client.last_error)
		quit(1)
		return

	print("model    %s" % str(reply.get("model", "")))
	print("reply    %s" % str(reply.get("content", "")))
	quit(0)
