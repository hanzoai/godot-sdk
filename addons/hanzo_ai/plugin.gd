@tool
extends EditorPlugin

const SETTINGS := {
	"hanzo_ai/base_url": {"default": "https://api.hanzo.ai", "type": TYPE_STRING},
	"hanzo_ai/api_key": {"default": "", "type": TYPE_STRING},
	"hanzo_ai/org_id": {"default": "", "type": TYPE_STRING},
	"hanzo_ai/default_chat_model": {"default": "zen6", "type": TYPE_STRING},
	"hanzo_ai/default_decision_model": {"default": "kai", "type": TYPE_STRING},
	"hanzo_ai/default_voice_model": {"default": "zen-voice", "type": TYPE_STRING},
}


func _enter_tree() -> void:
	for key in SETTINGS.keys():
		var spec: Dictionary = SETTINGS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, spec["default"])
		ProjectSettings.set_initial_value(key, spec["default"])
		ProjectSettings.add_property_info({
			"name": key,
			"type": spec["type"],
		})


func _exit_tree() -> void:
	pass
