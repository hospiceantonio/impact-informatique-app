#!/usr/bin/env python3
"""Copie les applications web dans le projet iOS avant sa génération."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
for variant in ("client", "admin"):
    target = root / "ios/Generated" / variant
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(root / variant, target, ignore=shutil.ignore_patterns("*.ps1"))
subprocess.run(["xcodegen", "generate", "--spec", "ios/project.yml"], cwd=root, check=True)
