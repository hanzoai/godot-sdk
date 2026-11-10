extends SceneTree

## money — Billing balance & usage (`GET /v1/billing/balance`, `GET /v1/billing/usage`).
## Run: HANZO_API_KEY=hk-... godot --headless --path . -s res://examples/money.gd


func _initialize() -> void:
	var client := HanzoClient.from_env()

	var bal := client.get_billing_balance()
	if not bool(bal.get("ok", false)):
		printerr("balance failed: %s" % client.last_error)
		quit(1)
		return
	print("balance  HTTP %d" % int(bal.get("status", 0)))

	var usage := client.get_billing_usage()
	if not bool(usage.get("ok", false)):
		printerr("usage failed: %s" % client.last_error)
		quit(1)
		return
	print("usage    HTTP %d" % int(usage.get("status", 0)))
	quit(0)
