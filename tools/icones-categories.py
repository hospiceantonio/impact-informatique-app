#!/usr/bin/env python3
# =========================================================
# Les icônes des catégories de BIZZOO (3.56)
#
# TROIS PLANCHES CHOISIES PAR L'ENSEIGNE, reprises à l'identique :
# rien n'est redessiné ni recoloré.
#   - « docs/icones-categories-source.webp » : les douze premières,
#     sur des tuiles bleu-gris (Alimentation … Services) ;
#   - « docs/icones-categories-source-2.jpg » et « -3.jpg » : vingt-deux
#     autres, sur des tuiles blanches (Bébé & Enfants … Formation &
#     Cours, plus un tracteur et des cartons de rechange).
# Chaque icône est prise telle quelle dans sa tuile, sans le nom écrit
# dessous, et le fond de la tuile est rendu transparent — « couleur vers
# alpha » : le bord adouci garde sa transparence exacte, et l'icône
# reposée sur le même fond redonne les mêmes pixels. Le grain de
# l'image autour du dessin est retiré.
#
# LA MÊME TAILLE POUR TOUTES. Les planches n'ont pas la même échelle :
# celles des planches blanches sont ramenées à la taille médiane des
# douze premières, chacune gardant sa taille relative à ses voisines de
# planche. Toutes se posent sur le carré des douze premières : celles-ci
# restent identiques au pixel près, et la rare icône plus large que ce
# carré (la camionnette, le tracteur) y est ramenée.
#
# Elles vont dans les deux applications, « client/img/pictos/ » et
# « admin/img/pictos/ », en PNG de 192 px à 128 couleurs (quelques
# kilo-octets chacune).
#
#   python3 tools/icones-categories.py
#
# Il faut Pillow (python3 -m pip install Pillow).
# =========================================================
import os
import statistics

from PIL import Image, ImageFilter

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COTE_FINAL = 192

# Chaque planche : son image, les bornes de ses tuiles (en pixels), le
# nom de l'icône de chaque tuile (None : pas de tuile à cet endroit).
PLANCHES = [
    {"source": "docs/icones-categories-source.webp", "blanche": False,
     "lignes": [(60, 364), (388, 701), (721, 1030)],
     "colonnes": [(59, 362), (399, 705), (741, 1048), (1083, 1388)],
     "noms": [["alimentation", "restauration", "mode", "beaute"],
              ["telephones", "informatique", "electromenager", "maison-deco"],
              ["auto-moto", "sante", "immobilier", "services"]]},
    {"source": "docs/icones-categories-source-2.jpg", "blanche": True,
     "lignes": [(28, 281), (301, 554), (574, 825)],
     "colonnes": [(71, 337), (362, 628), (653, 918), (944, 1210)],
     "noms": [["bebe-enfant", "sport-loisirs", "bijoux", "livres-education"],
              ["bricolage", "animaux", "agriculture", "cadeau"],
              [None, "bureau", "grossistes", None]]},
    {"source": "docs/icones-categories-source-3.jpg", "blanche": True,
     "lignes": [(30, 287), (303, 559), (576, 824)],
     "colonnes": [(31, 323), (342, 630), (649, 938), (957, 1249)],
     "noms": [["energie", "securite", "musique", "artisanat"],
              ["jardinage", "imprimante", "evenementiel", "materiel-pro"],
              ["transport", "formation", "tracteur", "cartons"]]},
]


