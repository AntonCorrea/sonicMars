# Marte Sónico — Game Design Document

> Demo accesible audio-first de escritorio, complemento del proyecto Misiones Análogas (VR).
> Serious game · PC (Windows) · Godot 4 · Completar: juega con los ojos cerrados.
> Conecta con: `../MISIONES-ANALOGAS.md` (Eje 6 del plan de carrera) · `../EXPERIENCIAS-INSPIRACION.md` (impulse response, vara de Valencia Tales, beacons, sonar).

---

## 1. Concepto

Misión de recolección de muestras en la superficie de Marte, guiada por descripciones por voz y ecolocalización. El jugador conduce un rover (dirección diferencial), localiza las rocas con la **descripción de alrededores** y cataloga tres muestras con un espectrómetro. Toda la información vive en el audio: la pantalla es prescindible.

**Frase del juego:** "aprendiste a escuchar a Marte".

**Objetivo de diseño (KPI):** la misión se completa en Windows **con los ojos cerrados** (modo sin vista). Es el demostrable de accesibilidad del Eje 6 y la vitrina serious game de museo / Salta Game Expo.

---

## 2. Motor, plataforma e input

| Decide | Valor |
|---|---|
| Motor | Godot 4 (4.4+) — GDScript, render 2D + audio espacial |
| Plataforma | Windows desktop (export). Console de audio: auriculares (requerido) |
| Input primario | **Gamepad** (museo/feria, sin teclado visible) |
| Input respaldo | Teclado (desarrollo y PC) |
| Vista | Primera persona **egocéntrica** · **posición = vista** (sin eje de cámara extra) |
| Movimiento | **Grilla cartesiana** (celda 80 px · 16×9 = ventana completa 1280×720) · cada palanca replica el WASD: arriba=avanzar 1, abajo=retroceder, izq/der=girar 90° en eje · hold = repetición con cadencia |

### Mapa de input

| Gamepad | Teclado | Acción |
|---|---|---|
| LT | Q | Describir alrededores — roca más cercana con tipo, distancia y dirección relativa |
| LS (eje Y) · RS (eje X) | W/S · A/D | Conducir: **LS = avance/retroceso · RS = giro 90°** (funciones únicas) |
| RT | E | Interactuar / recoger muestra |
| Start | ESC | Menú / pausa |

> **LT sin asignar:** el sonar de geometría (pulso) y la vara se removieron en la demo; si la navegación a oscuras lo exige, son los primeros candidatos a reintroducir en el LT.

### Vehículo "tanque" en grilla (una sola referencia de mando)

El mundo se divide en **casillas de 80 px** (grilla 16×9 = 1280×720, encasillada en la ventana, paredes en el borde). El jugador vive en una casilla (`Vector2i`) y mira hacia un cardinal (N/S/E/O). Las palancas tienen **función única**: la izquierda conduce (avance/retroceso) y la derecha dirige (giro) — un esquema discreto de paso a paso:

| Gesto | Resultado |
|---|---|
| LS arriba | Avanza 1 casilla en el frente |
| LS abajo | Retrocede 1 casilla (mismo eje) |
| RS izquierda | Gira 90° a la izquierda (en el eje) |
| RS derecha | Gira 90° a la derecha |
| Mantener (hold) | Repite el paso/giro con cadencia fija (paso ~0.5 s, giro ~0.7 s) |

**Detalles:**
- Mientras se mueve, el último comando entra en **buffer** (slot único) y se ejecuta al llegar.
- Paso a casilla ocupada (roca, pared, borde) o fuera de grilla → **bloqueado** + sonido *golpe seco*.
- Base se puede pisar (zona, no colisión); las rocas son celdas bloqueadas.
- Interpolación suave (~0.18 s/casilla) + giro 90° con lerp; el dentro-de-celda queda estable para el conteo por pasos.
- Objetos anclados a centro de casilla → la narración habla en "casillas" ("roca a 2 casillas al este").

**Por qué grilla:** posiciones deterministas, narración audible exacta ("a X casillas"), colisión trivial, y aditividad para futuras mecánicas (geiger por distancia de casilla).

### Accesibilidad de input
- Cada botón = **una sola función** (sin tap/hold): LT = alrededores · RT = espectrómetro. Un solo gesto mental por acción.
- La misión se completa solo con **LT + RT** (y los pasos): garantía de accesibilidad (ojos cerrados).

---

## 3. Herramientas activas (v1)

| Herramienta | Gesto | Devuelve |
|---|---|---|
| **Alrededores** | LT / Q | Roca más cercana dentro de un cono frontal de ~90° (crece hasta 5 casillas de ancho): tipo + distancia + dirección relativa |
| **Espectrómetro** | RT / E | Recoge y cataloga la muestra de la roca adyacente |

> **Estado demo:** el sonar de geometría (pulso) y la vara (hold) fueron **removidos por ahora** para reducir a un gesto mental por botón; **LT se reasignó a alrededores** (Q en teclado). Si la navegación a oscuras lo exige, son los primeros candidatos a reintroducir. La voz de identificación vive en los alrededores; el apoyo de navegación es el **conteo de pasos** (crunch) y el **golpe seco** al bloquearse.

