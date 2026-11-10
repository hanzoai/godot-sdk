class_name HanzoClient
extends RefCounted

## Official Godot 4 client for the Hanzo Cloud API (https://api.hanzo.ai).
##
## Pure GDScript over Godot's native HTTPClient + TLSOptions.client() — zero C++
## GDExtension or .NET requirement, works in desktop, mobile, XR/VR, and headless CI.
##
## Environment configuration (resolved once in reload_config(), matching all Hanzo SDKs):
##   - HANZO_API_KEY   : Bearer API key (`hk-...` / `sk-...`) or Hanzo IAM access token
##   - HANZO_BASE_URL  : Gateway origin (default `https://api.hanzo.ai`)
##   - HANZO_ORG_ID    : Optional tenant override sent as `X-Org-Id`
##
## Primary AI models on `api.hanzo.ai`:
##   - `zen6` / `zen6-flash` / `zen6-coder` / `zen6-max` (`POST /v1/chat/completions`)
##   - `kai` (`POST /v1/decisions` — structured zero-output-token decisions)
##   - `zen-voice` (`POST /v1/audio/speech` -> `AudioStreamMP3`)

const DEFAULT_BASE_URL := "https://api.hanzo.ai"
const DEFAULT_CHAT_MODEL := "zen6"
const DEFAULT_FAST_CHAT_MODEL := "zen6-flash"
const DEFAULT_DECISION_MODEL := "kai"
const DEFAULT_VOICE_MODEL := "zen-voice"
const MCP_PROTOCOL_VERSION := "2026-07-28"
const SDK_USER_AGENT := "HanzoGodotSDK/1.0.0 (Godot-4)"

var base_url: String = DEFAULT_BASE_URL
var api_key: String = ""
var org_id: String = ""
var default_chat_model: String = DEFAULT_CHAT_MODEL
var default_decision_model: String = DEFAULT_DECISION_MODEL
var default_voice_model: String = DEFAULT_VOICE_MODEL
var timeout_ms: int = 45000
var last_error: String = ""
var request_count: int = 0


## Construct a client configured from environment variables (or explicit overrides).
func _init(p_api_key: String = "", p_base_url: String = "", p_org_id: String = "") -> void:
	reload_config()
	if not p_api_key.strip_edges().is_empty():
		api_key = p_api_key.strip_edges()
	if not p_base_url.strip_edges().is_empty():
		base_url = _normalize_base_url(p_base_url)
	if not p_org_id.strip_edges().is_empty():
		org_id = p_org_id.strip_edges()


## Shared Gateway-style factory matching Hanzo SDK conventions across languages.
static func from_env() -> HanzoClient:
	return HanzoClient.new()


## Reload configuration from HANZO_API_KEY, HANZO_BASE_URL, HANZO_ORG_ID, and ProjectSettings.
func reload_config() -> void:
	var ps_base := str(ProjectSettings.get_setting("hanzo_ai/base_url", DEFAULT_BASE_URL))
	var ps_key := str(ProjectSettings.get_setting("hanzo_ai/api_key", ""))
	var ps_org := str(ProjectSettings.get_setting("hanzo_ai/org_id", ""))
	default_chat_model = str(ProjectSettings.get_setting("hanzo_ai/default_chat_model", DEFAULT_CHAT_MODEL))
	default_decision_model = str(ProjectSettings.get_setting("hanzo_ai/default_decision_model", DEFAULT_DECISION_MODEL))
	default_voice_model = str(ProjectSettings.get_setting("hanzo_ai/default_voice_model", DEFAULT_VOICE_MODEL))

	var env_base := OS.get_environment("HANZO_BASE_URL").strip_edges()
	if env_base.is_empty():
		env_base = OS.get_environment("HANZO_API_URL").strip_edges()
	base_url = _normalize_base_url(env_base if not env_base.is_empty() else ps_base)

	var env_key := OS.get_environment("HANZO_API_KEY").strip_edges()
	api_key = env_key if not env_key.is_empty() else ps_key.strip_edges()

	var env_org := OS.get_environment("HANZO_ORG_ID").strip_edges()
	org_id = env_org if not env_org.is_empty() else ps_org.strip_edges()


