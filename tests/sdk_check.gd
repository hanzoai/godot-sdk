extends SceneTree

## Hanzo Godot SDK verification suite (`tests/sdk_check.gd`).
## Verifies offline wire/scene invariants AND full live game-backend integration
## against `https://api.hanzo.ai` when `HANZO_API_KEY` is present:
##   1. URL normalization, default configuration, Bearer + X-Org-Id + budget headers, public-route isolation
##   2. HanzoAgent3D node lifecycle, child AudioStreamPlayer3D creation & reuse, async WorkerThreadPool signals
##   3. Live `GET /v1/models` (`zen6`, `zen6-flash`, `zen6-coder`, `zen6-max`, `kai`, `zen-voice`)
##   4. Live `GET /v1/account/keys` (401/403 on invalid key, 200 on valid key) & `GET /v1/billing/*`
##   5. Live Cloud KV Game-Save lifecycle (`POST /v1/kv/{bucket}`, `PUT`/`GET` JSON revisions, `/history`, `DELETE`)
##   6. Live Kai decision (`POST /v1/decisions` — calibrated probabilities, confidence in [0,1], 0 output tokens)
##   7. Live Zen 6 chat (`POST /v1/chat/completions` on `zen6-flash` and `zen6`)
##   8. Live Zen Voice TTS (`POST /v1/audio/speech` -> playable `AudioStreamMP3` with positive duration)
##   9. Live Cloud Agent lifecycle (`POST /v1/agent` -> `POST /v1/agent/{ref}/run` -> `DELETE /v1/agent/{ref}`)
##  10. Live Cloud MCP (`POST /v1/mcp` `initialize` `2026-07-28` + `tools/list` + `GET /v1/tool`)

var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s" % label)


