#!/usr/bin/env python3
"""Gera um vídeo de digital rain estilo Matrix, em loop perfeito.

O loop é exato: a velocidade de cada coluna é escolhida para que ela
complete um número inteiro de ciclos no total de quadros. Assim o último
quadro emenda no primeiro sem salto visível.

Uso:
    make-matrix-video.py [-o saida.mp4] [--width 1920] [--height 1080]
                         [--fps 30] [--seconds 12] [--font-size 22]

Requer: python3-pil e ffmpeg.
"""
import argparse
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CHARS = (
    "アイウエオカキクケコサシスセソタチツテトナニヌネノ"
    "ハヒフヘホマミムメモヤユヨラリルレロワヲン"
    "0123456789"
    "=+-*/<>|_"
)

# A fonte PRECISA ter katakana. JetBrains Mono / DejaVu não têm CJK e
# renderiam tofu (▯) silenciosamente — por isso Noto Sans Mono CJK vem
# primeiro. O índice é a face dentro do .ttc (5 = "Noto Sans Mono CJK JP").
FONT_CANDIDATES = [
    (Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"), 5),
    (Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"), 5),
    (Path("/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"), 0),
]

# Gradiente da cauda: cabeça quase branca, corpo verde neon, fim escuro.
HEAD = (200, 255, 230)
BODY = (0, 255, 156)
TAIL = (0, 60, 42)


def renders_katakana(font: ImageFont.FreeTypeFont) -> bool:
    """Detecta tofu: compara 'ア' com um codepoint garantidamente ausente.

    Se os dois desenham o mesmo pixel-a-pixel, a fonte está caindo no
    glifo de fallback e o vídeo sairia cheio de quadradinhos.
    """
    missing = "\U000f0000"  # área de uso privado, sem glifo real
    a = font.getmask("ア", mode="L")
    b = font.getmask(missing, mode="L")
    if bytes(a) == bytes(b):
        return False
    return a.getbbox() is not None


def pick_font(size: int) -> ImageFont.FreeTypeFont:
    tried = []
    for path, index in FONT_CANDIDATES:
        if not path.exists():
            continue
        font = ImageFont.truetype(str(path), size, index=index)
        if renders_katakana(font):
            return font
        tried.append(f"{path.name}[{index}] ({font.getname()[0]}) sem katakana")
    raise SystemExit(
        "Nenhuma fonte com katakana encontrada.\n  "
        + "\n  ".join(tried or ["nenhuma candidata existe no sistema"])
        + "\nInstale com: sudo apt install fonts-noto-cjk"
    )


def lerp(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))


def build_glyph_cache(font, levels, cell_w, cell_h):
    """Pré-renderiza cada caractere em cada nível de brilho.

    Desenhar texto é caro; colar tiles prontos é ordens de magnitude
    mais rápido, o que viabiliza centenas de quadros.
    """
    cache = []
    for i in range(levels):
        t = i / max(levels - 1, 1)
        # 0 = fim da cauda (escuro), 1 = cabeça (clara)
        color = lerp(TAIL, BODY, min(t * 1.6, 1.0)) if t < 0.75 else lerp(BODY, HEAD, (t - 0.75) / 0.25)
        level = {}
        for ch in CHARS:
            tile = Image.new("RGB", (cell_w, cell_h), (0, 0, 0))
            d = ImageDraw.Draw(tile)
            d.text((cell_w // 2, cell_h // 2), ch, font=font, fill=color, anchor="mm")
            level[ch] = tile
        cache.append(level)
    return cache


def main() -> None:
    p = argparse.ArgumentParser()
    # Mesma pasta que o menu do lockvideo.sh (SUPER + I) lista, para o vídeo
    # gerado já aparecer entre as opções.
    p.add_argument("-o", "--output", default=str(Path.home() / "Vídeos/video_wallpaper/matrix-rain.mp4"))
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--seconds", type=int, default=12)
    p.add_argument("--font-size", type=int, default=22)
    p.add_argument("--levels", type=int, default=12)
    p.add_argument("--seed", type=int, default=1337)
    p.add_argument(
        "--blur",
        type=float,
        default=10.0,
        help="Sigma do blur assado no vídeo (0 desliga). Assar é de graça em "
        "runtime; filtrar ao vivo no mpv custaria CPU todo quadro.",
    )
    args = p.parse_args()

    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg não encontrado. Instale com: sudo apt install ffmpeg")

    random.seed(args.seed)

    font = pick_font(args.font_size)
    cell_w = max(font.getbbox("W")[2], args.font_size // 2 + 2) + 2
    cell_h = args.font_size + 6

    cols = args.width // cell_w
    rows = args.height // cell_h + 1
    frames = args.fps * args.seconds

    cache = build_glyph_cache(font, args.levels, cell_w, cell_h)

    # Estado por coluna. `period` é a distância total do ciclo; escolher
    # `cycles` inteiro garante o loop perfeito.
    columns = []
    for _ in range(cols):
        trail = random.randint(6, 22)
        period = rows + trail
        cycles = random.randint(1, 3)
        columns.append(
            {
                "trail": trail,
                "period": period,
                "speed": cycles * period / frames,
                "offset": random.uniform(0, period),
                # cada linha da coluna tem seu caractere, trocado esporadicamente
                "chars": [random.choice(CHARS) for _ in range(period)],
                "active": random.random() > 0.18,
            }
        )

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{args.width}x{args.height}", "-r", str(args.fps),
        "-i", "-",
    ]
    if args.blur > 0:
        # gblur precisa de sigma e steps; steps maior = gaussiana mais fiel
        cmd += ["-vf", f"gblur=sigma={args.blur}:steps=3"]
    cmd += [
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-crf", "20", "-preset", "medium",
        "-movflags", "+faststart", "-an",
        str(out),
    ]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    canvas = Image.new("RGB", (args.width, args.height), (0, 0, 0))
    black = Image.new("RGB", (cell_w, cell_h), (0, 0, 0))

    for f in range(frames):
        canvas.paste(black.resize((args.width, args.height)), (0, 0))
        for cx, col in enumerate(columns):
            if not col["active"]:
                continue
            head = (col["offset"] + f * col["speed"]) % col["period"]
            hi = int(head)
            for k in range(col["trail"]):
                ry = hi - k
                if ry < 0 or ry >= rows:
                    continue
                t = 1.0 - (k / col["trail"])
                lvl = min(int(t * args.levels), args.levels - 1)
                ch = col["chars"][ry % col["period"]]
                canvas.paste(cache[lvl][ch], (cx * cell_w, ry * cell_h))
        ff.stdin.write(canvas.tobytes())
        if f % max(frames // 10, 1) == 0:
            print(f"  {100 * f // frames}%", file=sys.stderr, flush=True)

    ff.stdin.close()
    rc = ff.wait()
    if rc != 0:
        raise SystemExit(f"ffmpeg falhou com código {rc}")

    print(f"OK: {out}  ({out.stat().st_size / 1e6:.1f} MB, {frames} quadros, loop exato)")


if __name__ == "__main__":
    main()
