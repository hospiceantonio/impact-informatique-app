#!/usr/bin/env python3
"""Construit les deux bundles avec une signature privée extérieure au dépôt."""
import json
import os
from pathlib import Path
import subprocess

racine = Path(__file__).resolve().parents[1]
configuration = Path.home() / ".config/bizzoo/android/play-signing.json"
environnement = dict(os.environ)
if configuration.is_file():
    environnement.update(json.loads(configuration.read_text()))
variables = (
    "BIZZOO_PLAY_STORE_FILE", "BIZZOO_PLAY_STORE_PASSWORD",
    "BIZZOO_PLAY_KEY_ALIAS", "BIZZOO_PLAY_KEY_PASSWORD",
)
if not all(environnement.get(nom) for nom in variables):
    raise SystemExit("Signature absente : fournir les quatre variables BIZZOO_PLAY_*.")

subprocess.run(["node", "android/preparer-assets.js"], cwd=racine, check=True)
subprocess.run(
    ["./gradlew", "--no-daemon", "bundleClientPlay", "bundleAdminPlay",
     "lintClientPlay", "lintAdminPlay"],
    cwd=racine / "android", env=environnement, check=True,
)
print("Bundles : android/app/build/outputs/bundle/{clientPlay,adminPlay}/")