func _initialize() -> void:
	randomize()
	# 1. Offline wire & config checks
	var c_default := HanzoClient.new("", "", "")
	if OS.get_environment("HANZO_BASE_URL").is_empty() and OS.get_environment("HANZO_API_URL").is_empty():
		_check(c_default.base_url == "https://api.hanzo.ai", "default base_url is https://api.hanzo.ai")
	_check(c_default.default_chat_model == "zen6", "default chat model is zen6")
	_check(c_default.default_decision_model == "kai", "default decision model is kai")
	_check(c_default.default_voice_model == "zen-voice", "default voice model is zen-voice")
	_check(c_default.timeout_ms >= 60000, "timeout_ms accommodates reasoning models")

	var c_norm := HanzoClient.new("hk-unit", "https://api.hanzo.ai/v1/", "acme")
	_check(c_norm.base_url == "https://api.hanzo.ai", "strips trailing /v1/ from base_url")
	var c_plain := HanzoClient.new("hk-unit", "https://api.hanzo.ai/", "")
	_check(c_plain.base_url == "https://api.hanzo.ai", "strips trailing slash from base_url")

	var hdrs_auth := Array(c_norm.build_headers("api.hanzo.ai", "application/json", true, {"X-Max-Cost": "0.25", "X-Max-Latency-Ms": "2000"}))
	_check(hdrs_auth.has("Authorization: Bearer hk-unit"), "sends Bearer header")
	_check(hdrs_auth.has("X-Org-Id: acme"), "sends X-Org-Id header")
	_check(hdrs_auth.has("Content-Type: application/json"), "sends Content-Type header")
	_check(hdrs_auth.has("X-Max-Cost: 0.25"), "sends custom X-Max-Cost header")
	_check(hdrs_auth.has("X-Max-Latency-Ms: 2000"), "sends custom X-Max-Latency-Ms header")

	var hdrs_public := Array(c_norm.build_headers("api.hanzo.ai", "", false))
	var leaked_auth := false
	var leaked_ct := false
	for h in hdrs_public:
		if str(h).begins_with("Authorization:") or str(h).begins_with("X-Org-Id:"):
			leaked_auth = true
		if str(h).begins_with("Content-Type:"):
			leaked_ct = true
	_check(not leaked_auth, "omits credentials on public routes (security: [])")
	_check(not leaked_ct, "omits empty Content-Type on bodyless GET routes")

	# 2. HanzoAgent3D node checks (auto-creation, existing AudioStreamPlayer3D reuse, silent mode)
	var agent_node := HanzoAgent3D.new()
	root.add_child(agent_node)
	agent_node._ready()
	_check(agent_node.chat_model == "zen6", "HanzoAgent3D defaults to zen6")
	_check(agent_node.decision_model == "kai", "HanzoAgent3D defaults to kai")
	_check(agent_node.voice_model == "zen-voice", "HanzoAgent3D defaults to zen-voice")
	_check(agent_node.audio_player != null and agent_node.audio_player.name == "HanzoVoice3D", "HanzoAgent3D creates HanzoVoice3D AudioStreamPlayer3D")
	agent_node.free()

	var custom_agent := HanzoAgent3D.new()
	var custom_speaker := AudioStreamPlayer3D.new()
	custom_speaker.name = "CustomHelmetRadio"
	custom_agent.add_child(custom_speaker)
	root.add_child(custom_agent)
	custom_agent._ready()
	_check(custom_agent.audio_player == custom_speaker, "HanzoAgent3D reuses pre-existing AudioStreamPlayer3D child")
	custom_agent.free()

	var silent_agent := HanzoAgent3D.new()
	silent_agent.auto_play_speech = false
	root.add_child(silent_agent)
	silent_agent._ready()
	_check(silent_agent.audio_player == null, "HanzoAgent3D skips AudioStreamPlayer3D when auto_play_speech is false")
	silent_agent.free()

	# 3a. Local open-weight model (HANZO_BASE_URL on localhost, e.g. `hanzo load zen6-nano`)
	var local_client := HanzoClient.from_env()
	var lb := local_client.base_url.to_lower()
	if OS.get_environment("HANZO_OFFLINE") != "1" and (lb.begins_with("http://127.0.0.1") or lb.begins_with("http://localhost")):
		var local_model := OS.get_environment("HANZO_MODEL").strip_edges()
		if local_model.is_empty():
			local_model = "zen6-nano"
		print("Running local open-weight checks against %s (%s)..." % [local_client.base_url, local_model])
		var lm := local_client.get_models()
		_check(bool(lm.get("ok", false)) and (lm.get("models", []) as Array).has(local_model), "local GET /v1/models lists %s" % local_model)
		var lc := local_client.chat_text("Reply with exactly: LOCAL_OK", "", local_model, 64, 0.0)
		_check(bool(lc.get("ok", false)) and str(lc.get("content", "")).contains("LOCAL_OK"), "local POST /v1/chat/completions follows instructions")
		var li := local_client.chat_text("Who are you? One sentence.", "", local_model, 120, 0.0)
		_check(bool(li.get("ok", false)) and str(li.get("content", "")).contains("Zen"), "local model identifies as Zen")

	# 3. Live gateway & game-backend checks (when HANZO_API_KEY is present and HANZO_OFFLINE != 1)
	var live_client := HanzoClient.from_env()
	if OS.get_environment("HANZO_OFFLINE") != "1" and not live_client.api_key.is_empty():
		print("Running live api.hanzo.ai game-backend checks...")

		# 3a. Catalog & Zen 6 family discovery
		var models := live_client.get_models()
		_check(bool(models.get("ok", false)), "live GET /v1/models HTTP 200")
		var model_ids: Array = models.get("models", [])
		_check(model_ids.size() > 50, "live catalog serves >50 models")
		_check(model_ids.has("zen6"), "catalog includes zen6")
		_check(model_ids.has("zen6-flash"), "catalog includes zen6-flash")
		_check(model_ids.has("zen6-coder"), "catalog includes zen6-coder")
		_check(model_ids.has("zen6-max"), "catalog includes zen6-max")
		_check(model_ids.has("kai"), "catalog includes kai")
		_check(model_ids.has("zen-voice"), "catalog includes zen-voice")

		# 3b. Auth & Billing checks
		var bad_client := HanzoClient.new("hk-invalid-probe-token", live_client.base_url)
		var bad_keys := bad_client.get_account_keys()
		_check(not bool(bad_keys.get("ok", false)) and int(bad_keys.get("status", 0)) in [401, 403], "GET /v1/account/keys refuses bad token")

		var ok_keys := live_client.get_account_keys()
		_check(bool(ok_keys.get("ok", false)), "live GET /v1/account/keys accepts valid token")

		var bal := live_client.get_billing_balance()
		_check(bool(bal.get("ok", false)) and (bal.get("json") is Dictionary), "live GET /v1/billing/balance returns JSON")
		var usage_res := live_client.get_billing_usage()
		_check(bool(usage_res.get("ok", false)), "live GET /v1/billing/usage returns 200")

		# 3c. Cloud KV Game-Save & Revision History round-trip
		var bucket := "godot_sdk_test_%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
		var b_create := live_client.create_kv_bucket(bucket, 3)
		_check(bool(b_create.get("ok", false)), "live POST /v1/kv/{bucket} creates save bucket")

		var p1 := live_client.put_kv(bucket, "save_slot_1", {"zone": "sector_1", "hp": 100, "score": 250})
		_check(bool(p1.get("ok", false)) and int(p1.get("revision", 0)) == 1, "live PUT /v1/kv/{bucket}/{key} writes rev 1")

		var p2 := live_client.put_kv(bucket, "save_slot_1", {"zone": "sector_2", "hp": 64, "score": 900, "inventory": ["medkit", "flare"]})
		_check(bool(p2.get("ok", false)) and int(p2.get("revision", 0)) == 2, "live PUT /v1/kv/{bucket}/{key} writes rev 2")

		var g_save := live_client.get_kv(bucket, "save_slot_1")
		var save_dict: Dictionary = g_save.get("data", {}) if g_save.get("data") is Dictionary else {}
		_check(bool(g_save.get("ok", false))
			and int(g_save.get("revision", 0)) == 2
			and str(save_dict.get("zone", "")) == "sector_2"
			and int(save_dict.get("score", 0)) == 900,
			"live GET /v1/kv/{bucket}/{key} parses latest JSON save state")

		var hist := live_client.get_kv_history(bucket, "save_slot_1")
		_check(bool(hist.get("ok", false)) and int(hist.get("count", 0)) == 2, "live GET /v1/kv/{bucket}/{key}/history returns both revisions")

		var d_key := live_client.delete_kv(bucket, "save_slot_1")
		_check(bool(d_key.get("ok", false)), "live DELETE /v1/kv/{bucket}/{key} succeeds")

		var d_bucket := live_client.delete_kv_bucket(bucket)
		_check(bool(d_bucket.get("ok", false)), "live DELETE /v1/kv/{bucket} cleans up bucket")

		var g_after := live_client.get_kv(bucket, "save_slot_1")
		_check(not bool(g_after.get("ok", false)) and int(g_after.get("status", 0)) == 404, "GET /v1/kv after delete returns 404")

		# 3d. Kai zero-output-token tactical decision
		var dec := live_client.decide_choice(
			{"hp": 92, "ammo": 18, "threat_visible": true, "distance_m": 4.0},
			{"hold": "stay passive when no threat is visible", "engage": "engage visible close-range threat while healthy"},
			"Choose the NPC combat action."
		)
		var dec_usage: Dictionary = dec.get("usage", {}) if dec.get("usage") is Dictionary else {}
		var dec_probs: Dictionary = dec.get("probabilities", {}) if dec.get("probabilities") is Dictionary else {}
		_check(bool(dec.get("ok", false)) and str(dec.get("choice", "")) == "engage", "live POST /v1/decisions (kai) selects engage")
		_check(float(dec.get("confidence", -1.0)) >= 0.0 and float(dec.get("confidence", 2.0)) <= 1.0 and dec_probs.size() == 2, "Kai returns calibrated confidence and probability distribution")
		_check(int(dec_usage.get("output_tokens", -1)) == 0, "Kai decision uses 0 output tokens")

		# 3e. Zen 6 Chat (`zen6-flash` and flagship `zen6`)
		var chat_flash := live_client.chat_text("Reply with exact word: FLASH_OK", "", "zen6-flash", 200, 0.0)
		_check(bool(chat_flash.get("ok", false)) and str(chat_flash.get("content", "")).contains("FLASH_OK"), "live POST /v1/chat/completions (zen6-flash)")

		var chat_zen6 := live_client.chat_text("Say hello in three words.", "", "zen6", 1200, 0.2)
		_check(bool(chat_zen6.get("ok", false)) and not str(chat_zen6.get("content", "")).strip_edges().is_empty(), "live POST /v1/chat/completions (zen6)")

		# 3f. Zen Voice TTS -> playable AudioStreamMP3
		var sp := live_client.speech("Hanzo Godot game backend verified.", "alloy", "zen-voice")
		var mp3_stream := sp.get("audio_stream") as AudioStreamMP3
		_check(bool(sp.get("ok", false)) and mp3_stream != null and int(sp.get("bytes", 0)) > 1000 and mp3_stream.get_length() > 0.4, "live POST /v1/audio/speech (zen-voice -> playable AudioStreamMP3)")

		# 3g. Cloud Agent create -> run -> delete lifecycle
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var agent_name := "godot-check-%08x" % rng.randi()
		var ag_create := live_client.create_agent(agent_name, "You answer factual questions in one concise sentence.", "zen6-flash")
		_check(bool(ag_create.get("ok", false)), "live POST /v1/agent creates bounded-budget cloud agent")
		var ag_run := live_client.run_agent(agent_name, "What is the capital of Japan?")
		var ag_out := ""
		if ag_run.get("json") is Dictionary:
			var rj := ag_run["json"] as Dictionary
			var st := str(rj.get("status", ""))
			if st in ["queued", "pending", "running", "in_progress", "starting"]:
				for _i in range(30):
					var lr := live_client.get_agent_runs(agent_name, 5)
					if bool(lr.get("ok", false)) and lr.get("json") is Dictionary:
						var runs: Variant = (lr["json"] as Dictionary).get("runs", [])
						if runs is Array and not (runs as Array).is_empty():
							var f0 := (runs as Array)[0] as Dictionary
							if not (str(f0.get("status", "")) in ["queued", "pending", "running", "in_progress", "starting"]):
								ag_out = str(f0.get("output", ""))
								break
					OS.delay_msec(1000)
			else:
				ag_out = str(rj.get("output", ""))
		_check(bool(ag_run.get("ok", false)) and ag_out.to_lower().contains("tokyo"), "live POST /v1/agent/{ref}/run executes cloud agent")
		var ag_del := live_client.delete_agent(agent_name)
		_check(bool(ag_del.get("ok", false)), "live DELETE /v1/agent/{ref} cleans up cloud agent")

		# 3h. Tool Catalog & Cloud MCP (2026-07-28)
		var t_cat := live_client.list_tools()
		_check(bool(t_cat.get("ok", false)) and int(t_cat.get("count", 0)) > 100, "live GET /v1/tool lists cloud tool catalog")

		var mcp_init := live_client.mcp_rpc("initialize", {
			"protocolVersion": "2026-07-28",
			"capabilities": {},
			"clientInfo": {"name": "hanzo-godot-sdk-test", "version": "1.1.0"},
		})
		var mcp_init_res: Dictionary = mcp_init.get("result", {}) if mcp_init.get("result") is Dictionary else {}
		_check(bool(mcp_init.get("ok", false)) and str(mcp_init_res.get("protocolVersion", "")) == "2026-07-28", "live POST /v1/mcp initialize negotiates 2026-07-28")

		var mcp_tools := live_client.mcp_rpc("tools/list", {}, 2)
		var mcp_arr: Variant = (mcp_tools.get("result", {}) as Dictionary).get("tools", []) if mcp_tools.get("result") is Dictionary else []
		_check(bool(mcp_tools.get("ok", false)) and (mcp_arr is Array) and (mcp_arr as Array).size() > 50, "live POST /v1/mcp tools/list returns >50 cloud tools")

	if _failed > 0:
		printerr("SDK CHECK FAILED (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
		return
	print("SDK CHECK PASS (%d assertions)" % _passed)
	quit(0)
