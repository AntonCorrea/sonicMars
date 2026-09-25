class_name MapGrid
extends RefCounted

## Rejilla de juego cartesiana.
## Celda 80 px · grilla 16×9 (mundo 1280×720 = ventana completa, encasillada).
## Celdas bloqueadas (muros, rocas) o zonas (base).
## Direcciones cardinales en coordenadas de pantalla (y hacia abajo).

const CELL := 80
const COLS := 16
const ROWS := 9

const N := Vector2i(0, -1)
const S := Vector2i(0, 1)
const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)

var _blocked: Dictionary = {}
var _kinds: Dictionary = {}

static func center(cell_pos: Vector2i) -> Vector2:
	return Vector2(cell_pos.x * CELL + CELL * 0.5, cell_pos.y * CELL + CELL * 0.5)

static func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))

static func is_inside(cell_pos: Vector2i) -> bool:
	return cell_pos.x >= 0 and cell_pos.x < COLS and cell_pos.y >= 0 and cell_pos.y < ROWS

func is_blocked(cell_pos: Vector2i) -> bool:
	if not is_inside(cell_pos):
		return true
	return _blocked.get(cell_pos, false)

func set_blocked(cell_pos: Vector2i, blocked: bool) -> void:
	_blocked[cell_pos] = blocked

func set_kind(cell_pos: Vector2i, kind: String) -> void:
	_kinds[cell_pos] = kind

func kind_at(cell_pos: Vector2i) -> String:
	return _kinds.get(cell_pos, "")

func blocked_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in _blocked.keys():
		out.append(k as Vector2i)
	return out

static func turn_left(f: Vector2i) -> Vector2i:
	return Vector2i(f.y, -f.x)

static func turn_right(f: Vector2i) -> Vector2i:
	return Vector2i(-f.y, f.x)

static func angle_of(f: Vector2i) -> float:
	return Vector2(f).angle()

static func forward_angle(f: Vector2i) -> float:
	## Ángulo que debe tener un Node2D para que su eje local -Y (arriba) apunte a f.
	## Es la única representación coherente con Vector2(0,-1).rotated(rotation) == Vector2(f).
	return Vector2(f).angle() + PI / 2.0