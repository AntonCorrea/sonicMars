"""Genera los WAV de voz del juego con ElevenLabs (una llamada por palabra o
frase).

Uso:
    python tools/elevenlabs_bake.py --voice-id <id> --out <carpeta>
    python tools/elevenlabs_bake.py --voice-id <id> --intro --out <carpeta>

La clave va en la variable de entorno ELEVENLABS_API_KEY o con --key.
Cada palabra (o frase de intro) se genera con el MISMO voice_id, modelo y
ajustes para que toda la voz suene consistente, y con seed fijo por clave
(estabilidad).

--intro hornea las 4 frases de la intro hablada (INTRO) como
assets/voice/intro_<clave>.wav (WAV por frase completa; va sin --words).

El juego (AudioLib._word_audio) sólo usa un WAV si es PCM 16-bit mono a
22050 Hz. Con output_format=wav_22050 ElevenLabs devuelve WAV PCM mono
16-bit 22050 Hz, así que sirve directo. Igual conviene verificar una muestra:
    python -c "import wave,sys; w=wave.open(sys.argv[1]); print(w.getnchannels(), w.getframerate(), w.getsampwidth())" assets/voice/basalto.wav
    (esperado: 1 22050 2)

IMPORTANTE (importación Godot): el importador de WAV de Godot 4.4 usa QOA por
defecto y la voz se escucharía como estática (AudioLib._wave_samples lee PCM).
Tras añadir/regenerar palabras, forzar PCM en los .import:
    Get-ChildItem assets\\voice\\*.wav.import | ForEach-Object {
        (Get-Content $_.FullName -Raw) -replace 'compress/mode=2','compress/mode=0' |
            Set-Content $_.FullName -NoNewline }
    (re-importar el proyecto)

Consejo: horneá primero a una carpeta temporal (--out tmp), escuchá una frase
y recién después volcá sobre assets/voice/ (guardate una copia de los WAV de
piper por si querés volver).

Nota de licencia: el uso comercial del audio generado requiere plan pago de
ElevenLabs; el plan gratuito no lo permite.
"""

import argparse
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

# clave (WORDS del juego) -> texto con ortografía correcta para el TTS
WORDS = {
    "roca": "roca", "de": "de", "a": "a", "casillas": "casillas",
    "basalto": "basalto", "regolito": "regolito", "brecha": "brecha",
    "ignea": "ígnea", "sedimentaria": "sedimentaria", "muestra": "muestra",
    "analizada": "analizada", "no": "no", "catalogable": "catalogable",
    "sin": "sin", "retorno": "retorno", "solido": "sólido", "plano": "plano",
    "base": "base", "nada": "nada", "cerca": "cerca", "delante": "delante",
    "detras": "detrás", "izquierda": "izquierda", "derecha": "derecha",
    "y": "y", "muchas": "muchas", "obsidiana": "obsidiana",
    "todas": "todas", "las": "las", "muestras": "muestras",
    "recolectadas": "recolectadas", "volver": "volver",
    "mision": "misión", "cumplida": "cumplida",
    "recogida": "recogida", "recoger": "recoger", "recogible": "recogible",
    "hay": "hay", "que": "que",
}

NUMS = ["uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho",
        "nueve", "diez", "once", "doce", "trece", "catorce", "quince"]

# Frases de la intro hablada (comienzo de cada partida) → WAV por frase completa
# (sintaxis natural, no concatenación palabra por palabra). Se hornean con
# --intro y quedan como assets/voice/intro_<clave>.wav.
INTRO = {
    "bienvenida": ("Bienvenido, astronauta. Este es Marte Sónico. "
                   "La vista no te va a hacer falta: todo lo que importa, "
                   "lo vas a escuchar."),
    "explicacion": ("Un juego de Marte que se juega con los oídos. "
                    "Cada sonido es una pista: la voz nombra la roca más "
                    "cercana y a cuántas casillas está. Buscá las muestras y "
                    "volvé a la base sin mirar la pantalla."),
    "quien_sos": ("Sos astronauta en Marte. Tu misión: recolectar basalto y "
                  "regolito. Encontrá las rocas, recogelas y volvé a la base "
                  "con todas las muestras."),
    "controles": ("Te dirigís con las palancas: la izquierda para girar, la "
                  "derecha para avanzar. El gatillo de alrededores escanea lo "
                  "que te rodea. El gatillo de recoger toma la roca que tengas "
                  "delante. Un botón, una acción."),
}

API = "https://api.elevenlabs.io/v1/text-to-speech"


def _stable_seed(base: int, key: str) -> int:
    return base + sum(ord(c) for c in key)


