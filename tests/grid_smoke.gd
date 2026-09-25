extends SceneTree

## Smoke test temporal del sistema de grilla (correr: godot --headless --script res://tests/grid_smoke.gd).
## Verifica: celda inicial, paso fwd, bloqueo contra roca, giro 90°, posición interpolada.

var _failures := 0
var _steps := 0
var _blocked := 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, name: String) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_failures += 1

## Canal con más energía del WAV estéreo (L/R): verifica el paneo real del sonido.
func _loudest_channel(stream: AudioStreamWAV) -> String:
	var energy := [0.0, 0.0]
	var data := stream.data
	for i in data.size() / 4:
		energy[0] += absf(data.decode_s16(i * 4))
		energy[1] += absf(data.decode_s16(i * 4 + 2))
	return "L" if energy[0] >= energy[1] else "R"

func _rotation_forward(player: Player) -> Vector2:
	return Vector2(0, -1).rotated(player.rotation)

func _run() -> void:
	var scene: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var player: Player = scene.get_node("Player")
	player.step_taken.connect(func(_c): _steps += 1)
	player.step_blocked.connect(func(): _blocked += 1)

	_check(player.cell == Vector2i(13, 1), "celda inicial = base (13,1)")
	_check(player.forward_dir() == Vector2(MapGrid.W), "forward_dir apunta al frente (W) al iniciar")
	_check(_rotation_forward(player).distance_to(Vector2(MapGrid.W)) < 0.001, "rotación coherente con facing (W)")
	# La brújula se dibuja en local hacia el OESTE del mundo: al volverla al
	# espacio mundo debe dar (-1,0) con cualquier giro (flecha fija al OESTE).
	_check(player.west_local().rotated(player.rotation).distance_to(Vector2(MapGrid.W)) < 0.001, "brújula local apunta al OESTE del mundo")

	# Movimiento y giros se prueban desde (7,4) mirando al norte (estado
	# determinista): el spawn quedó en la base (13,1) mirando al oeste (al campo).
	player.cell = Vector2i(7, 4)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	player.rotation = MapGrid.forward_angle(player.facing)
	await physics_frame

	# Paso adelante con input real (acción WASD)
	Input.action_press(&"move_forward")
	for i in 25:
		await physics_frame
	Input.action_release(&"move_forward")
	_check(player.cell == Vector2i(7, 3), "avanzó 1 casilla al norte (hold cadencia)")
	_check(_steps >= 1, "emitió step_taken")
	var target: Vector2 = MapGrid.center(Vector2i(7, 3))
	_check(player.position.distance_to(target) < 1.0, "posición interpolada al centro de celda")

	# Giro 90° izquierda (N → W)
	var before: Vector2i = player.facing
	Input.action_press(&"turn_left")
	for i in 25:
		await physics_frame
	Input.action_release(&"turn_left")
	_check(player.facing == MapGrid.turn_left(before), "giro 90° izquierda")
	_check(player.forward_dir() == Vector2(MapGrid.turn_left(before)), "forward_dir acompaña el giro")
	_check(_rotation_forward(player).distance_to(Vector2(MapGrid.turn_left(before))) < 0.001, "rotación coherente tras giro")
	_check(_loudest_channel(scene._turn_player.stream) == "L", "giro a la izquierda → sonido mayormente en el oído izquierdo")

	# Giro 90° derecha (W → N): el sonido se panea al oído derecho.
	var before_r: Vector2i = player.facing
	Input.action_press(&"turn_right")
	for i in 25:
		await physics_frame
	Input.action_release(&"turn_right")
	_check(player.facing == MapGrid.turn_right(before_r), "giro 90° derecha")
	_check(_loudest_channel(scene._turn_player.stream) == "R", "giro a la derecha → sonido mayormente en el oído derecho")

	# Bloqueo: posiciono delante de la roca de basalto en (4,2)
	Input.action_release(&"move_forward")
	player.cell = Vector2i(4, 3)
	player.facing = MapGrid.N
	player.position = MapGrid.center(player.cell)
	player.state = Player.State.IDLE
	await physics_frame
	var blocked_before: int = _blocked
	Input.action_press(&"move_forward")
	for i in 20:
		await physics_frame
	Input.action_release(&"move_forward")
	_check(_blocked > blocked_before, "paso contra roca = bloqueado (sonido)")
	_check(player.cell == Vector2i(4, 3), "no avanzó a celda bloqueada")

	print("RESULTADO: %d fallos" % _failures)
	quit(1 if _failures > 0 else 0)