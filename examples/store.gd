extends SceneTree

## store — KV store lifecycle (`POST / GET / DELETE /v1/provisioning/kv`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/store.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var store_name := "godot-sdk-%08x" % rng.randi()

	var created := client.create_kv_store(store_name)
	if not bool(created.get("ok", false)) or not (created.get("json") is Dictionary):
		printerr("create kv failed: %s" % client.last_error)
		quit(1)
		return
	var cj := created["json"] as Dictionary
	print("created  %s (%s)" % [str(cj.get("name", store_name)), str(cj.get("status", ""))])

	var exit_code := 0
	var read_res := client.get_kv_store(store_name)
	if not bool(read_res.get("ok", false)) or not (read_res.get("json") is Dictionary):
		printerr("read kv failed: %s" % client.last_error)
		exit_code = 1
	else:
		var rj := read_res["json"] as Dictionary
		print("read     %s host=%s port=%s status=%s" % [
			str(rj.get("name", store_name)),
			str(rj.get("host", "")),
			str(rj.get("port", "")),
			str(rj.get("status", "")),
		])

	var del_res := client.delete_kv_store(store_name)
	if bool(del_res.get("ok", false)):
		print("deleted  %s" % store_name)
	else:
		printerr("delete kv failed: %s" % client.last_error)
		exit_code = 1

	quit(exit_code)
