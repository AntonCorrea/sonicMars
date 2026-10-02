"""Genera los WAV de voz del juego con ElevenLabs (una llamada por palabra).

Uso:
    python tools/elevenlabs_bake.py --voice-id <id> --out <carpeta>

La clave va en la variable de entorno ELEVENLABS_API_KEY o con --key.
Cada palabra se genera con el MISMO voice_id, modelo y ajustes para que toda
la voz suene consistente, y con seed fijo por palabra (estabilidad).

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
}

NUMS = ["uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho",
        "nueve", "diez", "once", "doce", "trece", "catorce", "quince"]

API = "https://api.elevenlabs.io/v1/text-to-speech"


def _stable_seed(base: int, key: str) -> int:
    return base + sum(ord(c) for c in key)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice-id", required=True, help="ID de la voz en ElevenLabs")
    ap.add_argument("--out", default="assets/voice", help="carpeta de salida")
    ap.add_argument("--model", default="eleven_multilingual_v2",
                    help="modelo (es: eleven_multilingual_v2, eleven_v3)")
    ap.add_argument("--key", default=os.environ.get("ELEVENLABS_API_KEY", ""),
                    help="API key (o variable ELEVENLABS_API_KEY)")
    ap.add_argument("--seed", type=int, default=0, help="semilla base de consistencia")
    ap.add_argument("--delay", type=float, default=0.5, help="pausa entre llamadas (s)")
    args = ap.parse_args()

    if not args.key:
        sys.exit("Falta la API key: ELEVENLABS_API_KEY o --key")

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    items = list(WORDS.items()) + [(n, n) for n in NUMS]
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
        print(f"[bake] {key} -> {dest.name} ({len(audio)} bytes)")
        time.sleep(args.delay)

    print("Listo. Verificá una muestra con el probe wave y forzá PCM en los .import "
          "si reimportás sobre assets/voice/ (ver cabecera).")


if __name__ == "__main__":
    main()