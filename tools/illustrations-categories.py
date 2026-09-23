#!/usr/bin/env python3
# =========================================================
# Les illustrations des catégories de BIZZOO
#
# Sur la DA, chaque rond de catégorie montre UN OBJET sur un fond
# pastel. Ce script les compose, et les range dans les deux
# applications : « client/img/categories/ » et
# « admin/img/categories/ ». Elles voyagent avec l'application —
# dans l'APK comme sur le site — et s'affichent donc hors
# connexion, sans rien demander au réseau.
#
# LES OBJETS sont les « Fluent Emoji » 3D de Microsoft, sous licence
# MIT (voir LICENCE.txt à côté des images) :
#
#   npm pack @lobehub/fluent-emoji-3d@1.1.0
#   tar xzf lobehub-fluent-emoji-3d-1.1.0.tgz
#   python3 tools/illustrations-categories.py package/assets
#
# LE FOND est la teinte claire de la catégorie — la même que celle
# du rond sur l'accueil (« teinteClaire(couleur, .16) ») : la photo
# se fond dans le rond, sans bord visible.
#
# Il faut Pillow (python3 -m pip install Pillow).
# =========================================================
import os
import sys

from PIL import Image, ImageFilter

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (fichier, code de l'emoji, couleur de la catégorie qu'il sert)
ILLUSTRATIONS = [
    # Une par catégorie de BIZZOO, dans l'ordre de la liste.
    ("robe", "1f457", "#6C3FBF"),            # Mode & Vêtements
    ("ordinateur", "1f4bb", "#0B5CF5"),      # High-Tech & Électronique
    ("voiture", "1f697", "#001450"),         # Auto & Moto
    ("maison", "1f3e1", "#0F9D58"),          # Maison & Jardin
    ("rouge-a-levres", "1f484", "#D81B60"),  # Beauté & Bien-être
    ("marmite", "1f372", "#F96302"),         # Restauration & Alimentation
    ("chariot", "1f6d2", "#E62329"),         # Supermarché & Épicerie
    ("ecran", "1f5a5-fe0f", "#0B7C8C"),      # Logiciels & Solutions pro
    ("nounours", "1f9f8", "#3F51B5"),        # Bébé & Enfant
    ("ballon", "26bd", "#9A6B00"),           # Sport & Loisirs
    ("briques", "1f9f1", "#546E7A"),         # Bricolage & Matériaux
    ("livres", "1f4da", "#7A4A32"),          # Livres, Éducation & Fournitures
    ("bague", "1f48d", "#6C3FBF"),           # Bijoux & Accessoires
    ("chien", "1f436", "#0F9D58"),           # Animaux
    ("boite-a-outils", "1f9f0", "#0B7C8C"),  # Services
    # D'autres, au choix de l'enseigne depuis l'admin.
    ("t-shirt", "1f455", "#6C3FBF"),
    ("telephone", "1f4f1", "#0B5CF5"),
    ("moto", "1f3cd-fe0f", "#001450"),
    ("plante", "1fab4", "#0F9D58"),
    ("burger", "1f354", "#F96302"),
    ("panier", "1f9fa", "#E62329"),
    ("outils", "1f6e0-fe0f", "#546E7A"),
    ("mallette", "1f4bc", "#0B7C8C"),
    ("poignee-de-main", "1f91d", "#0B7C8C"),
]

# 360 px : l'objet y garde à peu près sa taille d'origine (256 px),
# et le plus grand rond — 62 px, 186 points sur l'écran le plus
# fin — n'en demande pas davantage.
COTE = 360


def teinte(hexa, part=0.16):
    n = int(hexa[1:], 16)
    r, g, b = n >> 16, (n >> 8) & 255, n & 255
    mele = lambda c: round(c * part + 255 * (1 - part))
    return (mele(r), mele(g), mele(b))


def composer(source, couleur):
    objet = Image.open(source).convert("RGBA")
    objet = objet.crop(objet.getbbox())
    w, h = objet.size
    # L'OBJET TIENT DANS LE CERCLE : c'est la demi-diagonale de son
    # cadre qui se règle, pas sa largeur — sinon les coins d'un objet
    # carré seraient coupés par le rond.
    echelle = (0.86 * COTE / 2) / (((w * w + h * h) ** 0.5) / 2)
    objet = objet.resize((max(1, round(w * echelle)), max(1, round(h * echelle))), Image.LANCZOS)
    fond = Image.new("RGBA", (COTE, COTE), teinte(couleur) + (255,))
    x = (COTE - objet.width) // 2
    y = (COTE - objet.height) // 2 + round(COTE * 0.01)
    # Une ombre douce dessous, comme un objet posé.
    ombre = Image.new("RGBA", (COTE, COTE), (0, 0, 0, 0))
    silhouette = Image.new("RGBA", objet.size, (20, 30, 60, 255))
    silhouette.putalpha(objet.split()[3].point(lambda a: a * 0.22))
    ombre.paste(silhouette, (x, y + round(COTE * 0.03)), silhouette)
    fond = Image.alpha_composite(fond, ombre.filter(ImageFilter.GaussianBlur(COTE * 0.03)))
    fond.alpha_composite(objet, (x, y))
    return fond.convert("RGB")


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage : python3 tools/illustrations-categories.py <dossier des emoji 3D>")
    assets = sys.argv[1]
    for app in ("client", "admin"):
        os.makedirs(os.path.join(RACINE, app, "img", "categories"), exist_ok=True)
    for nom, code, couleur in ILLUSTRATIONS:
        image = composer(os.path.join(assets, code + ".webp"), couleur)
        for app in ("client", "admin"):
            chemin = os.path.join(RACINE, app, "img", "categories", nom + ".jpg")
            image.save(chemin, "JPEG", quality=86, optimize=True, progressive=True)
        print(nom)


if __name__ == "__main__":
    main()
