extends Node2D

## Orquestador principal — Fase 2 (retoque escenario):
## - Buses de audio (Ambiente / SFX / Voz) + layout desde default_bus_layout.tres
## - Viento de superficie (loop procedural)
## - Movimiento en grilla (MapGrid 16×9 = ventana completa) + sonidos de paso y bloqueo
## - ALREDEDORES (LB / R): voz que nombra la roca más cercana y su dirección relativa
## - ESPECTRÓMETRO (RT / E): chirrido → voz → contenedor (muestra guardada)
## - Base-cápsula: inicio de la misión y punto de entrega (victoria al volver con todas las muestras)
## - Sonar de geometría (pulso) y vara: removidos por ahora (se re-evalúan)
## - Sin beacons Geiger (removidos temporalmente) · sin cráteres

@onready var _player: Player = $Player
@onready var _debug_label: Label = $DebugLabel

## Misión v1: recolectar TODAS las muestras catalogables (basalto y regolito)
## y volver a la base. El rover arranca EN la base; las rocas recolectadas
## dejan de detectarse (alrededores y espectrómetro) y liberan su casilla.
const SPAWN_CELL := Vector2i(13, 1)
const BASE_CELL := Vector2i(13, 1)

var grid := MapGrid.new()

var _wind_player: AudioStreamPlayer
var _step_player: AudioStreamPlayer
var _blocked_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _spectro_player: AudioStreamPlayer
var _container_player: AudioStreamPlayer
var _turn_player: AudioStreamPlayer

var _rt_down := false

## Diagnóstico de gamepad (Android): primer pad conectado + readout temporal.
var _debug_pad := -1
var _pad_readout_until := 0.0
var _base_label_text := ""
## Picos de ejes para detectar rango acotado (pads Android con recorrido corto).
var _peak_ly := 0.0
var _peak_rx := 0.0
var _peak_rt := 0.0
var _peak_dirty := false
var _last_peak_log := 0

# Mapping SDL opcional para pads no reconocidos por Godot en Android
# (formato: "guid,name,<campo>:<valor>,...,platform:Android"). Ver get_joy_guid().
const CUSTOM_JOY_MAPPINGS: PackedStringArray = []

var _rocks: Array[Node2D] = []
var _base: Node2D

## Por roca: node, cell, type (nombre en GDD), voice (palabra), catalogable, collected.
var _rock_data: Array[Dictionary] = []
var _collected := 0
var _catalog_count := 0
var _mission_done := false
var _spectro_busy := false
## Generación de la sesión: se incrementa al reiniciar para invalidar anuncios y
## análisis en vuelo (coroutines que quedaron en espera).
var _session := 0
var _hud_button: Button

func _ready() -> void:
	_setup_audio_buses()
	_build_grid()
	_build_bounds()
	_build_objects()

	_player.grid = grid
	_player.cell = SPAWN_CELL
	_player.position = grid.center(SPAWN_CELL)
	_player.step_taken.connect(_on_step_taken)
	_player.step_blocked.connect(_on_step_blocked)
	_player.turn_taken.connect(_on_turn_taken)
	queue_redraw()

	_step_player = _make_sfx_player(AudioLib.crunch())
	_blocked_player = _make_sfx_player(AudioLib.thud())
	_turn_player = _make_sfx_player(AudioLib.turn())
	_spectro_player = _make_sfx_player(AudioLib.spectro_chirp())
	_container_player = _make_sfx_player(AudioLib.container_kchk())

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voz"
	add_child(_voice_player)

	_wind_player = AudioStreamPlayer.new()
	_wind_player.bus = "Ambiente"
	_wind_player.stream = AudioLib.wind()
	_wind_player.volume_db = -4.0
	add_child(_wind_player)
	_wind_player.play()

	_debug_label.text = "MARTE SÓNICO — recolectá todas las muestras y volvé a la base · LB/R = alrededores · RT/E = espectrómetro · LS/RS = conducir"
	_base_label_text = _debug_label.text
	_setup_hud_button()

	# Mappings custom (pads no reconocidos) + diagnóstico de gamepads.
	for m in CUSTOM_JOY_MAPPINGS:
		Input.add_joy_mapping(m)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for pad in Input.get_connected_joypads():
		_on_joy_connection_changed(pad, true)

func _make_sfx_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = stream
	add_child(p)
	return p

