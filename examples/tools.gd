extends SceneTree

## tools — Tool catalog (`GET /v1/tool`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/tools.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var res := client.list_tools()
	if not bool(res.get("ok", false)):
		printerr("tools failed: %s" % client.last_error)
		quit(1)
		return

	var listed: Array = res.get("tools", [])
	var shown := mini(listed.size(), 5)
	for i in range(shown):
		if listed[i] is Dictionary:
			var t := listed[i] as Dictionary
			print("%-32s %-12s %s" % [
				str(t.get("name", "")),
				str(t.get("source", "")),
				"activated" if bool(t.get("activated", false)) else "available",
			])
	print("%d tools" % listed.size())
	quit(0)
