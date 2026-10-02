class_name Player
extends Node2D

## Movimiento en grilla · mando tanque.
## Palancas con función única: LS (Y) = avanzar/retroceder · RS (X) = girar 90° en eje.
## Cruzeta del pad = flechas digitales (↑ avanzar · ↓ retroceder · ← girar izq · → girar der).
## Teclado WASD/flechas = respaldo completo (4 direcciones).
## Mantener = repetición con cadencia. Un comando en buffer mientras se mueve.
## Posición = vista: facing cardinal (N/S/E/O) es la única referencia espacial.

signal step_taken(cell: Vector2i)
signal step_blocked
## El parámetro indica el lado del giro: true = izquierda (oído izquierdo), false = derecha.
signal turn_taken(turn_left: bool)

const STEP_TIME := 0.18
const TURN_TIME := 0.22
const STEP_INTERVAL := 0.5
const TURN_INTERVAL := 0.7
const AXIS_DEADZONE := 0.2

enum State { IDLE, MOVING, TURNING }

var grid: MapGrid
var cell := Vector2i(7, 4)
var facing := MapGrid.N

## Permite/deniega la conducción: bloqueada durante la intro hablada de arranque
## (main._start_intro/_end_intro la apagan/prenden en cada partida).
var input_enabled := true

var state := State.IDLE
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _from_angle := 0.0
var _to_angle := 0.0
var _t := 0.0

var _held := ""
var _hold := 0.0
var _queued_cmd := ""

func _ready() -> void:
	facing = MapGrid.W
	rotation = MapGrid.forward_angle(facing)

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			_idle(delta)
		State.MOVING:
			_advance_position(delta)
		State.TURNING:
			_advance_rotation(delta)
	# Un comando que DEJA de coincidir con lo sostenido durante el movimiento
	# se bufferiza; si el jugador sigue sosteniendo lo mismo, manda la cadencia.
	if state == State.IDLE and _queued_cmd != "":
		var cmd := _queued_cmd
		_queued_cmd = ""
		_hold = 0.0
		_try_execute(cmd)

func _idle(delta: float) -> void:
	if not input_enabled:
		_held = ""
		_queued_cmd = ""
		_hold = 0.0
		return
	var dir := _held_dir()
	if dir != "":
		if dir == _held:
			_hold += delta
			var interval := TURN_INTERVAL if dir == "left" or dir == "right" else STEP_INTERVAL
			if _hold >= interval:
				_hold = 0.0
				_try_execute(dir)
		else:
			_held = dir
			_hold = 0.0
			_try_execute(dir)
	else:
		_held = ""

func _capture_busy_input() -> void:
	if not input_enabled:
		_held = ""
		_queued_cmd = ""
		_hold = 0.0
		return
	var dir := _held_dir()
	if dir != _held:
		if dir != "":
			_queued_cmd = dir
		_held = dir
		_hold = 0.0

func _try_execute(cmd: String) -> void:
	match cmd:
		"left":
			_start_turn(MapGrid.turn_left(facing))
		"right":
			_start_turn(MapGrid.turn_right(facing))
		"fwd":
			_try_step(facing)
		"back":
			_try_step(-facing)

func _try_step(d: Vector2i) -> void:
	if grid == null or grid.is_blocked(cell + d):
		step_blocked.emit()
		return
	_from = MapGrid.center(cell)
	_to = MapGrid.center(cell + d)
	cell += d
	_t = 0.0
	state = State.MOVING
	step_taken.emit(cell)

func _advance_position(delta: float) -> void:
	_capture_busy_input()
	_t += delta / STEP_TIME
	var p := clampf(_t, 0.0, 1.0)
	position = _from.lerp(_to, p * (2.0 - p))
	if _t >= 1.0:
		position = _to
		state = State.IDLE
		_hold = 0.0

func _start_turn(new_facing: Vector2i) -> void:
	_from_angle = rotation
	_to_angle = MapGrid.forward_angle(new_facing)
	var is_left := MapGrid.turn_left(facing) == new_facing
	facing = new_facing
	_t = 0.0
	state = State.TURNING
	turn_taken.emit(is_left)

func _advance_rotation(delta: float) -> void:
	_capture_busy_input()
	_t += delta / TURN_TIME
	var p := clampf(_t, 0.0, 1.0)
	rotation = lerp_angle(_from_angle, _to_angle, p * (2.0 - p))
	if _t >= 1.0:
		rotation = _to_angle
		state = State.IDLE
		_hold = 0.0

## Rejilla de juego cartesiana — reinicio: vuelve al estado inicial de arranque
## (celda y orientación de la base, buffers de entrada limpios).
func reset_to(start_cell: Vector2i, start_facing: Vector2i) -> void:
	cell = start_cell
	position = MapGrid.center(start_cell)
	facing = start_facing
	rotation = MapGrid.forward_angle(start_facing)
	state = State.IDLE
	_held = ""
	_queued_cmd = ""
	_hold = 0.0
	_from = position
	_to = position
	_from_angle = rotation
	_to_angle = rotation
	_t = 0.0

## Dirección de avance (mundo) = hacia donde mira el jugador.
func forward_dir() -> Vector2:
	return Vector2(facing)