**Alrededores** — lectura de conciencia situacional cuando el jugador está perdido. Barre un **cono de ~90° hacia adelante** centrado en el jugador (mínimo 3 casillas de ancho en la fila del cuerpo) que se **ensancha al avanzar hasta 5 casillas de ancho máximo** — así cubre también los costados. Toma la **roca más cercana dentro de ese cono** y la nombra con su distancia y dirección **relativa al cuerpo**:
> "Roca de basalto a 2 casillas delante."

Direcciones **relativas al cuerpo** en v1 (sin brújula; con todas las muestras a bordo, LT orienta hacia la base).

---

## 4. Gramática sonora (el idioma del juego)

Reglas: **un sonido = una cosa** · nada musical durante la misión · **toda** línea narrativa cierra con fin de diálogo.

| # | Sonido | Forma | Función |
|---|---|---|---|
| 1 | **Fin de diálogo** | 2 notas descendentes (gota) | "Terminé de hablar, tu turno" |
| 2 | **Arpegio de menú** | 3 notas ascendentes (dk·dk·dk) | "Hay opciones scrolleables" |
| 3 | **Click de scroll** | click con tono que sube por índice | "Posición N de la lista" |
| 4 | **Thud de fin de lista** | golpe grave | "No hay más opciones" |
| 5 | **Ta-da de confirmación** | 2 tonos iguales rápidos | "Seleccionaste, seguimos" |
| 8 | **Eco de base** | retorno grave, retardado, casi inaudible | "El objetivo a la distancia" (reservado, Fase 3) |
| 9 | ~~Beacon de roca~~ | ~~click tipo Geiger~~ | **Removido por ahora** (se reevalúa en fase posterior) |
| 12 | **LT — roca más cercana** | voz relativa al cuerpo + cierre con fin de diálogo | "Dónde está la piedra más próxima" |
| 12b | **LT — guía de base** | voz base + dirección + distancia (activa con todas las muestras) | "El objetivo cambió: volvé al hogar" |
| 13 | **Espectrómetro activo** | chirrido de audio + silencio de suspenso | "Analizando…" |
| 14 | **Contenedor** | *kchk* — escala musical por muestra (1ª media, 2ª grave, 3ª aguda) | "Muestra guardada + progreso" |
| 15 | **Tono de base** | bajo grave constante, más grave = más cerca | "El hogar te llama" |
| 16 | **Viento de superficie** | profundo, ambiente | "Zona abierta / marco sonoro" |
| 17 | **Compuerta** | *chsss* | "Transición interior/exterior" |
| 18 | **Giro de orugas** | servo mecánico corto (barrido descendente), paneado al oído del lado del giro (izq/der) | "El cuerpo cambió de orientación" |
| 19 | **Aviso de muestras completas** | voz "todas las muestras recolectadas · volver base" | "Misión lograda; regresá" |
| 20 | **Misión cumplida** | voz "misión cumplida" | "Llegaste a la base con todo" |

> **Voz en runtime:** WAV pre-generados con **Piper** (español — `es_ES-davefx-medium`, 22050 Hz, vocabulario + números) concatenados por palabra con pausa de 0.09 s y normalización RMS. Si falta el audio de una palabra, cae a síntesis *formant* en tiempo real. Regenerar voces: `python tools/piper_bake.py --model <modelo.onnx> --out assets/voice` (escribe en `assets/voice/`).

---

## 5. Flujo de experiencia (paso a paso)

### 0 · Título
Viento marciano. Logo: **MARTE SÓNICO** · "experiencia de audio — usar auriculares".

### 1 · Menú principal (selección scrolleable #1)
Arpegio dk·dk·dk → el jugador aprende el idioma de la lista:
1. Comenzar misión
2. Narración completa / solo subtítulos
3. Instrucciones (repetir el idioma de sonidos)
4. Accesibilidad (modo sin vista, contraste alto, volumen de voz)
Scroll = click + nombre hablado · confirmar = ta-da · fin de lista = thud.

### 2 · Rampa (briefing)
Motor se apaga. Voz de Control Central con fondo de sala de control:
> "Base Harmony, aquí Control Central." [fin de diálogo]
> "Recolectá las dos muestras y volvé a la base." [fin de diálogo]
> "Localizá las rocas con los alrededores y recogelas con el espectrómetro. Cuando tengas todo, volvé." [fin de diálogo]
Compuerta *chsss* → reloj corre. Si no hace nada 10 s → subtítulo `[LT] alrededores · [RT] espectrómetro`.

### 3 · Salida a superficie
Pasos sobre regolito, viento. **Descubrimiento #1:** cada paso de regolito mide una casilla.

### 4 · Exploración
LT → voz: la roca más cercana dentro de la banda, con **dirección relativa** y **distancia en casillas** ("roca de basalto a 3 casillas izquierda"). Los pasos (crunch) permiten contar la distancia; el bloqueo (golpe seco) avisa del borde.

