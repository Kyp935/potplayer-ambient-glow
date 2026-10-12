"""Generate the PotPlayer shader files from the template."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "PxShader"
template = (HERE / "ambient_glow_template.hlsl").read_text()

COMMON_USAGE = [
    "//   Copy into PotPlayer's PxShader folder, then right-click the video >",
    "//   Video > Pixel Shaders and add it to the POST-resize (after resizing) list.",
]

AUTO_USAGE = [
    "//   Finds where the picture starts each frame, so it also handles 4:3,",
    "//   1.85:1 and 2:1 videos. In very dark scenes it can occasionally spill",
    "//   into black areas at the picture's edge; the 16-9 file never does.",
]

# How much of the bar the glow fills.
FULLER = dict(FALLOFF="0.60", REACH="1.40", SOFTNESS="0.14")
FULLEST = dict(FALLOFF="0.50", REACH="2.00", SOFTNESS="0.16")

VARIANTS = {
    "Ambient Glow 16-9.txt": dict(
        TITLE="16:9 videos",
        ASPECT_MODE="0",
        CONTENT_AR="(16.0 / 9.0)",
        STRETCHED="0",
        USAGE=COMMON_USAGE + [
            "//   Play fullscreen. It only lights bars that are truly empty, so it stays",
            "//   off for 2.39:1 films that already fill the screen.",
        ],
        **FULLER,
    ),
    "Ambient Glow Auto.txt": dict(
        TITLE="any aspect ratio",
        ASPECT_MODE="1",
        CONTENT_AR="(16.0 / 9.0)",
        STRETCHED="0",
        USAGE=COMMON_USAGE + AUTO_USAGE,
        **FULLER,
    ),
    "Ambient Glow Auto Max.txt": dict(
        TITLE="any aspect ratio, fills the bars almost completely",
        ASPECT_MODE="1",
        CONTENT_AR="(16.0 / 9.0)",
        STRETCHED="0",
        USAGE=COMMON_USAGE + AUTO_USAGE + [
            "//   Same as Ambient Glow Auto, but the glow reaches almost all the way",
            "//   to the screen edge instead of darkening towards it.",
        ],
        **FULLEST,
    ),
    "Ambient Glow Stretch 16-9.txt": dict(
        TITLE="plan B for stretched video",
        ASPECT_MODE="0",
        CONTENT_AR="(16.0 / 9.0)",
        STRETCHED="1",
        USAGE=COMMON_USAGE + [
            "//   Only use this if the other files show no glow (PotPlayer's renderer",
            "//   didn't pass the black bars to the shader). Set PotPlayer's aspect ratio",
            "//   to stretch the video to the screen; this shader puts the 16:9 shape",
            "//   back and fills the sides. For 4:3 videos, set CONTENT_AR to (4.0 / 3.0).",
        ],
        **FULLER,
    ),
}

OUT.mkdir(exist_ok=True)
for name, v in VARIANTS.items():
    text = template
    text = text.replace("%%USAGE%%", "\n".join(v["USAGE"]))
    for key in ("TITLE", "ASPECT_MODE", "CONTENT_AR", "STRETCHED", "FALLOFF", "REACH", "SOFTNESS"):
        text = text.replace(f"%%{key}%%", v[key])
    assert "%%" not in text, name
    # Windows line endings so it opens cleanly in Notepad
    (OUT / name).write_bytes(text.replace("\n", "\r\n").encode("ascii"))
    print("wrote", OUT / name)
