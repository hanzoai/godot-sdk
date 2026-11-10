class_name HanzoAgent3D
extends Node3D

## Drop-in 3D AI NPC / Voice Agent node for Godot 4.
##
## Runs Zen 6 (`chat_completions`), Kai (`decide_choice`), and Zen Voice (`speech`)
## asynchronously on Godot's WorkerThreadPool so frame pacing never stalls in
## 60-120 Hz desktop or XR scenes, and optionally plays spatial 3D audio on an
## attached AudioStreamPlayer3D.

signal decision_ready(choice: String, confidence: float, result: Dictionary)
signal reply_ready(content: String, result: Dictionary)
signal speech_ready(stream: AudioStream, result: Dictionary)
signal request_failed(operation: String, error: String)

@export var chat_model: String = HanzoClient.DEFAULT_CHAT_MODEL
@export var decision_model: String = HanzoClient.DEFAULT_DECISION_MODEL
@export var voice_model: String = HanzoClient.DEFAULT_VOICE_MODEL
@export var voice: String = "alloy"
@export_multiline var system_prompt: String = "You are an intelligent in-world character. Respond concisely in character."
@export var auto_play_speech: bool = true

var audio_player: AudioStreamPlayer3D = null


func _ready() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			audio_player = child as AudioStreamPlayer3D
			break
	if audio_player == null and auto_play_speech:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "HanzoVoice3D"
		add_child(audio_player)


## Non-blocking tactical / behavioral decision via Kai (`POST /v1/decisions`).
func decide_async(state: Dictionary, criteria: Dictionary, instructions: String = "") -> void:
	var model_copy := decision_model
	WorkerThreadPool.add_task(func() -> void:
		var client := HanzoClient.from_env()
		var res := client.decide_choice(state, criteria, instructions, "action", model_copy)
		call_deferred("_on_decision_done", res)
	)


## Non-blocking Zen 6 dialogue generation (`POST /v1/chat/completions`).
func ask_async(prompt: String, max_tokens: int = 900, speak_reply: bool = false) -> void:
	var model_copy := chat_model
	var sys_copy := system_prompt
	WorkerThreadPool.add_task(func() -> void:
		var client := HanzoClient.from_env()
		var res := client.chat_text(prompt, sys_copy, model_copy, max_tokens)
		call_deferred("_on_reply_done", res, speak_reply)
	)


## Non-blocking Zen Voice speech synthesis (`POST /v1/audio/speech` -> `AudioStreamMP3`).
func speak_async(text: String) -> void:
	var v_model := voice_model
	var v_name := voice
	WorkerThreadPool.add_task(func() -> void:
		var client := HanzoClient.from_env()
		var res := client.speech(text, v_name, v_model)
		call_deferred("_on_speech_done", res)
	)


func _on_decision_done(res: Dictionary) -> void:
	if not bool(res.get("ok", false)):
		request_failed.emit("decide", str(res.get("error", "unknown error")))
		return
	decision_ready.emit(str(res.get("choice", "")), float(res.get("confidence", 0.0)), res)


func _on_reply_done(res: Dictionary, speak_reply: bool) -> void:
	if not bool(res.get("ok", false)):
		request_failed.emit("chat", str(res.get("error", "unknown error")))
		return
	var text := str(res.get("content", ""))
	reply_ready.emit(text, res)
	if speak_reply and not text.strip_edges().is_empty():
		speak_async(text)


func _on_speech_done(res: Dictionary) -> void:
	if not bool(res.get("ok", false)):
		request_failed.emit("speech", str(res.get("error", "unknown error")))
		return
	var stream: AudioStream = res.get("audio_stream") as AudioStream
	if stream != null and auto_play_speech and audio_player != null and is_inside_tree():
		audio_player.stream = stream
		audio_player.play()
	speech_ready.emit(stream, res)
