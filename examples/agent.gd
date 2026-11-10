extends SceneTree

## agent — Create a budgeted cloud agent, run it, verify output, and delete it.
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/agent.gd

const RUNNING_STATES := ["queued", "pending", "running", "in_progress", "starting"]


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var agent_name := "godot-sdk-%08x" % rng.randi()
	var model := OS.get_environment("HANZO_MODEL").strip_edges()
	if model.is_empty():
		model = HanzoClient.DEFAULT_FAST_CHAT_MODEL

	var created := client.create_agent(
		agent_name,
		"You answer factual questions in one concise sentence.",
		model,
		1000000,
		250000,
		"month"
	)
	if not bool(created.get("ok", false)) or not (created.get("json") is Dictionary):
		printerr("create agent failed: %s" % client.last_error)
		quit(1)
		return
	var cj := created["json"] as Dictionary
	print("created  %s (%s)" % [str(cj.get("name", agent_name)), str(cj.get("id", ""))])

	var exit_code := 0
	var run_res := client.run_agent(agent_name, "What is the capital of Japan?")
	if not bool(run_res.get("ok", false)):
		printerr("run agent failed: %s" % client.last_error)
		exit_code = 1
	else:
		print("ran      %s" % agent_name)
		var rj: Dictionary = run_res["json"] as Dictionary if run_res.get("json") is Dictionary else {}
		var status := str(rj.get("status", ""))
		if not rj.is_empty() and not RUNNING_STATES.has(status):
			print("run      %s %s" % [str(rj.get("id", "")), status])
			print("output   %s" % str(rj.get("output", "")))
		else:
			var settled := false
			for _i in range(60):
				var list_res := client.get_agent_runs(agent_name, 5)
				if bool(list_res.get("ok", false)) and list_res.get("json") is Dictionary:
					var runs: Variant = (list_res["json"] as Dictionary).get("runs", [])
					if runs is Array and not (runs as Array).is_empty():
						var first: Dictionary = (runs as Array)[0]
						var st := str(first.get("status", ""))
						if not RUNNING_STATES.has(st):
							print("run      %s %s" % [str(first.get("id", "")), st])
							print("output   %s" % str(first.get("output", "")))
							settled = true
							break
				OS.delay_msec(1000)
			if not settled:
				printerr("agent run did not settle within 60s")
				exit_code = 1

	var del_res := client.delete_agent(agent_name)
	if bool(del_res.get("ok", false)):
		print("deleted  %s" % agent_name)
	quit(exit_code)