def _trim_wav_silence(path: pathlib.Path, keep_ms: int = 60,
                      threshold: int = 131) -> None:
    """Recorta el silencio de relleno (cabeza y cola) de un WAV PCM 16-bit.

    ElevenLabs agrega mucho relleno silencioso en wav_22050 (las frases de la
    intro miden 8-13 s con ~2 s de silencio). Como la intro se REPITE hasta que
    el jugador pulse un gatillo, conviene dejar el clip ágil: umbral de silencio
    0.004 (igual que AudioLib.SILENCE_THRESHOLD) y 60 ms de margen por lado.
    """
    import wave
    with wave.open(str(path), "rb") as w:
        params = w.getparams()
        frames = bytearray(w.readframes(params.nframes))
    if params.sampwidth != 2:
        return
    n = params.nframes
    step = params.nchannels
    keep = int(params.framerate * keep_ms / 1000.0)
    first = -1
    last = -1
    for i in range(n):
        amp = abs(int.from_bytes(
            frames[i * step * 2:(i * step + 1) * 2], "little", signed=True))
        if amp > threshold:
            if first < 0:
                first = i
            last = i
    if first < 0:
        return
    start = max(0, first - keep)
    end = min(n, last + 1 + keep)
    with wave.open(str(path), "wb") as w:
        w.setparams(params)
        w.writeframes(frames[start * step * 2:end * step * 2])


def _resample_wav_fast(path: pathlib.Path, factor: float) -> None:
    """Resample lineal (factor > 1 = más rápido) de un WAV PCM mono 16-bit.

    Mismo criterio que el juego (AudioLib.VOICE_SPEED = 1.15): la voz de la
    intro se acelera igual que las frases palabra-por-palabra, así el ritmo de
    toda la voz es coherente.
    """
    import struct
    import wave
    with wave.open(str(path), "rb") as w:
        params = w.getparams()
        frames = w.readframes(params.nframes)
    if params.sampwidth != 2 or params.nchannels != 1:
        return
    n = params.nframes
    n_out = int(n / factor)
    if n_out <= 0:
        return
    out = bytearray(n_out * 2)
    for i in range(n_out):
        src = i * factor
        i0 = int(src)
        i1 = min(i0 + 1, n - 1)
        a = int.from_bytes(frames[i0 * 2:(i0 + 1) * 2], "little", signed=True)
        b = int.from_bytes(frames[i1 * 2:(i1 + 1) * 2], "little", signed=True)
        v = int(a + (b - a) * (src - i0))
        out[i * 2:(i + 1) * 2] = struct.pack("<h", v)
    with wave.open(str(path), "wb") as w:
        w.setparams(params)
        w.writeframes(bytes(out))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice-id", required=True, help="ID de la voz en ElevenLabs")
    ap.add_argument("--out", default="assets/voice", help="carpeta de salida")
    ap.add_argument("--model", default="eleven_multilingual_v2",
                    help="modelo (es: eleven_multilingual_v2, eleven_v3)")
    ap.add_argument("--key", default=os.environ.get("ELEVENLABS_API_KEY", ""),
                    help="API key (o variable ELEVENLABS_API_KEY)")
    ap.add_argument("--seed", type=int, default=0, help="semilla base de consistencia")
    ap.add_argument("--words", default="",
                    help="sólo estas claves separadas por coma (test de un subconjunto); por defecto todas")
    ap.add_argument("--intro", action="store_true",
                    help="hornear las 4 frases de la intro (assets/voice/intro_*.wav) en vez de las palabras")
    ap.add_argument("--delay", type=float, default=0.5, help="pausa entre llamadas (s)")
    args = ap.parse_args()

    if not args.key:
        sys.exit("Falta la API key: ELEVENLABS_API_KEY o --key")

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    items = list(WORDS.items()) + [(n, n) for n in NUMS]
    if args.intro:
        items = [("intro_" + k, v) for k, v in INTRO.items()]
    elif args.words:
        sel = {w.strip() for w in args.words.split(",") if w.strip()}
        items = [it for it in items if it[0] in sel]
    url = f"{API}/{args.voice_id}?output_format=wav_22050"
    for key, text in items:
        dest = out / f"{key}.wav"
        if dest.exists():
            print(f"[skip] {key}")
            continue
        body = json.dumps({
            "text": text,
            "model_id": args.model,
            "voice_settings": {
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "speed": 1.0,
                "use_speaker_boost": True,
            },
            "seed": _stable_seed(args.seed, key),
        }).encode()
        req = urllib.request.Request(
            url, data=body, method="POST",
            headers={"xi-api-key": args.key, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                audio = r.read()
        except urllib.error.HTTPError as e:
            print(f"[error] {key}: HTTP {e.code} {e.read()[:200]!r}")
            continue
        dest.write_bytes(audio)
        if args.intro:
            _trim_wav_silence(dest)
            _resample_wav_fast(dest, 1.15)
        print(f"[bake] {key} -> {dest.name} ({len(audio)} bytes)")
        time.sleep(args.delay)

    print("Listo. Verificá una muestra con el probe wave y forzá PCM en los .import "
          "si reimportás sobre assets/voice/ (ver cabecera).")


if __name__ == "__main__":
    main()