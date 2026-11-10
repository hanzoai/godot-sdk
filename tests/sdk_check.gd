extends SceneTree

## Hanzo Godot SDK verification suite (`tests/sdk_check.gd`).
## Verifies:
##   1. URL normalization, default configuration, Bearer + X-Org-Id headers, public route no-auth
##   2. HanzoAgent3D node instantiation & AudioStreamPlayer3D wiring
##   3. Live `https://api.hanzo.ai` verification when HANZO_API_KEY is set:
##      - GET /v1/models (zen6, zen6-flash, kai, zen-voice present)
##      - GET /v1/account/keys (403 on bad key, 200 on valid key)
##      - POST /v1/chat/completions (zen6)
##      - POST /v1/decisions (kai)
##      - POST /v1/audio/speech (zen-voice -> AudioStreamMP3)
##      - POST /v1/mcp (tools/list)

var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s" % label)


func _initialize() -> void:
	# 1. Offline wire & config checks
	var c_default := HanzoClient.new("", "", "")
	if OS.get_environment("HANZO_BASE_URL").is_empty() and OS.get_environment("HANZO_API_URL").is_empty():
		_check(c_default.base_url == "https://api.hanzo.ai", "default base_url is https://api.hanzo.ai")
	_check(c_default.default_chat_model == "zen6", "default chat model is zen6")
	_check(c_default.default_decision_model == "kai", "default decision model is kai")
	_check(c_default.default_voice_model == "zen-voice", "default voice model is zen-voice")

	var c_norm := HanzoClient.new("hk-unit", "https://api.hanzo.ai/v1/", "acme")
	_check(c_norm.base_url == "https://api.hanzo.ai", "strips trailing /v1/ from base_url")
	var hdrs_auth := Array(c_norm.build_headers("api.hanzo.ai", "application/json", true, {"X-Max-Cost": "0.25"}))
	_check(hdrs_auth.has("Authorization: Bearer hk-unit"), "sends Bearer header")
	_check(hdrs_auth.has("X-Org-Id: acme"), "sends X-Org-Id header")
	_check(hdrs_auth.has("X-Max-Cost: 0.25"), "sends custom bound header")

	var hdrs_public := Array(c_norm.build_headers("api.hanzo.ai", "", false))
	var leaked_auth := false
	for h in hdrs_public:
		if str(h).begins_with("Authorization:") or str(h).begins_with("X-Org-Id:"):
			leaked_auth = true
	_check(not leaked_auth, "omits credentials on public routes (security: [])")

	# 2. HanzoAgent3D node check
	var agent_node := HanzoAgent3D.new()
	root.add_child(agent_node)
	agent_node._ready()
	_check(agent_node.chat_model == "zen6", "HanzoAgent3D defaults to zen6")
	_check(agent_node.decision_model == "kai", "HanzoAgent3D defaults to kai")
	_check(agent_node.voice_model == "zen-voice", "HanzoAgent3D defaults to zen-voice")
	_check(agent_node.audio_player != null, "HanzoAgent3D creates AudioStreamPlayer3D")
	agent_node.free()

	# 3. Live gateway checks (when HANZO_API_KEY is present and HANZO_OFFLINE != 1)
	var live_client := HanzoClient.from_env()
	if OS.get_environment("HANZO_OFFLINE") != "1" and not live_client.api_key.is_empty():
		print("Running live api.hanzo.ai checks...")
		var models := live_client.get_models()
		_check(bool(models.get("ok", false)), "live GET /v1/models HTTP 200")
		var model_ids: Array = models.get("models", [])
		_check(model_ids.has("zen6"), "catalog includes zen6")
		_check(model_ids.has("zen6-flash"), "catalog includes zen6-flash")
		_check(model_ids.has("kai"), "catalog includes kai")
		_check(model_ids.has("zen-voice"), "catalog includes zen-voice")

		var bad_client := HanzoClient.new("hk-invalid-probe-token", live_client.base_url)
		var bad_keys := bad_client.get_account_keys()
		_check(not bool(bad_keys.get("ok", false)) and int(bad_keys.get("status", 0)) in [401, 403], "GET /v1/account/keys refuses bad token")

		var ok_keys := live_client.get_account_keys()
		_check(bool(ok_keys.get("ok", false)), "live GET /v1/account/keys accepts valid token")

		var chat := live_client.chat_text("Reply with exact word: GODOT_OK", "", "zen6", 900, 0.0)
		_check(bool(chat.get("ok", false)) and not str(chat.get("content", "")).strip_edges().is_empty(), "live POST /v1/chat/completions (zen6)")

		var dec := live_client.decide_choice(
			{"hp": 90, "threat": true},
			{"hold": "stay in cover", "engage": "engage visible threat"}
		)
		_check(bool(dec.get("ok", false)) and str(dec.get("choice", "")) in ["hold", "engage"], "live POST /v1/decisions (kai)")

		var sp := live_client.speech("Hanzo Godot SDK verified.", "alloy", "zen-voice")
		_check(bool(sp.get("ok", false)) and (sp.get("audio_stream") is AudioStreamMP3) and int(sp.get("bytes", 0)) > 1000, "live POST /v1/audio/speech (zen-voice -> AudioStreamMP3)")

		var mcp := live_client.mcp_rpc("tools/list", {})
		_check(bool(mcp.get("ok", false)), "live POST /v1/mcp (tools/list)")

	if _failed > 0:
		printerr("SDK CHECK FAILED (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
		return
	print("SDK CHECK PASS (%d assertions)" % _passed)
	quit(0)
