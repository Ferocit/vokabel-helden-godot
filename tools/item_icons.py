"""Zeichnet eigene 16x16-Gegenstandssymbole im Stil von Kenney Tiny Dungeon nach assets/tiles/items.png.

Das Kenney-Set hat keine einzelnen Helme, deshalb sind die Helm-Symbole hier als Pixelraster beschrieben.
Jedes Symbol bekommt wie bei Kenney einen 2 px breiten dunklen Rand: gezeichnet wird mit 1 px Rand ('o'),
das Skript legt automatisch eine zweite Randschicht außen herum.

Aufruf (aus dem Projektordner):  python tools/item_icons.py
Reihenfolge der Kacheln = Index in Assets.ITEMS (siehe ui/assets.gd).
"""
from pathlib import Path

from PIL import Image

PALETTE = {
    "o": (63, 38, 49),      # Rand (wie Kenney)
    "W": (234, 240, 246),   # Glanzlicht
    "G": (192, 203, 220),   # Metall hell
    "g": (139, 155, 180),   # Metall mittel
    "k": (82, 96, 124),     # Metall dunkel
    "B": (189, 108, 74),    # Leder
    "b": (234, 165, 108),   # Leder hell
    "d": (140, 78, 56),     # Leder dunkel
    "R": (232, 69, 55),     # Rot
    "r": (168, 44, 48),     # Rot dunkel
    "Y": (247, 202, 92),    # Gold
    "y": (196, 132, 56),    # Gold dunkel
    "E": (96, 214, 150),    # Edelstein grün
}

ICONS = {
    "leather_cap": [
        "................",
        "................",
        "................",
        "................",
        "......oooo......",
        "....oobbBBoo....",
        "...obbBBBBBBo...",
        "...obBBBBBBdo...",
        "..obBBBBBBBBdo..",
        "..oBBBBBBBBBdo..",
        "..oBBBBBBBBddo..",
        ".oddddddddddddo.",
        ".oBbbbbbbbbbbBo.",
        "..oooooooooooo..",
        "................",
        "................",
    ],
    "apprentice_helm": [
        "................",
        "................",
        "................",
        "......oooo......",
        "....ooWGGgoo....",
        "...oWGGGGGggo...",
        "...oGGGGGgggo...",
        "..oGGGGGgggggo..",
        "..oGGGGggggggo..",
        "..okkkkkkkkkko..",
        "..okgkgkkgkgko..",
        "..ooooooGgoooo..",
        "......oGgo......",
        "......oGgo......",
        "......oooo......",
        "................",
    ],
    "healer_circlet": [
        "................",
        "................",
        "................",
        "................",
        ".......oo.......",
        "......oEEo......",
        "....ooEWEEoo....",
        "..ooYYoEEoYYoo..",
        ".oYYyyooooyyYYo.",
        ".oYyo......oyYo.",
        ".oYYoo....ooYYo.",
        "..ooYYYYYYYYoo..",
        "....oooooooo....",
        "................",
        "................",
        "................",
    ],
    "knight_helm": [
        "................",
        ".........ooo....",
        "........oRRRo...",
        ".......oRRrro...",
        ".....ooooRroo...",
        "....oWGGGgggo...",
        "...oWGGGGggggo..",
        "...oGGGGGggggo..",
        "...okkkkkkkkko..",
        "...ooooooooooo..",
        "...oGGGGgggggo..",
        "...oGkGkgkgkgo..",
        "...oGGGGgggggo..",
        "....oGGggggko...",
        ".....ooooooo....",
        "................",
    ],
}

ORDER = ["leather_cap", "apprentice_helm", "healer_circlet", "knight_helm"]


def draw(rows: list[str]) -> Image.Image:
    assert len(rows) == 16 and all(len(r) == 16 for r in rows), "Symbole müssen 16x16 sein"
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), PALETTE[ch] + (255,))
    # Zweite Randschicht: jedes leere Pixel neben einem Randpixel wird ebenfalls Rand.
    out = img.copy()
    edge = PALETTE["o"] + (255,)
    for y in range(16):
        for x in range(16):
            if img.getpixel((x, y))[3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 16 and 0 <= ny < 16 and img.getpixel((nx, ny)) == edge:
                    out.putpixel((x, y), edge)
                    break
    return out


def main() -> None:
    sheet = Image.new("RGBA", (16 * len(ORDER), 16), (0, 0, 0, 0))
    for i, name in enumerate(ORDER):
        sheet.paste(draw(ICONS[name]), (i * 16, 0))
    target = Path(__file__).resolve().parent.parent / "assets" / "tiles" / "items.png"
    sheet.save(target)
    print("geschrieben:", target)


if __name__ == "__main__":
    main()
