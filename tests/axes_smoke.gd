extends SceneTree

## Smoke test: mapeo de palancas únicas (LS Y = avance/retroceso · RS X = giro).
## Correr: godot --headless --script res://tests/axes_smoke.gd

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, name: String) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_failures += 1

func _run() -> void:
	var player := Player.new()
	root.add_child(player)

	_check(player._axes_to_command(0.0, 0.0) == "", "reposo (0,0) = sin comando")
	_check(player._axes_to_command(-1.0, 0.0) == "fwd", "LS arriba = avanzar")
	_check(player._axes_to_command(1.0, 0.0) == "back", "LS abajo = retroceder")
	_check(player._axes_to_command(0.0, -1.0) == "left", "RS izquierda = girar izq")
	_check(player._axes_to_command(0.0, 1.0) == "right", "RS derecha = girar der")
	_check(player._axes_to_command(0.1, 0.1) == "", "zona muerta (bajo umbral) = sin comando")
	_check(player._axes_to_command(0.9, -0.5) == "back", "eje dominante vertical gana (back)")
	_check(player._axes_to_command(-0.5, 0.9) == "right", "eje dominante horizontal gana (right)")
	_check(player._axes_to_command(0.0, 0.9) == "right", "ignora LS X / RS Y (solo cruz)")

	print("RESULTADO: %d fallos" % _failures)
	quit(1 if _failures > 0 else 0)