## Botón del HUD para reiniciar toda la experiencia (esquina inferior derecha).
func _setup_hud_button() -> void:
	var btn := Button.new()
	btn.text = "REINICIAR EXPERIENCIA"
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(270, 46)
	btn.size = Vector2(270, 46)
	btn.position = Vector2(MapGrid.COLS * MapGrid.CELL - 270.0 - 12.0, MapGrid.ROWS * MapGrid.CELL - 46.0 - 12.0)
	btn.pressed.connect(_restart_experience)
	add_child(btn)
	_hud_button = btn

## Reinicio completo: la misión, las rocas, el rover y el HUD vuelven al estado
## inicial (spawn en la base, catálogo completo por recolectar). Los anuncios y
## análisis en vuelo quedan invalidados con _session.
func _restart_experience() -> void:
	_log_pad("RESTART experiencia")
	_session += 1
	_voice_player.stop()
	_spectro_player.stop()
	_collected = 0
	_catalog_count = 0
	_mission_done = false
	_spectro_busy = false
	for rock in _rock_data:
		rock.collected = false
		rock.node.visible = true
		grid.set_blocked(rock.cell, true)
		if rock.catalogable:
			_catalog_count += 1
	_player.reset_to(SPAWN_CELL, MapGrid.W)
	_debug_label.text = _base_label_text
	queue_redraw()

func _process(delta: float) -> void:
	_poll_right_trigger()

	if Input.is_action_just_pressed(&"interact"):
		_try_interact()
	if Input.is_action_just_pressed(&"surroundings"):
		_describe_surroundings()

	_update_pad_readout()

## Primer gamepad conectado (índice genérico, no hardcodeado a 0).
## Respaldo: en Android la lista puede llegar vacía aunque los ejes del id 0 respondan.
func _pad_id() -> int:
	if _debug_pad >= 0:
		return _debug_pad
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		return pads[0]
	for id in range(4):
		var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		var rt := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
		if absf(ly) > Player.AXIS_DEADZONE or absf(rx) > Player.AXIS_DEADZONE or rt > 0.4:
			return id
	return -1

## Imprime y anexa a user://gamepad.log (útil en Android sin adb).
func _log_pad(msg: String) -> void:
	print(msg)
	var f := FileAccess.open("user://gamepad.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line(msg)
		f.close()
	else:
		var g := FileAccess.open("user://gamepad.log", FileAccess.WRITE)
		if g != null:
			g.store_line(msg)
			g.close()

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_debug_pad = device
		_pad_readout_until = Time.get_ticks_msec() + 5000.0
		_peak_ly = 0.0
		_peak_rx = 0.0
		_peak_rt = 0.0
		_peak_dirty = false
		_last_peak_log = Time.get_ticks_msec()
		_log_pad("CONNECTED PADS=%s" % [Input.get_connected_joypads()])
		_log_pad("JOYPAD CONNECTED id=%d name=\"%s\" guid=\"%s\" known=%s" % [
			device, Input.get_joy_name(device), Input.get_joy_guid(device),
			Input.is_joy_known(device)])
	elif device == _debug_pad:
		_debug_pad = -1

## Muestra en el HUD los valores del pad por unos segundos (o mientras se mueve)
## y registra picos de ejes en el log (para medir el rango real en Android).
func _update_pad_readout() -> void:
	if _debug_pad == -1:
		return
	var id := _debug_pad
	var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
	var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
	var rt := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
	var la := absf(ly)
	var ra := absf(rx)
	var ta := absf(rt)
	if la > _peak_ly:
		_peak_ly = la
		_peak_dirty = true
	if ra > _peak_rx:
		_peak_rx = ra
		_peak_dirty = true
	if ta > _peak_rt:
		_peak_rt = ta
		_peak_dirty = true
	var now := Time.get_ticks_msec()
	if _peak_dirty and now - _last_peak_log >= 1000:
		_log_pad("AXIS PEAKS LY=%.3f RX=%.3f RT=%.3f" % [_peak_ly, _peak_rx, _peak_rt])
		_peak_dirty = false
		_last_peak_log = now
	var cmd := Player.axes_to_command(ly, rx)
	var stick_live := la > 0.1 or ra > 0.1 or rt > 0.1
	if now < _pad_readout_until or stick_live:
		var dev0 := ""
		var pads := Input.get_connected_joypads()
		if not pads.is_empty() and int(pads[0]) != id:
			dev0 = "\nID0=%d CMD=%s LY=%.2f RX=%.2f" % [
				pads[0], Player.axes_to_command(
					Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y),
					Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X)),
				Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y),
				Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X)]
		_debug_label.text = "JOYPAD %d · %s (known=%s)\nLY=%.2f RX=%.2f RT=%.2f · LB=%s · CMD=%s%s\n%s" % [
			id, Input.get_joy_name(id), Input.is_joy_known(id),
			ly, rx, rt,
			"pressed" if Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER) else "up",
			cmd, dev0,
			"guid=" + Input.get_joy_guid(id)]
	elif _debug_label.text.begins_with("JOYPAD"):
		_debug_label.text = _base_label_text

