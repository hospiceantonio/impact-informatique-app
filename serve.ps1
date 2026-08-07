$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 5180
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Output "Impact Informatique disponible sur :"
Write-Output "  Application client : http://localhost:$port/client/"
Write-Output "  Application admin  : http://localhost:$port/admin/"

$mime = @{
  ".html"="text/html"; ".css"="text/css"; ".js"="application/javascript";
  ".svg"="image/svg+xml"; ".png"="image/png"; ".jpg"="image/jpeg"; ".ico"="image/x-icon";
  ".webmanifest"="application/manifest+json"; ".json"="application/json"
}

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $req = $context.Request
  $res = $context.Response
  try {
    $localPath = $req.Url.LocalPath
    if ($localPath -eq "/") { $localPath = "/client/index.html" }
    if ($localPath.EndsWith("/")) { $localPath = $localPath + "index.html" }
    $filePath = Join-Path $root ($localPath.TrimStart('/'))
    if ((Test-Path $filePath -PathType Container)) { $filePath = Join-Path $filePath "index.html" }
    if (Test-Path $filePath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($filePath)
      $contentType = $mime[$ext]
      if (-not $contentType) { $contentType = "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $res.ContentType = $contentType
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $res.StatusCode = 404
      $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
      $res.OutputStream.Write($notFound, 0, $notFound.Length)
    }
  } catch {
    $res.StatusCode = 500
  } finally {
    $res.OutputStream.Close()
  }
}