## Traduce los ejes de palanca (LS Y = avance · RS X = giro) a comando.
## Helper puro y determinista (testeable sin hardware, compartido con el HUD de diagnóstico).
static func axes_to_command(ly: float, rx: float) -> String:
	var v := clampf(ly, -1.0, 1.0)
	var h := clampf(rx, -1.0, 1.0)
	if absf(v) < AXIS_DEADZONE and absf(h) < AXIS_DEADZONE:
		return ""
	if absf(v) >= absf(h):
		return "back" if v > 0.0 else "fwd"
	return "right" if h > 0.0 else "left"

## Traduce palancas analógicas + cruzeta digital al mismo comando dominante.
## La cruzeta suma fuerza digital (1.0) a la palanca correspondiente y el
## conjunto pasa por la misma dominante de axes_to_command. Helper puro y
## determinista (testeable sin hardware).
static func axes_dpad_to_command(ly: float, rx: float, dpad_ly: float, dpad_rx: float) -> String:
	var v := clampf(ly + dpad_ly, -1.0, 1.0)
	var h := clampf(rx + dpad_rx, -1.0, 1.0)
	return Player.axes_to_command(v, h)

func _axes_to_command(ly: float, rx: float) -> String:
	return Player.axes_to_command(ly, rx)

## Dirección sostenida actual: palancas únicas (LS avance · RS giro) + cruzeta
## digital + teclado. En Android get_connected_joypads() puede devolver [] aunque
## el pad responda en el id 0 (get_joy_axis funciona) → se barren ids 0..3.
func _held_dir() -> String:
	var a := _held_axes()
	var dp := _held_dpad()
	var cmd := Player.axes_dpad_to_command(a.y, a.x, dp.y, dp.x)
	if cmd != "":
		return cmd
	var k := Vector2.ZERO
	if Input.is_action_pressed(&"move_forward"):
		k.y -= 1.0
	if Input.is_action_pressed(&"move_back"):
		k.y += 1.0
	if Input.is_action_pressed(&"turn_left"):
		k.x -= 1.0
	if Input.is_action_pressed(&"turn_right"):
		k.x += 1.0
	if k.length_squared() < 0.25:
		return ""
	if absf(k.y) >= absf(k.x):
		return "back" if k.y > 0.0 else "fwd"
	return "right" if k.x > 0.0 else "left"

## Pads candidatos: lista conectada + ids 0..3 (respaldo Android).
func _candidate_pads() -> PackedInt32Array:
	var ids := Input.get_connected_joypads()
	for id in range(4):
		if not ids.has(id):
			ids.append(id)
	return ids

## Primer pad con ejes vivos (LY, RX); ZERO si ninguno supera la zona muerta.
func _held_axes() -> Vector2:
	for id in _candidate_pads():
		var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		if absf(ly) > AXIS_DEADZONE or absf(rx) > AXIS_DEADZONE:
			return Vector2(ly, rx)
	return Vector2.ZERO

## Cruzeta digital (D-pad): flechas con la misma convención que las palancas
## (x = eje de giro, y = eje de avance; arriba/izquierda = negativo). Primera
## pad candidata con botones de cruzeta presionados.
func _held_dpad() -> Vector2:
	for id in _candidate_pads():
		var d := Vector2.ZERO
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP):
			d.y -= 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN):
			d.y += 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT):
			d.x -= 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT):
			d.x += 1.0
		if d != Vector2.ZERO:
			return d
	return Vector2.ZERO

# Depuración visual (modo contraste alto en fase posterior).
# Paleta de alto contraste para visión reducida: cuerpo naranja brillante con
# borde blanco; la flecha BLANCA marca el "adelante" (nariz del cuerpo, -Y
# local) — es lo más luminoso en pantalla; la brújula MAGENTA siempre apunta
# al OESTE del mundo. Nada depende de distinguir rojo/verde.
func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(0.98, 0.58, 0.1))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0), 2.0)
	# Adelante: la nariz es el eje local -Y (forward_angle gira el nodo para que
	# (0,-1) local apunte a facing en el mundo → la flecha acompaña el giro).
	var perp := Vector2(0, -1).rotated(PI / 2.0)
	var tip := Vector2(0, -1) * 36.0
	draw_colored_polygon(
		PackedVector2Array([Vector2.ZERO, tip + perp * 10.0, tip - perp * 10.0]),
		Color(1.0, 1.0, 1.0)
	)
	draw_circle(tip, 5.0, Color(1.0, 1.0, 1.0))
	# Brújula OESTE: fija en pantalla (al mundo), sin importar el giro del rover.
	var west := west_local()
	var w_perp := west.rotated(PI / 2.0)
	draw_line(Vector2.ZERO, west * 21.0, Color(1.0, 0.4, 0.85), 4.0)
	draw_colored_polygon(
		PackedVector2Array([
			west * 30.0,
			west * 21.0 + w_perp * 8.0,
			west * 21.0 - w_perp * 8.0,
		]),
		Color(1.0, 0.4, 0.85)
	)

## Dirección local (espacio del cuerpo) del OESTE del mundo: se usa para dibujar
## la brújula, que debe permanecer fija al mundo aunque el rover gire.
func west_local() -> Vector2:
	return Vector2(-1, 0).rotated(-rotation)