static func _normalize_base_url(raw: String) -> String:
	var clean := raw.strip_edges().trim_suffix("/")
	if clean.is_empty():
		return DEFAULT_BASE_URL
	if clean.ends_with("/v1"):
		clean = clean.substr(0, clean.length() - 3)
	return clean


static func _parse_url(full_url: String) -> Dictionary:
	var u := full_url.strip_edges()
	var use_tls := false
	if u.begins_with("https://"):
		use_tls = true
		u = u.substr(8)
	elif u.begins_with("http://"):
		use_tls = false
		u = u.substr(7)
	var slash := u.find("/")
	var host_port := u if slash < 0 else u.substr(0, slash)
	var path := "/" if slash < 0 else u.substr(slash)
	var host := host_port
	var port := 443 if use_tls else 80
	var colon := host_port.find(":")
	if colon >= 0:
		host = host_port.substr(0, colon)
		port = int(host_port.substr(colon + 1))
	return {"host": host, "port": port, "path": path, "tls": use_tls}


## Build outbound headers for testing and wire inspection.
func build_headers(host: String, content_type: String = "application/json", use_auth: bool = true, extra_headers: Dictionary = {}) -> PackedStringArray:
	var headers := PackedStringArray([
		"Host: " + host,
		"User-Agent: " + SDK_USER_AGENT,
		"Accept: application/json, audio/mpeg, */*",
	])
	if not content_type.is_empty():
		headers.append("Content-Type: " + content_type)
	if use_auth and not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
		if not org_id.is_empty():
			headers.append("X-Org-Id: " + org_id)
	for hk in extra_headers.keys():
		headers.append("%s: %s" % [str(hk), str(extra_headers[hk])])
	return headers


