@echo off
rem =========================================================
rem  BIZZOO - a double-cliquer.
rem
rem  Ouvre les deux applications sur cet ordinateur, et lance
rem  le navigateur dessus. Rien n'est installe : ce sont des
rem  fichiers HTML que le navigateur lit tels quels.
rem
rem  Le "-ExecutionPolicy Bypass" ci-dessous est la pour une
rem  seule raison : Windows refuse par defaut d'executer un
rem  script PowerShell. On lui dit de faire une exception pour
rem  CE lancement-la, sans rien changer aux reglages de la
rem  machine.
rem
rem  Fermez cette fenetre noire pour arreter le serveur.
rem =========================================================
title BIZZOO - serveur local
cd /d "%~dp0"

if not exist "%~dp0serve.ps1" (
  echo.
  echo   Fichier serve.ps1 introuvable.
  echo   Ce raccourci doit rester dans le dossier du projet,
  echo   a cote des dossiers "client" et "admin".
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" %*

rem Si PowerShell s'arrete tout seul, la fenetre reste ouverte
rem le temps de lire le message.
echo.
echo   Le serveur est arrete.
pause
