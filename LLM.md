# hanzoai/godot-sdk — notes for maintainers & agents

Home: `github.com/hanzoai/godot-sdk`. Checkout: `~/work/hanzo/godot-sdk`.
Addon path: `addons/hanzo_ai/`.

## Architecture

- **`addons/hanzo_ai/hanzo_client.gd` (`HanzoClient`)**: Pure-GDScript client over Godot 4's `HTTPClient` + `TLSOptions.client()`. Reads `HANZO_API_KEY`, `HANZO_BASE_URL` (default `https://api.hanzo.ai`), and `HANZO_ORG_ID` (`X-Org-Id`) once in `reload_config()`.
  - **Godot 4 `HTTPClient` quirk**: Always read `http.has_response()` *before* `http.get_response_headers_as_dictionary()` — the latter clears internal response headers and makes subsequent `has_response()` return `false`.
- **`addons/hanzo_ai/hanzo_agent_3d.gd` (`HanzoAgent3D`)**: Non-blocking `Node3D` wrapper dispatching `zen6`, `kai`, and `zen-voice` calls onto `WorkerThreadPool` and emitting signals (`decision_ready`, `reply_ready`, `speech_ready`) via `call_deferred`.
- **Models**: Default to **Zen 6** (`zen6`, `zen6-flash`, `zen6-coder`, `zen6-max`), **`kai`** for `/v1/decisions`, and **`zen-voice`** for `/v1/audio/speech`.

## Testing

```bash
# Offline wire & node checks
HANZO_OFFLINE=1 godot --headless --path . -s res://tests/sdk_check.gd

# Live gateway verification against https://api.hanzo.ai
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://tests/sdk_check.gd
```