## Low-level HTTP/HTTPS request over Godot's native HTTPClient + TLSOptions.
func request_raw(
	method: HTTPClient.Method,
	route_path: String,
	payload_bytes: PackedByteArray = PackedByteArray(),
	content_type: String = "application/json",
	use_auth: bool = true,
	extra_headers: Dictionary = {}
) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var full_url := route_path if (route_path.begins_with("https://") or route_path.begins_with("http://")) else (base_url + ("/" if not route_path.begins_with("/") else "") + route_path)
	var parsed := _parse_url(full_url)
	var host := str(parsed["host"])
	var port := int(parsed["port"])
	var path := str(parsed["path"])
	var use_tls := bool(parsed["tls"])

	var http := HTTPClient.new()
	var tls_opts: TLSOptions = TLSOptions.client() if use_tls else null
	var err := http.connect_to_host(host, port, tls_opts)
	if err != OK:
		last_error = "connect_to_host failed (%d) for %s" % [err, full_url]
		return {"ok": false, "status": 0, "error": last_error, "latency_ms": Time.get_ticks_msec() - t0}

	while true:
		http.poll()
		var st := http.get_status()
		if st == HTTPClient.STATUS_CONNECTED:
			break
		if st != HTTPClient.STATUS_RESOLVING and st != HTTPClient.STATUS_CONNECTING:
			last_error = "connection failed (status=%d) for %s" % [st, full_url]
			return {"ok": false, "status": 0, "error": last_error, "latency_ms": Time.get_ticks_msec() - t0}
		if Time.get_ticks_msec() - t0 > timeout_ms:
			last_error = "connection timeout after %d ms for %s" % [timeout_ms, full_url]
			return {"ok": false, "status": 0, "error": last_error, "latency_ms": Time.get_ticks_msec() - t0}
		OS.delay_msec(5)

	var effective_ct := content_type if (payload_bytes.size() > 0 or method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PUT or method == HTTPClient.METHOD_PATCH) else ""
	var headers := build_headers(host, effective_ct, use_auth, extra_headers)

	if payload_bytes.size() == 0 and (method == HTTPClient.METHOD_GET or method == HTTPClient.METHOD_DELETE):
		err = http.request(method, path, headers)
	else:
		err = http.request_raw(method, path, headers, payload_bytes)
	if err != OK:
		last_error = "request send failed (%d) for %s" % [err, full_url]
		return {"ok": false, "status": 0, "error": last_error, "latency_ms": Time.get_ticks_msec() - t0}

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() - t0 > timeout_ms:
			last_error = "response timeout after %d ms for %s" % [timeout_ms, full_url]
			return {"ok": false, "status": 0, "error": last_error, "latency_ms": Time.get_ticks_msec() - t0}
		OS.delay_msec(5)

	# IMPORTANT: In Godot 4, get_response_headers_as_dictionary() clears internal
	# response_headers, making subsequent has_response() return false. Capture first!
	var had_resp := http.has_response()
	var status_code := http.get_response_code()
	var resp_headers := http.get_response_headers_as_dictionary()
	var body := PackedByteArray()
	if had_resp or http.get_status() == HTTPClient.STATUS_BODY:
		while http.get_status() == HTTPClient.STATUS_BODY:
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				body.append_array(chunk)
			else:
				http.poll()
				OS.delay_msec(2)
			if Time.get_ticks_msec() - t0 > timeout_ms:
				last_error = "body read timeout after %d ms for %s" % [timeout_ms, full_url]
				break

	http.close()
	request_count += 1
	var elapsed := Time.get_ticks_msec() - t0

	var ctype := ""
	var cencoding := ""
	for hk in resp_headers.keys():
		var hkl := str(hk).to_lower()
		if hkl == "content-type":
			ctype = str(resp_headers[hk])
		elif hkl == "content-encoding":
			cencoding = str(resp_headers[hk]).to_lower()

	if cencoding.contains("gzip") or (body.size() >= 2 and body[0] == 0x1f and body[1] == 0x8b):
		body = body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	elif cencoding.contains("deflate"):
		body = body.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)

	var json_val: Variant = null
	if body.size() > 0 and (ctype.to_lower().contains("json") or body[0] == 123 or body[0] == 91):
		var txt := body.get_string_from_utf8().strip_edges()
		if not txt.is_empty():
			json_val = JSON.parse_string(txt)

	var ok_http := status_code >= 200 and status_code < 300
	if not ok_http:
		last_error = "HTTP %d from %s: %s" % [status_code, full_url, body.get_string_from_utf8().left(300)]
	return {
		"ok": ok_http,
		"status": status_code,
		"content_type": ctype,
		"headers": resp_headers,
		"body": body,
		"json": json_val,
		"latency_ms": elapsed,
	}


func request_json(method: HTTPClient.Method, route_path: String, payload: Variant = null, use_auth: bool = true, extra_headers: Dictionary = {}) -> Dictionary:
	var bytes := PackedByteArray()
	if payload != null:
		bytes = JSON.stringify(payload).to_utf8_buffer()
	return request_raw(method, route_path, bytes, "application/json", use_auth, extra_headers)


# ---------------------------------------------------------------------------
# Identity & Catalog (`hello` flow: GET /v1/models, GET /v1/account/keys)
# ---------------------------------------------------------------------------

## Public model catalog (`GET /v1/models` — `security: []`, sends no credential).
func get_models(filter_prefix: String = "") -> Dictionary:
	var res := request_json(HTTPClient.METHOD_GET, "/v1/models", null, false)
	if not bool(res.get("ok", false)) or not (res.get("json") is Dictionary):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error, "models": []}
	var data_arr: Variant = (res["json"] as Dictionary).get("data", [])
	var ids: Array[String] = []
	if data_arr is Array:
		for item in data_arr:
			if item is Dictionary:
				var mid := str((item as Dictionary).get("id", ""))
				if filter_prefix.is_empty() or mid.begins_with(filter_prefix):
					ids.append(mid)
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"count": ids.size(),
		"models": ids,
		"latency_ms": int(res.get("latency_ms", 0)),
	}


