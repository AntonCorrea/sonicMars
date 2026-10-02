extends SceneTree

## Smoke test: mapeo de palancas únicas (LS Y = avance/retroceso · RS X = giro)
## y cruzeta del pad (flechas digitales equivalentes).
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
	# Cruzeta (D-pad): flechas digitales mandan igual que las palancas.
	_check(player.axes_dpad_to_command(0.0, 0.0, -1.0, 0.0) == "fwd", "cruzeta arriba = avanzar")
	_check(player.axes_dpad_to_command(0.0, 0.0, 1.0, 0.0) == "back", "cruzeta abajo = retroceder")
	_check(player.axes_dpad_to_command(0.0, 0.0, 0.0, -1.0) == "left", "cruzeta izquierda = girar izq")
	_check(player.axes_dpad_to_command(0.0, 0.0, 0.0, 1.0) == "right", "cruzeta derecha = girar der")
	_check(player.axes_dpad_to_command(0.4, 0.0, -1.0, 0.0) == "fwd", "cruzeta arriba arrastra a LS abajo (0.4)")
	_check(player.axes_dpad_to_command(1.0, 0.0, -1.0, 0.0) == "", "cruzeta y palanca opuestas a tope se cancelan")
	_check(player.axes_dpad_to_command(0.0, -0.5, 0.0, 1.0) == "right", "cruzeta derecha arrastra a RS izquierda (0.5)")
	_check(player.axes_dpad_to_command(0.0, 0.0, 0.0, 0.0) == "", "sin cruzeta ni palancas = sin comando")

	# Convenciones de vector runtime (axes = Vector2(ly, rx) · dpad = Vector2(dpad_rx, dpad_ly)):
	# regresión: la palanca IZQ conduce y la DER gira (nunca al revés).
	_check(player.axes_vec_to_command(Vector2(-1.0, 0.0), Vector2.ZERO) == "fwd", "LS arriba = avanzar (vector)")
	_check(player.axes_vec_to_command(Vector2(1.0, 0.0), Vector2.ZERO) == "back", "LS abajo = retroceder (vector)")
	_check(player.axes_vec_to_command(Vector2(0.0, -1.0), Vector2.ZERO) == "left", "RS izquierda = girar izq (vector)")
	_check(player.axes_vec_to_command(Vector2(0.0, 1.0), Vector2.ZERO) == "right", "RS derecha = girar der (vector)")
	_check(player.axes_vec_to_command(Vector2.ZERO, Vector2(0.0, -1.0)) == "fwd", "cruzeta arriba = avanzar (vector)")
	_check(player.axes_vec_to_command(Vector2.ZERO, Vector2(0.0, 1.0)) == "back", "cruzeta abajo = retroceder (vector)")
	_check(player.axes_vec_to_command(Vector2.ZERO, Vector2(-1.0, 0.0)) == "left", "cruzeta izquierda = girar izq (vector)")
	_check(player.axes_vec_to_command(Vector2.ZERO, Vector2(1.0, 0.0)) == "right", "cruzeta derecha = girar der (vector)")
	_check(player.axes_vec_to_command(Vector2(-1.0, 0.0), Vector2(0.0, 1.0)) == "", "LS arriba y cruzeta abajo se cancelan")
	_check(player.axes_vec_to_command(Vector2(0.0, 1.0), Vector2(-1.0, 0.0)) == "", "RS derecha y cruzeta izquierda se cancelan")

	print("RESULTADO: %d fallos" % _failures)
	quit(1 if _failures > 0 else 0)