### 5 · El primer beacon
Click Geiger de una roca cercana. **Descubrimiento #2:** acercarse acelera el click → una aguja sonora. Precio: confirmar con **LT** al llegar.

### 6 · Espectrómetro
RT/E cerca de la roca → chirrido → silencio → voz descripción → contenedor *kchk* → `✓ Muestra 1 de 2`. Las rocas recolectadas desaparecen, liberan su casilla y dejan de detectarse.

5 rocas: 2 catalogables con tipos y voces distintas (basalto en el cuadrante norte · regolito con óxidos al sur) y 3 decorativas (obsidiana al este, ígnea-B, sedimentaria al norte). La brecha de impacto ya no forma parte de la demo.

### 7 · Cápsula y puerta
La base-cápsula es el **punto de inicio de la misión** y la meta: al llegar con todas las muestras se declara la misión cumplida. La puerta sigue figurada (transición interior/exterior, Fase 3).

### 8 · Tornada
Con todas las muestras a bordo, **LT deja de buscar rocas y guía hacia la base** ("base a 3 casillas delante") y se anuncia "todas las muestras recolectadas · volver base". El jugador combina: pasos para medir la distancia y LT para reorientarse.

### 9 · Base
Al pisar la base con todo a bordo → **MISIÓN CUMPLIDA** (voz "misión cumplida" + HUD). El menú scrolleable de resumen y la entrega formal de muestras son Fase 4.

### 10 · Resumen (selección scrolleable #2)
1. Repetir misión
2. Ver catálogo de muestras (scroll: cada muestra suena su espectrómetro + la voz la describe)
3. Menú principal

### 11 · Cierre
"La superficie de Marte sigue ahí afuera. Siempre esperando a alguien que la escuche." [fin de diálogo] → créditos + nota real: "Las misiones análogas son simulaciones de misiones espaciales que se realizan en la Tierra para preparar las reales (NASA/ESA)."

---

## 6. Los 3 descubrimientos (sin tutorial)

1. **El regolito mide el paso** → cada crunch es una casilla; los pasos son la regla de distancia.
2. **LT es la brújula** → la roca más cercana siempre se orienta respecto al cuerpo.
3. **El tono grave es el hogar** → la base es un faro (Fase 3).
(El espectrómetro cataloga; el sonar de geometría/vara se re-evalúan fuera de la demo.)

---

## 7. Accesibilidad (garantías)

- **Audio-first:** toda información por sonido y voz; subtítulos siempre visibles.
- **Modo sin vista:** pantalla apagada; la misión se completa con LT (alrededores + guía de base) + RT (espectrómetro) + pasos.
- **Contraste alto:** modo gráfico de formas grandes de color para baja visión (polish).
- **Input simple:** cada botón = una sola acción (LT alrededores · RT espectrómetro).
- **HUD:** subtítulos visibles + botón **REINICIAR EXPERIENCIA** (esquina inf. derecha) que vuelve misión, rocas y rover al arranque e invalida análisis/anuncios en vuelo.
- **Sin presión:** 4 minutos configirables; modo "sin estrés" opcional (sin reloj).

---

## 8. Alcance v1 y criterio de "listo"

**Alcance:**
- 1 nivel: campo abierto con 5 rocas (2 a recolectar: basalto + regolito) + 3 decorativas + 1 base-cápsula (inicio y meta).
- 2 tipos catalogables con descripción por voz (WAV Piper); decorativas identificables pero no recolectables.
- Alrededores (LT) · espectrómetro (RT) · misión "recolectá todo y volvé a la base" · menús scrolleables (Fase 4). (Sonar de geometría y vara: fuera de la demo, se re-evalúan.)
- Audio procedural + voces por palabra pre-generadas con Piper (WAV en `assets/voice/`).
- Gamepad + teclado · export Windows.

**Fuera de alcance v1 (polish):** modo contraste alto gráfico, catálogo completo, música en menú, brújula cardinal, mouse-look.

**Criterio de "listo":** la misión de 5 min se completa en Windows con gamepad **con los ojos cerrados**, sin ayuda del equipo.

---

## 9. Roadmap de construcción

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Scaffold Godot: project.godot, input maps, buses de audio (Ambiente/SFX/Voz), export Windows | ✅ |
| 1 | Movimiento diferencial + viento ambiente + picho/eco (audio espacial) | ✅ |
| 2 | Rocas + beacon Geiger + spectrómetro (descripción voz + contenedor) | ✅ |
| 3 | Misión completa: win al volver con todas las muestras a la base + guía por LT · falta reloj/compuerta | 🟡 parcial |
| 4 | Menús scrolleables + narración + gramática de selección + accesibilidad | 🔲 |
| 5 | Pulido, build .exe, playtest externo (ojos cerrados), unidad con museo/Expo | 🔲 |

*Documento de diseño del proyecto Misiones Análogas · Sección 4.2 (serious game gamificado) y KPI "demo accesible functional" del plan de carrera.*