## Authenticated key list (`GET /v1/account/keys` — refuses 403 on missing/invalid key).
func get_account_keys() -> Dictionary:
	var res := request_json(HTTPClient.METHOD_GET, "/v1/account/keys")
	if not bool(res.get("ok", false)):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error, "keys": []}
	var keys: Array = []
	if res.get("json") is Dictionary:
		var k: Variant = (res["json"] as Dictionary).get("keys", [])
		if k is Array:
			keys = k
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"keys": keys,
		"latency_ms": int(res.get("latency_ms", 0)),
	}


# ---------------------------------------------------------------------------
# Inference (`chat`, `kai`, `speech`, `embeddings`)
# ---------------------------------------------------------------------------

## Chat completions (`POST /v1/chat/completions`, default model `zen6`).
func chat_completions(messages: Array, model: String = "", options: Dictionary = {}) -> Dictionary:
	var use_model := model if not model.strip_edges().is_empty() else default_chat_model
	var body: Dictionary = {
		"model": use_model,
		"messages": messages,
		"stream": false,
	}
	for k in ["max_tokens", "max_completion_tokens", "temperature", "top_p", "stop", "tools", "tool_choice", "response_format", "reasoning_effort", "seed", "user"]:
		if options.has(k):
			body[k] = options[k]
	var extra_headers: Dictionary = {}
	if options.has("max_cost"):
		extra_headers["X-Max-Cost"] = str(options["max_cost"])
	if options.has("max_latency_ms"):
		extra_headers["X-Max-Latency-Ms"] = str(options["max_latency_ms"])

	var res := request_json(HTTPClient.METHOD_POST, "/v1/chat/completions", body, true, extra_headers)
	if not bool(res.get("ok", false)) or not (res.get("json") is Dictionary):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error}
	var j := res["json"] as Dictionary
	var content := ""
	var finish_reason := ""
	var choices_val: Variant = j.get("choices", [])
	if choices_val is Array and not (choices_val as Array).is_empty():
		var c0: Variant = (choices_val as Array)[0]
		if c0 is Dictionary:
			finish_reason = str((c0 as Dictionary).get("finish_reason", ""))
			var msg: Variant = (c0 as Dictionary).get("message", {})
			if msg is Dictionary and (msg as Dictionary).get("content") != null:
				content = str((msg as Dictionary).get("content", ""))
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"id": str(j.get("id", "")),
		"model": str(j.get("model", use_model)),
		"content": content,
		"finish_reason": finish_reason,
		"usage": j.get("usage", {}),
		"raw": j,
		"latency_ms": int(res.get("latency_ms", 0)),
	}


## Convenience one-turn Zen 6 chat helper.
func chat_text(prompt: String, system_prompt: String = "", model: String = "", max_tokens: int = 900, temperature: float = 0.7) -> Dictionary:
	var msgs: Array = []
	if not system_prompt.is_empty():
		msgs.append({"role": "system", "content": system_prompt})
	msgs.append({"role": "user", "content": prompt})
	var res := chat_completions(msgs, model, {"max_tokens": max_tokens, "temperature": temperature})
	if bool(res.get("ok", false)) and str(res.get("content", "")).strip_edges().is_empty() and model.is_empty() and default_chat_model != DEFAULT_FAST_CHAT_MODEL:
		res = chat_completions(msgs, DEFAULT_FAST_CHAT_MODEL, {"max_tokens": max_tokens, "temperature": temperature})
	return res