## Gatillo derecho: los pads reportan RT como eje (no como botón) → se sondea por eje.
func _poll_right_trigger() -> void:
	var pad := _pad_id()
	var rt := 0.0 if pad < 0 else Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)
	if rt > 0.4:
		if not _rt_down:
			_rt_down = true
			_try_interact()
	else:
		_rt_down = false

## ---- Paso y bloqueo ----

func _on_step_taken(cell: Vector2i) -> void:
	_log_pad("MOVE step cell=%s" % [cell])
	_step_player.pitch_scale = randf_range(0.85, 1.15)
	_step_player.play()
	if cell == BASE_CELL and _collected >= _catalog_count and not _mission_done:
		_mission_done = true
		_debug_label.text = "MISIÓN CUMPLIDA — %d muestras entregadas" % _collected
		_announce_mission_done()

func _on_step_blocked() -> void:
	_log_pad("MOVE blocked")
	_blocked_player.pitch_scale = randf_range(0.9, 1.1)
	_blocked_player.play()

## Giro: la etapa usada se panea al oído del lado del giro (izquierda → izq,
## derecha → der), "mayormente" en ese lado (80/20 en el propio WAV estéreo).
func _on_turn_taken(turn_left: bool) -> void:
	_log_pad("MOVE turn %s" % ("L" if turn_left else "R"))
	_turn_player.stream = AudioLib.turn_panned(turn_left)
	_turn_player.pitch_scale = randf_range(0.9, 1.1)
	_turn_player.play()

func _say(words: Array) -> void:
	if _voice_player.playing:
		return
	_voice_player.stream = AudioLib.speak_words(words)
	_voice_player.play()

## ---- ALREDEDORES (LB / R) ----

## Dirección relativa al cuerpo (facing): delante/detras/izquierda/derecha.
func _relative_dir(to_cell: Vector2i) -> String:
	var d := to_cell - _player.cell
	var f := _player.facing
	var r := MapGrid.turn_right(f)
	var fwd := d.x * f.x + d.y * f.y
	var rgt := d.x * r.x + d.y * r.y
	if absi(fwd) >= absi(rgt):
		return "delante" if fwd > 0 else "detras"
	return "derecha" if rgt > 0 else "izquierda"

func _cells_word(cells: int) -> String:
	return AudioLib.number_word(cells) if cells <= 15 else "muchas"

## Pasos desde la casilla actual hasta `to_cell` según el eje de `dir`:
## delante/detras = pasos al frente, izquierda/derecha = pasos laterales.
## Así la cantidad dicha coincide con la dirección nombrada ("a 2 casillas
## delante" = 2 pasos al frente, aunque la roca esté corrida 1 o 2 al costado).
func _steps_to(to_cell: Vector2i, dir: String) -> int:
	var d := to_cell - _player.cell
	var f := _player.facing
	var r := MapGrid.turn_right(f)
	var fwd := d.x * f.x + d.y * f.y
	var rgt := d.x * r.x + d.y * r.y
	match dir:
		"delante":
			return maxi(1, fwd)
		"detras":
			return maxi(1, -fwd)
		"derecha":
			return maxi(1, rgt)
		"izquierda":
			return maxi(1, -rgt)
	return 1

## Voz que nombra la roca más cercana dentro del área de barrido:
## cono hacia adelante de ~90° (mínimo 3 de ancho) que se ensancha al
## avanzar y crece hasta 5 casillas de ancho máximo.
func _describe_surroundings() -> void:
	# Con todas las muestras a bordo, el foco pasa a la base: LB guía el regreso.
	if _catalog_count > 0 and _collected >= _catalog_count and not _mission_done:
		_describe_base()
		return
	var f := _player.facing
	var r := MapGrid.turn_right(f)
	var nearest: Dictionary = {}
	var best := INF
	for block in _rock_data:
		if block.collected:
			continue
		var d: Vector2i = block.cell - _player.cell
		var fwd := d.x * f.x + d.y * f.y
		var lat := d.x * r.x + d.y * r.y
		if fwd < 0 or absi(lat) > mini(maxi(1, fwd), 2):
			continue
		var dist := Vector2(d).length_squared()
		if dist < best:
			best = dist
			nearest = block
	if nearest.is_empty():
		_debug_label.text = "ALREDEDOR: nada al frente"
		_say(["nada", "delante"])
		return
	# La distancia se reporta en pasos (eje de la dirección dicha), no en
	# distancia diagonal: 2 adelante + 1 al costado = "a 2 casillas delante".
	var dir := _relative_dir(nearest.cell)
	var cells := _steps_to(nearest.cell, dir)
	_debug_label.text = "ALREDEDOR: %s %s %d" % [nearest.type, dir, cells]
	_say(["roca", "de", nearest.voice, "a", _cells_word(cells), "casillas", dir])

