# =========================================================
# Ouvre les deux applications BIZZOO sur cet ordinateur.
#
#   .\serve.ps1            (port 5180)
#   .\serve.ps1 -Port 8000
#
# Un simple serveur de fichiers : rien n'est compilé, rien
# n'est installé. Les deux applications sont du HTML, du CSS
# et du JavaScript — le navigateur les lit telles quelles,
# exactement comme le fera le serveur une fois en ligne.
#
# La base reste celle de Supabase, en ligne : ce qu'on
# enregistre ici est enregistré pour de bon.
#
# Ctrl+C pour arrêter.
# =========================================================
param([int]$Port = 5180)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
  $listener.Start()
} catch {
  Write-Host "Le port $Port est deja utilise." -ForegroundColor Red
  Write-Host "  Fermez l'autre fenetre, ou choisissez un autre port :"
  Write-Host "    .\serve.ps1 -Port 5181"
  exit 2
}

Write-Host ""
Write-Host "BIZZOO tourne sur cet ordinateur :" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Accueil          http://localhost:$Port/"
Write-Host "   La boutique      http://localhost:$Port/client/"
Write-Host "   Espace admin     http://localhost:$Port/admin/"
Write-Host ""
Write-Host "Astuce : reduisez la fenetre du navigateur sous 1024 px de large" -ForegroundColor DarkGray
Write-Host "         pour voir exactement ce que voit un telephone." -ForegroundColor DarkGray
Write-Host "Ctrl+C pour arreter." -ForegroundColor DarkGray
Write-Host ""

# Le jeu de caracteres est annonce pour les fichiers texte : sans lui,
# les accents des ecrans francais s'affichent de travers.
$mime = @{
  ".html"="text/html; charset=utf-8"; ".css"="text/css; charset=utf-8";
  ".js"="application/javascript; charset=utf-8"; ".json"="application/json; charset=utf-8";
  ".webmanifest"="application/manifest+json; charset=utf-8"; ".txt"="text/plain; charset=utf-8";
  ".svg"="image/svg+xml"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg";
  ".webp"="image/webp"; ".gif"="image/gif"; ".ico"="image/x-icon";
  ".mp4"="video/mp4"; ".webm"="video/webm";
  ".woff2"="font/woff2"; ".woff"="font/woff"
}

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  try {
    $localPath = $req.Url.LocalPath
    if ($localPath.EndsWith("/")) { $localPath = $localPath + "index.html" }
    $filePath = Join-Path $root ($localPath.TrimStart('/'))
    if ((Test-Path $filePath -PathType Container)) { $filePath = Join-Path $filePath "index.html" }
    if (Test-Path $filePath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
      $contentType = $mime[$ext]
      if (-not $contentType) { $contentType = "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $res.ContentType = $contentType
      # En local on ne garde rien en cache : un fichier modifie doit
      # s'afficher au rechargement, pas au prochain redemarrage.
      $res.Headers.Add("Cache-Control", "no-store")
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
      $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 - fichier introuvable")
      $res.ContentType = "text/plain; charset=utf-8"
      $res.OutputStream.Write($notFound, 0, $notFound.Length)
    }
  } catch {
    $res.StatusCode = 500
  } finally {
    $res.OutputStream.Close()
  }
}
