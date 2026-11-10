extends SceneTree

## hello — Reachability (`GET /v1/models`) + Identity (`GET /v1/account/keys`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/hello.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()

	var models := client.get_models()
	if not bool(models.get("ok", false)):
		printerr("models failed: %s" % client.last_error)
		quit(1)
		return
	print("models   %d served by %s" % [int(models.get("count", 0)), client.base_url])

	var keys := client.get_account_keys()
	if not bool(keys.get("ok", false)):
		printerr("keys refused: %s" % client.last_error)
		quit(1)
		return

	var owned: Array = keys.get("keys", [])
	if owned.is_empty():
		print("the key is good, and it owns no keys of its own")
	else:
		for k in owned:
			if k is Dictionary:
				var kd := k as Dictionary
				print("%-8s %-24s %s" % [str(kd.get("type", "")), str(kd.get("prefix", "")), str(kd.get("created", ""))])
	quit(0)