## Modo guía: con todas las muestras, LB orienta hacia la base.
func _describe_base() -> void:
	if _player.cell == BASE_CELL:
		_debug_label.text = "BASE: estás en la base"
		_say(["base"])
		return
	var dir := _relative_dir(BASE_CELL)
	var cells := _steps_to(BASE_CELL, dir)
	_debug_label.text = "BASE %s %d" % [dir, cells]
	_say(["base", "a", _cells_word(cells), "casillas", dir])

## ---- Espectrómetro (RT / E) ----

func _nearest_rock_nearby() -> Dictionary:
	var best: Dictionary = {}
	var bd := 2
	for block in _rock_data:
		if block.collected:
			continue
		var dc := maxi(abs(block.cell.x - _player.cell.x), abs(block.cell.y - _player.cell.y))
		if dc <= 1 and dc < bd:
			bd = dc
			best = block
	return best

func _try_interact() -> void:
	if _spectro_busy:
		return
	var sess := _session
	var block := _nearest_rock_nearby()
	if block.is_empty():
		_debug_label.text = "NADA CERCA"
		return
	if not block.catalogable:
		_debug_label.text = "ENFRENTE: %s (decorativa, no catalogable)" % block.type
		_say(["roca", "de", block.voice, "no", "catalogable"])
		return
	_spectro_busy = true
	_spectro_player.pitch_scale = randf_range(0.95, 1.05)
	_spectro_player.play()
	await get_tree().create_timer(0.4).timeout
	if sess != _session:
		_spectro_busy = false
		return
	_say(["roca", "de", block.voice, "muestra", "analizada"])
	await get_tree().create_timer(1.5).timeout
	if sess != _session:
		_spectro_busy = false
		return
	block.collected = true
	_collected += 1
	# La roca recolectada deja de existir para la detección: desaparece y
	# libera su casilla (el camino de vuelta queda abierto).
	block.node.visible = false
	grid.set_blocked(block.cell, false)
	_container_player.pitch_scale = [1.0, 0.85, 1.2][mini(_collected - 1, 2)]
	_container_player.play()
	_debug_label.text = "MUESTRA %d DE %d — %s" % [_collected, _catalog_count, block.type]
	if _collected >= _catalog_count:
		_announce_all_collected()
	_spectro_busy = false

## Espera a que la voz termine (los anuncios nunca se cortan).
func _wait_voice_idle() -> void:
	while _voice_player.playing:
		await get_tree().process_frame

## Anuncio: todas las muestras recolectadas → volver a la base.
func _announce_all_collected() -> void:
	_debug_label.text = "MUESTRAS COMPLETAS — volver a la base"
	var sess := _session
	await _wait_voice_idle()
	if sess != _session:
		return
	_say(["todas", "las", "muestras", "recolectadas", "volver", "base"])

## Anuncio: misión cumplida al pisar la base con todas las muestras.
func _announce_mission_done() -> void:
	var sess := _session
	await _wait_voice_idle()
	if sess != _session:
		return
	_say(["mision", "cumplida"])

## ---- Mundo ----

func _build_grid() -> void:
	for x in MapGrid.COLS:
		grid.set_blocked(Vector2i(x, 0), true)
		grid.set_blocked(Vector2i(x, MapGrid.ROWS - 1), true)
	for y in MapGrid.ROWS:
		grid.set_blocked(Vector2i(0, y), true)
		grid.set_blocked(Vector2i(MapGrid.COLS - 1, y), true)

func _build_bounds() -> void:
	var w := MapGrid.COLS * MapGrid.CELL
	var h := MapGrid.ROWS * MapGrid.CELL
	var t := 60.0
	_add_wall(Vector2(w / 2.0, -t / 2.0), Vector2(w, t))
	_add_wall(Vector2(w / 2.0, h + t / 2.0), Vector2(w, t))
	_add_wall(Vector2(-t / 2.0, h / 2.0), Vector2(t, h))
	_add_wall(Vector2(w + t / 2.0, h / 2.0), Vector2(t, h))

