# Hanzo — Godot 4 SDK

[![Built with Hanzo](https://hanzo.ai/badges/built-with-hanzo.svg)](https://hanzo.ai)
[![Edit on Hanzo](https://hanzo.ai/badges/edit-on-hanzo.svg)](https://hanzo.app/dev?repo=https%3A%2F%2Fgithub.com%2Fhanzoai%2Fgodot-sdk)

Official Godot 4 SDK (`addons/hanzo_ai`) for the [Hanzo Cloud API](https://hanzo.ai) at `https://api.hanzo.ai` — **[Docs](https://docs.hanzo.ai/docs/sdks/godot)** · **[Agent Skill (`godot.md`)](https://hanzoskills.com/godot.md)**.

Pure GDScript over Godot's built-in `HTTPClient` + `TLSOptions.client()` — **zero GDExtension or .NET build required**, works out of the box on Linux, macOS, Windows, Android, iOS, OpenXR/VR, and headless CI. Also compatible alongside the [`Hanzo`](https://github.com/hanzo-csharp/sdk) NuGet package in Godot 4 .NET projects (see [`examples/csharp/`](examples/csharp)).

## Models & Game-Engine Surfaces

| Capability | Route | Default Model | Godot Return Shape |
| --- | --- | --- | --- |
| Dialogue, reasoning, code | `POST /v1/chat/completions` | `zen6` (`zen6-flash`, `zen6-coder`, `zen6-max`) | `{ok, model, content, usage, latency_ms}` |
| Tactical NPC / AI Director decisions | `POST /v1/decisions` | `kai` | `{ok, choice, confidence, probabilities, latency_ms}` |
| Real-time 3D spatial voice synthesis | `POST /v1/audio/speech` | `zen-voice` | `{ok, bytes, audio_stream: AudioStreamMP3}` |
| Public model discovery | `GET /v1/models` | — (`security: []`) | `{ok, count, models}` |
| Key verification | `GET /v1/account/keys` | — | `{ok, keys}` |
| Billing balance & usage | `GET /v1/billing/{balance,usage}` | — | `{ok, status, json}` |
| Cloud KV game saves & state | `POST / PUT / GET / DELETE /v1/kv/{bucket}[/{key}]` | — | `{ok, data, revision, revisions}` |
| Provisioning KV stores | `POST/GET/DELETE /v1/provisioning/kv` | — | `{ok, status, json}` |
| Cloud Agents | `POST /v1/agent`, `POST /v1/agent/{ref}/run` | `zen6-flash` | `{ok, status, json}` |
| MCP Tool catalog & JSON-RPC | `GET /v1/tool`, `POST /v1/mcp` | — | `{ok, count, tools}` / `{ok, result}` |

## Install

### Option 1: Copy or submodule `addons/hanzo_ai`

Download `hanzo-godot-sdk-v1.1.0.zip` from [Releases](https://github.com/hanzoai/godot-sdk/releases) (or clone `hanzoai/godot-sdk`) and copy `addons/hanzo_ai/` into your Godot 4 project's `addons/` folder, then enable **Hanzo AI SDK** under **Project -> Project Settings -> Plugins**.

### Option 2: Godot 4 .NET (C#)

See [`examples/csharp/`](examples/csharp) to combine Godot 4 .NET with the [`Hanzo`](https://github.com/hanzo-csharp/sdk) NuGet package (`8.5.1026`).

## Authenticate

[`HanzoClient`](addons/hanzo_ai/hanzo_client.gd) resolves credentials in one place from environment variables (or `ProjectSettings` under `hanzo_ai/*`):

| Variable | Meaning |
| --- | --- |
| `HANZO_API_KEY` | Bearer credential: a Hanzo Cloud API key (`hk-...`) or IAM token |
| `HANZO_BASE_URL` | Gateway origin; default `https://api.hanzo.ai` |
| `HANZO_ORG_ID` | Optional org scope sent as `X-Org-Id` |

## Quickstart (GDScript)

```gdscript
var client := HanzoClient.from_env()

# 1. Zen 6 Dialogue / Narrative
var chat := client.chat_text("Give a one-line radio transmission from orbit.", "", "zen6")
print(chat["content"])

# 2. Kai Tactical NPC Decision (zero output tokens, ~100 ms)
var dec := client.decide_choice(
    {"health": 80, "ammo": 12, "target_visible": true},
    {
        "patrol": "continue route when area is clear",
        "engage": "attack visible threat when healthy",
        "retreat": "fall back when critically injured",
    }
)
print("NPC tactic: ", dec["choice"], " confidence=", dec["confidence"])

# 3. Zen Voice -> Playable Godot AudioStreamMP3
var voice := client.speech("Contact confirmed at sector four.", "alloy", "zen-voice")
if voice["ok"]:
    $AudioStreamPlayer3D.stream = voice["audio_stream"]
    $AudioStreamPlayer3D.play()
```

### Non-Blocking 3D Node (`HanzoAgent3D`)

Drop [`HanzoAgent3D`](addons/hanzo_ai/hanzo_agent_3d.gd) into any 3D/VR scene to run `zen6`, `kai`, and `zen-voice` on Godot's `WorkerThreadPool` without stalling frame pacing, emitting `decision_ready`, `reply_ready`, and `speech_ready` on the main thread and automatically playing spatial MP3 audio on a child `AudioStreamPlayer3D`.

## Examples

All six canonical Hanzo SDK flows from `hanzoai/openapi` `flows.yaml` plus Godot-specific `kai` and `speech` flows:

| Flow | Script | Route(s) |
| --- | --- | --- |
| `hello` | [`examples/hello.gd`](examples/hello.gd) | `GET /v1/models`, `GET /v1/account/keys` |
| `chat` | [`examples/chat.gd`](examples/chat.gd) | `POST /v1/chat/completions` (`zen6`) |
| `kai` | [`examples/kai.gd`](examples/kai.gd) | `POST /v1/decisions` (`kai`) |
| `speech` | [`examples/speech.gd`](examples/speech.gd) | `POST /v1/audio/speech` (`zen-voice` -> `AudioStreamMP3`) |
| `money` | [`examples/money.gd`](examples/money.gd) | `GET /v1/billing/balance`, `GET /v1/billing/usage` |
| `store` | [`examples/store.gd`](examples/store.gd) | `POST / GET / DELETE /v1/provisioning/kv` |
| `agent` | [`examples/agent.gd`](examples/agent.gd) | `POST /v1/agent`, `POST /v1/agent/{ref}/run`, `DELETE /v1/agent/{ref}` |
| `tools` | [`examples/tools.gd`](examples/tools.gd) | `GET /v1/tool` |
| `game_backend` | [`examples/game_backend.gd`](examples/game_backend.gd) | Complete game loop: Cloud KV saves -> Kai Director -> Zen 6 radio -> Zen Voice 3D MP3 |
| `csharp` | [`examples/csharp/HanzoGodotNode.cs`](examples/csharp/HanzoGodotNode.cs) | Godot 4 .NET + `Hanzo` NuGet |

Run any example headlessly with Godot 4.x:

```bash
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://examples/game_backend.gd
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://examples/hello.gd
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://examples/chat.gd
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://examples/kai.gd
HANZO_API_KEY=$(hanzo auth token) godot --headless --path . -s res://examples/speech.gd
```

## The same API in other languages

[Python](https://github.com/hanzoai/python-sdk) ·
[TypeScript](https://github.com/hanzoai/js-sdk) ·
[Go](https://github.com/hanzo-go/sdk) ·
[Rust](https://github.com/hanzo-rs/sdk) ·
[C#](https://github.com/hanzo-csharp/sdk) ·
[Java](https://github.com/hanzo-java/sdk) ·
[C++](https://github.com/hanzo-cpp/sdk) ·
[all SDKs](https://github.com/hanzoai/sdk)

## License

Apache-2.0. See [LICENSE](LICENSE).

## Local open-weight models (no key, no cloud)

Run NPCs on an open-weight model on the player's or developer's machine:

```bash
hanzo load zen6-nano                      # Hanzo Engine on http://127.0.0.1:36900/v1
HANZO_BASE_URL=http://127.0.0.1:36900 HANZO_MODEL=zen6-nano \
  godot --headless --path . -s res://examples/local_npc.gd
```

`HanzoClient` talks to the local engine exactly as it talks to `api.hanzo.ai`; switch back by
unsetting `HANZO_BASE_URL`. CI (`.github/workflows/zen6-local.yml`) serves `zen6-nano`
(2B, 429 MB) on the runner CPU and runs `tests/sdk_check.gd` against it.