def fond_de(tuile):
    px = tuile.load()
    w = tuile.size[0]
    echant = [px[x, 12][:3] for x in range(40, w - 40)]
    return tuple(sorted(c[k] for c in echant)[len(echant) // 2] for k in range(3))


def boite_du_dessin(tuile, fond):
    """Le cadre du pictogramme : tout ce qui est encré au-dessus du nom.
    Le nom, ce sont les dernières bandes encrées de la tuile, de la
    hauteur d'une ligne de texte (une ou deux lignes) ; un dessin en
    plusieurs morceaux (des étincelles, une guirlande) reste entier."""
    px = tuile.load()
    w, h = tuile.size
    # Les coins arrondis de la tuile sont transparents : ce n'est pas de l'encre.
    encre = lambda p: p[3] > 200 and max(abs(p[k] - fond[k]) for k in range(3)) > 40
    lignes = [any(encre(px[x, y]) for x in range(w)) for y in range(h)]
    bandes, debut = [], None
    for y, encree in enumerate(lignes + [False]):
        if encree and debut is None:
            debut = y
        elif not encree and debut is not None:
            bandes.append((debut, y))
            debut = None
    while len(bandes) > 1 and bandes[-1][1] - bandes[-1][0] <= 34:
        bandes.pop()
    haut, bas = bandes[0][0], bandes[-1][1]
    colonnes = [x for x in range(w) if any(encre(px[x, y]) for y in range(haut, bas))]
    # Quelques pixels de marge : le bord adouci du trait.
    m = 5
    return (max(0, colonnes[0] - m), max(0, haut - m),
            min(w, colonnes[-1] + 1 + m), min(h, bas + m))


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


def dessins_de(planche):
    im = Image.open(os.path.join(RACINE, planche["source"])).convert("RGBA")
    dessins = []
    for j, (y0, y1) in enumerate(planche["lignes"]):
        for i, (x0, x1) in enumerate(planche["colonnes"]):
            nom = planche["noms"][j][i]
            if not nom:
                continue
            if planche["blanche"]:
                # Tuile blanche sur fond noir (JPEG) : les coins arrondis,
                # noirs, restent dehors. Le fond est rendu transparent
                # comme du blanc pur — le grain du JPEG (254, 255) n'est
                # pas un dessin.
                tuile = im.crop((x0 + 8, y0 + 8, x1 - 7, y1 - 7))
                fond = fond_de(tuile)
                fond_alpha = (255, 255, 255)
            else:
                tuile = im.crop((x0, y0, x1 + 1, y1 + 1))
                fond = fond_alpha = fond_de(tuile)
            dessin = nettoyer(vers_alpha(tuile.crop(boite_du_dessin(tuile, fond)), fond_alpha))
            dessins.append((nom, dessin))
    return dessins


def main():
    sorties = [os.path.join(RACINE, app, "img", "pictos") for app in ("client", "admin")]
    for sortie in sorties:
        os.makedirs(sortie, exist_ok=True)
    planches = [dessins_de(p) for p in PLANCHES]
    reference = statistics.median(max(d.size) for _, d in planches[0])
    # LE CARRÉ DES DOUZE PREMIÈRES : la plus grande le remplit presque.
    cote = max(max(d.size) for _, d in planches[0]) + 8
    for numero, dessins in enumerate(planches):
        echelle = reference / statistics.median(max(d.size) for _, d in dessins)
        print("planche", numero + 1, "échelle", round(echelle, 3))
        for nom, dessin in dessins:
            # À l'échelle des douze premières, sans jamais déborder du carré.
            e = min(echelle, (cote - 8) / max(dessin.size))
            if abs(e - 1) > 1e-9:
                dessin = dessin.resize((round(dessin.size[0] * e), round(dessin.size[1] * e)), Image.LANCZOS)
            carre = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
            carre.alpha_composite(dessin, ((cote - dessin.size[0]) // 2, (cote - dessin.size[1]) // 2))
            carre = carre.resize((COTE_FINAL, COTE_FINAL), Image.LANCZOS)
            # 128 couleurs suffisent largement à deux teintes et leurs bords
            # adoucis : le fichier tombe à quelques kilo-octets.
            carre = carre.quantize(colors=128, method=Image.Quantize.FASTOCTREE)
            for sortie in sorties:
                carre.save(os.path.join(sortie, nom + ".png"), optimize=True)
            print(" ", nom, "dessin", dessin.size)
    print("carré commun", cote, "→", COTE_FINAL)


if __name__ == "__main__":
    main()