func _add_wall(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

func _build_objects() -> void:
	# 5 rocas: 2 catalogables (basalto, regolito) + 3 decorativas.
	var rock_cells := [
		["BASALTO", Vector2i(4, 2), true],
		["OBSIDIANA", Vector2i(11, 3), false],
		["IGNEA-B", Vector2i(10, 6), false],
		["SEDIMENTARIA", Vector2i(7, 1), false],
		["REGOLITO", Vector2i(2, 6), true],
	]
	for r in rock_cells:
		var cell_pos: Vector2i = r[1]
		var rock := _add_rock(grid.center(cell_pos), 30.0, str(r[0]))
		_rocks.append(rock)
		grid.set_blocked(cell_pos, true)
		grid.set_kind(cell_pos, "rock")
		_rock_data.append({
			"node": rock,
			"cell": cell_pos,
			"type": str(r[0]),
			"voice": _voice_word(str(r[0])),
			"catalogable": bool(r[2]),
			"collected": false,
		})
		if r[2]:
			_catalog_count += 1

	_base = _add_base(grid.center(BASE_CELL), 60.0)
	grid.set_kind(BASE_CELL, "base")

func _voice_word(type_name: String) -> String:
	var dict := {
		"BASALTO": "basalto",
		"REGOLITO": "regolito",
		"IGNEA-B": "ignea",
		"SEDIMENTARIA": "sedimentaria",
		"OBSIDIANA": "obsidiana",
	}
	return dict.get(type_name, "roca")

func _add_rock(pos: Vector2, radius: float, type_name: String) -> Node2D:
	var rock := StaticBody2D.new()
	rock.collision_layer = 2
	rock.collision_mask = 0
	rock.position = pos
	rock.set_meta("kind", "rock")
	rock.set_meta("rock_name", type_name)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	rock.add_child(shape)
	add_child(rock)
	return rock

func _add_base(pos: Vector2, half: float) -> Node2D:
	var base := StaticBody2D.new()
	base.collision_layer = 2
	base.collision_mask = 0
	base.position = pos
	base.set_meta("kind", "base")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(half * 2, half * 2)
	shape.shape = rect
	base.add_child(shape)
	add_child(base)
	return base

func _draw() -> void:
	# Depuración visual (modo dev).
	var w := MapGrid.COLS * MapGrid.CELL
	var h := MapGrid.ROWS * MapGrid.CELL
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.1, 0.06, 0.03), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.25, 0.2, 0.1), false, 1.0)
	var line_color := Color(0.35, 0.28, 0.16, 0.5)
	for x in range(MapGrid.COLS + 1):
		var px := x * MapGrid.CELL
		draw_line(Vector2(px, 0), Vector2(px, h), line_color, 1.0)
	for y in range(MapGrid.ROWS + 1):
		var py := y * MapGrid.CELL
		draw_line(Vector2(0, py), Vector2(w, py), line_color, 1.0)
	# Celdas bloqueadas (paredes y rocas): sombreado
	var blocked_color := Color(0.55, 0.38, 0.2, 0.35)
	for c in grid.blocked_cells():
		var cell_rect := Rect2(c.x * MapGrid.CELL + 3, c.y * MapGrid.CELL + 3, MapGrid.CELL - 6, MapGrid.CELL - 6)
		draw_rect(cell_rect, blocked_color, true)
	for rock in _rocks:
		draw_circle(rock.position, 30.0, Color(0.7, 0.3, 0.1))
	if _base:
		draw_circle(_base.position, 50.0, Color(0.2, 0.5, 0.8))
		_draw_base_door(_base.position)

# Puerta de la cápsula — sólo figurada (sin función por ahora).
func _draw_base_door(base_pos: Vector2) -> void:
	var door_center := base_pos + Vector2(0, 45)
	draw_rect(Rect2(door_center - Vector2(28, 5), Vector2(56, 10)), Color(0.08, 0.1, 0.14), true)
	draw_rect(Rect2(door_center - Vector2(28, 5), Vector2(56, 10)), Color(0.55, 0.7, 0.85), false, 1.5)
	draw_line(door_center + Vector2(0, -3), door_center + Vector2(0, 3), Color(0.4, 0.55, 0.7), 1.5)

## ---- Audio buses ----

func _setup_audio_buses() -> void:
	if AudioServer.get_bus_count() < 4:
		while AudioServer.get_bus_count() < 4:
			AudioServer.add_bus()
		AudioServer.set_bus_name(1, "Ambiente")
		AudioServer.set_bus_name(2, "SFX")
		AudioServer.set_bus_name(3, "Voz")
	if AudioServer.get_bus_effect_count(1) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 350.0
		AudioServer.add_bus_effect(1, lp, 0)
