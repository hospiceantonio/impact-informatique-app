#!/usr/bin/env python3
# =========================================================
# Les icônes des catégories de BIZZOO (3.56)
#
# LES DOUZE DE L'IMAGE CHOISIE PAR L'ENSEIGNE, à l'identique
# (« docs/icones-categories-source.webp ») : rien n'est redessiné.
# Chaque icône est prise telle quelle dans sa tuile, sans le nom écrit
# dessous, et son fond bleu-gris est rendu transparent — « couleur vers
# alpha » : le bord adouci garde sa transparence exacte, et l'icône
# reposée sur le même fond redonne les mêmes pixels. Le grain de
# l'image autour du dessin est retiré.
#
# LES QUATRE QUE L'IMAGE N'A PAS (Bébé & Enfant, Sport & Loisirs,
# Livres & Éducation, Animaux), construites dans son style par
# « icones-categories-construites.mjs », passent par le même chemin.
#
# LES SEIZE SUR UN MÊME CARRÉ : aucune n'est agrandie plus qu'une
# autre, elles gardent entre elles les tailles de l'image. Elles vont
# dans les deux applications, « client/img/pictos/ » et
# « admin/img/pictos/ », en PNG de 192 px à 128 couleurs (quelques
# kilo-octets chacune).
#
#   node tools/icones-categories-construites.mjs /tmp/construites
#   python3 tools/icones-categories.py docs/icones-categories-source.webp /tmp/construites
#
# Il faut Pillow (python3 -m pip install Pillow), et Playwright pour
# le premier pas.
# =========================================================
import os
import sys

from PIL import Image, ImageFilter

COLS = [(59, 362), (399, 705), (741, 1048), (1083, 1388)]
ROWS = [(60, 364), (388, 701), (721, 1030)]
NOMS = [["alimentation", "restauration", "mode", "beaute"],
        ["telephones", "informatique", "electromenager", "maison-deco"],
        ["auto-moto", "sante", "immobilier", "services"]]


def fond_de(tuile):
    px = tuile.load()
    w = tuile.size[0]
    echant = [px[x, 12][:3] for x in range(40, w - 40)]
    return tuple(sorted(c[k] for c in echant)[len(echant) // 2] for k in range(3))


def boite_du_dessin(tuile, fond):
    """Le cadre du pictogramme : la première bande encrée, sans le nom."""
    px = tuile.load()
    w, h = tuile.size
    # Les coins arrondis de la tuile sont transparents : ce n'est pas de l'encre.
    encre = lambda p: p[3] > 200 and max(abs(p[k] - fond[k]) for k in range(3)) > 40
    lignes = [any(encre(px[x, y]) for x in range(w)) for y in range(h)]
    debut = lignes.index(True)
    fin = debut
    while fin + 1 < h and lignes[fin + 1]:
        fin += 1
    colonnes = [x for x in range(w) if any(encre(px[x, y]) for y in range(debut, fin + 1))]
    # Quelques pixels de marge : le bord adouci du trait.
    m = 5
    return (max(0, colonnes[0] - m), max(0, debut - m),
            min(w, colonnes[-1] + 1 + m), min(h, fin + 1 + m))


def vers_alpha(img, fond):
    """« Couleur vers alpha » (celle de GIMP) : chaque pixel devient la
    couleur la plus opaque possible qui, posée sur le fond, le redonne."""
    src = img.convert("RGB").load()
    w, h = img.size
    out = Image.new("RGBA", (w, h))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            p = src[x, y]
            a = 0.0
            for k in range(3):
                b = fond[k]
                if p[k] < b:
                    a = max(a, (b - p[k]) / b)
                elif p[k] > b:
                    a = max(a, (p[k] - b) / (255 - b))
            if a < 0.03:  # le grain du fond, pas le dessin
                dst[x, y] = (0, 0, 0, 0)
                continue
            c = tuple(max(0, min(255, round((p[k] - (1 - a) * fond[k]) / a))) for k in range(3))
            dst[x, y] = c + (round(a * 255),)
    return out


def nettoyer(img):
    """Le grain de l'image d'origine laisse, autour du dessin, un voile de
    pixels presque transparents. Seul compte ce qui touche le trait : au
    plus trois pixels autour de ce qui est franchement dessiné."""
    alpha = img.getchannel("A")
    trait = alpha.point(lambda a: 255 if a > 128 else 0).filter(ImageFilter.MaxFilter(7))
    propre = Image.composite(alpha, Image.new("L", img.size, 0), trait)
    img.putalpha(propre.point(lambda a: 0 if a < 16 else a))
    return img


RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COTE_FINAL = 192


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage : python3 tools/icones-categories.py <image source> <dossier des construites>")
    source, construites = sys.argv[1], sys.argv[2]
    sorties = [os.path.join(RACINE, app, "img", "pictos") for app in ("client", "admin")]
    for sortie in sorties:
        os.makedirs(sortie, exist_ok=True)
    im = Image.open(source).convert("RGBA")
    dessins = []
    for j, (y0, y1) in enumerate(ROWS):
        for i, (x0, x1) in enumerate(COLS):
            tuile = im.crop((x0, y0, x1 + 1, y1 + 1))
            fond = fond_de(tuile)
            boite = boite_du_dessin(tuile, fond)
            dessin = nettoyer(vers_alpha(tuile.crop(boite), fond))
            dessins.append((NOMS[j][i], dessin))
            print(NOMS[j][i], "fond", fond, "dessin", dessin.size)
    for fichier in sorted(os.listdir(construites)):
        if fichier.endswith(".png"):
            img = Image.open(os.path.join(construites, fichier)).convert("RGBA")
            x0, y0, x1, y1 = img.getchannel("A").getbbox()
            m = 5
            dessin = img.crop((max(0, x0 - m), max(0, y0 - m), x1 + m, y1 + m))
            dessins.append((fichier[:-4], dessin))
            print(fichier[:-4], "(construite)", "dessin", dessin.size)
    # UN MÊME CARRÉ POUR LES SEIZE : le plus grand dessin le remplit
    # presque, les autres gardent leur taille relative de l'image.
    cote = max(max(d.size) for _, d in dessins) + 8
    for nom, dessin in dessins:
        carre = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
        carre.alpha_composite(dessin, ((cote - dessin.size[0]) // 2, (cote - dessin.size[1]) // 2))
        carre = carre.resize((COTE_FINAL, COTE_FINAL), Image.LANCZOS)
        # 128 couleurs suffisent largement à deux teintes et leurs bords
        # adoucis : le fichier tombe à quelques kilo-octets.
        carre = carre.quantize(colors=128, method=Image.Quantize.FASTOCTREE)
        for sortie in sorties:
            carre.save(os.path.join(sortie, nom + ".png"), optimize=True)
    print("carré commun", cote, "→", COTE_FINAL)


if __name__ == "__main__":
    main()