## Structured Kai decision (`POST /v1/decisions`, default model `kai`).
func decide(state: Variant, questions: Dictionary, model: String = "", session_id: String = "") -> Dictionary:
	var use_model := model if not model.strip_edges().is_empty() else default_decision_model
	var body: Dictionary = {
		"model": use_model,
		"state": state,
		"questions": questions,
	}
	if not session_id.is_empty():
		body["session_id"] = session_id
	var res := request_json(HTTPClient.METHOD_POST, "/v1/decisions", body)
	if not bool(res.get("ok", false)) or not (res.get("json") is Dictionary):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error}
	var j := res["json"] as Dictionary
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"id": str(j.get("id", "")),
		"model": str(j.get("model", use_model)),
		"answers": j.get("answers", {}),
		"usage": j.get("usage", {}),
		"routing": j.get("routing", {}),
		"state_hash": str(j.get("state_hash", "")),
		"latency_ms": float(j.get("latency_ms", res.get("latency_ms", 0))),
	}


## Convenience single-choice Kai decision helper for NPC brains & game directors.
func decide_choice(state: Variant, criteria: Dictionary, instructions: String = "", question_key: String = "action", model: String = "") -> Dictionary:
	var q: Dictionary = {
		"type": "choice",
		"criteria": criteria,
	}
	if not instructions.is_empty():
		q["instructions"] = instructions
	var res := decide(state, {question_key: q}, model)
	if not bool(res.get("ok", false)):
		return res
	var answers: Dictionary = res.get("answers", {}) if res.get("answers") is Dictionary else {}
	var ans: Dictionary = answers.get(question_key, {}) if answers.get(question_key) is Dictionary else {}
	res["choice"] = str(ans.get("choice", ""))
	res["confidence"] = float(ans.get("confidence", 0.0))
	res["probabilities"] = ans.get("probabilities", {})
	return res


## Text-to-speech synthesis (`POST /v1/audio/speech`, default model `zen-voice` -> `AudioStreamMP3`).
func speech(input_text: String, voice: String = "alloy", model: String = "", response_format: String = "mp3", speed: float = 1.0) -> Dictionary:
	var use_model := model if not model.strip_edges().is_empty() else default_voice_model
	var body := {
		"model": use_model,
		"input": input_text,
		"voice": voice,
		"response_format": response_format,
		"speed": clampf(speed, 0.25, 4.0),
	}
	var res := request_json(HTTPClient.METHOD_POST, "/v1/audio/speech", body)
	var audio_bytes: PackedByteArray = res.get("body", PackedByteArray())
	if not bool(res.get("ok", false)) or audio_bytes.size() < 64:
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error, "bytes": 0}
	var stream: AudioStream = null
	if response_format == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = audio_bytes
		stream = mp3
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"model": use_model,
		"voice": voice,
		"bytes": audio_bytes.size(),
		"data": audio_bytes,
		"audio_stream": stream,
		"latency_ms": int(res.get("latency_ms", 0)),
	}


## Vector embeddings (`POST /v1/embeddings`).
func embeddings(input_value: Variant, model: String = "text-embedding-3-small") -> Dictionary:
	return request_json(HTTPClient.METHOD_POST, "/v1/embeddings", {"model": model, "input": input_value})


# ---------------------------------------------------------------------------
# Billing (`money` flow: GET /v1/billing/balance, GET /v1/billing/usage)
# ---------------------------------------------------------------------------

func get_billing_balance() -> Dictionary:
	return request_json(HTTPClient.METHOD_GET, "/v1/billing/balance")


func get_billing_usage(start_iso: String = "", end_iso: String = "") -> Dictionary:
	var qs: Array[String] = []
	if not start_iso.is_empty():
		qs.append("start=" + start_iso.uri_encode())
	if not end_iso.is_empty():
		qs.append("end=" + end_iso.uri_encode())
	var path := "/v1/billing/usage" + (("?" + "&".join(qs)) if not qs.is_empty() else "")
	return request_json(HTTPClient.METHOD_GET, path)


