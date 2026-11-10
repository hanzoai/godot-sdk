extends SceneTree

## speech — Synthesize voice audio into a playable Godot AudioStreamMP3 (`POST /v1/audio/speech`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/speech.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()
	var res := client.speech("Signal locked. Welcome to Hanzo AI on Godot four.", "alloy", "zen-voice")
	if not bool(res.get("ok", false)):
		printerr("speech failed: %s" % client.last_error)
		quit(1)
		return

	var stream: AudioStreamMP3 = res.get("audio_stream") as AudioStreamMP3
	if stream == null or stream.data.is_empty():
		printerr("speech returned invalid AudioStreamMP3")
		quit(1)
		return

	print("model    %s (voice=%s)" % [str(res.get("model", "")), str(res.get("voice", ""))])
	print("audio    %d bytes -> AudioStreamMP3 (%.2fs)" % [int(res.get("bytes", 0)), stream.get_length()])
	quit(0)