# ---------------------------------------------------------------------------
# Provisioning KV (`store` flow: /v1/provisioning/kv)
# ---------------------------------------------------------------------------

func create_kv_store(store_name: String, plan: String = "") -> Dictionary:
	var body: Dictionary = {"name": store_name}
	if not plan.is_empty():
		body["plan"] = plan
	return request_json(HTTPClient.METHOD_POST, "/v1/provisioning/kv", body)


func get_kv_store(store_name: String) -> Dictionary:
	return request_json(HTTPClient.METHOD_GET, "/v1/provisioning/kv/" + store_name.uri_encode())


func delete_kv_store(store_name: String) -> Dictionary:
	return request_json(HTTPClient.METHOD_DELETE, "/v1/provisioning/kv/" + store_name.uri_encode())


# ---------------------------------------------------------------------------
# Cloud Agents (`agent` flow: /v1/agent)
# ---------------------------------------------------------------------------

func create_agent(
	agent_name: String,
	instructions: String,
	model: String = DEFAULT_FAST_CHAT_MODEL,
	cap_micro_usd: int = 1000000,
	max_task_micro_usd: int = 250000,
	period: String = "month"
) -> Dictionary:
	return request_json(HTTPClient.METHOD_POST, "/v1/agent", {
		"name": agent_name,
		"model": model,
		"instructions": instructions,
		"cap_micro_usd": cap_micro_usd,
		"max_task_micro_usd": max_task_micro_usd,
		"period": period,
	})


func run_agent(agent_ref: String, input_text: String) -> Dictionary:
	return request_json(HTTPClient.METHOD_POST, "/v1/agent/%s/run" % agent_ref.uri_encode(), {
		"input": input_text,
	})


func get_agent_runs(agent_ref: String, limit: int = 20) -> Dictionary:
	return request_json(HTTPClient.METHOD_GET, "/v1/agent/%s/runs?limit=%d" % [agent_ref.uri_encode(), limit])


func delete_agent(agent_ref: String) -> Dictionary:
	return request_json(HTTPClient.METHOD_DELETE, "/v1/agent/%s" % agent_ref.uri_encode())


# ---------------------------------------------------------------------------
# Tool Catalog & MCP (`tools` flow: GET /v1/tool, POST /v1/mcp)
# ---------------------------------------------------------------------------

func list_tools() -> Dictionary:
	var res := request_json(HTTPClient.METHOD_GET, "/v1/tool")
	if not bool(res.get("ok", false)):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error, "tools": []}
	var tools_arr: Array = []
	if res.get("json") is Dictionary:
		var t: Variant = (res["json"] as Dictionary).get("tools", [])
		if t is Array:
			tools_arr = t
	return {
		"ok": true,
		"status": int(res.get("status", 200)),
		"count": tools_arr.size(),
		"tools": tools_arr,
		"latency_ms": int(res.get("latency_ms", 0)),
	}


func mcp_rpc(method_name: String, params: Dictionary = {}, req_id: int = 1) -> Dictionary:
	var res := request_json(HTTPClient.METHOD_POST, "/v1/mcp", {
		"jsonrpc": "2.0",
		"id": req_id,
		"method": method_name,
		"params": params,
	}, true, {"MCP-Protocol-Version": MCP_PROTOCOL_VERSION})
	if not bool(res.get("ok", false)) or not (res.get("json") is Dictionary):
		return {"ok": false, "status": int(res.get("status", 0)), "error": last_error}
	var j := res["json"] as Dictionary
	if j.has("error") and j["error"] != null:
		return {"ok": false, "status": int(res.get("status", 200)), "error": JSON.stringify(j["error"]), "raw": j}
	return {"ok": true, "status": int(res.get("status", 200)), "result": j.get("result", {}), "latency_ms": int(res.get("latency_ms", 0))}
