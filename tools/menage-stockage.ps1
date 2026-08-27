# =========================================================
#  BIZZOO - supprimer les fichiers orphelins du stockage
#
#  Un orphelin est un fichier que plus aucune ligne de la base
#  ne designe : une photo retiree d'un produit reste dans le
#  seau, la base ne la suit plus, le stockage la garde.
#
#  MARCHE A SUIVRE
#    1. Executer supabase/etat-du-stockage.sql dans l'editeur SQL
#       de Supabase.
#    2. Exporter le resultat en CSV (bouton "Download CSV").
#    3. Lancer ce script en lui donnant ce fichier :
#
#         .\tools\menage-stockage.ps1 -Csv "C:\...\resultat.csv"
#
#  Il ne supprime QUE les lignes marquees ORPHELINS par la
#  requete, et vous montre la liste avant de toucher a quoi que
#  ce soit. Rien ne part sans que vous ayez tape SUPPRIMER.
#
#  AUCUNE CLE SECRETE ici. Le script se connecte avec VOTRE
#  compte administrateur, et les regles de la base decident de
#  ce qu'il a le droit d'effacer - exactement comme quand vous
#  supprimez une photo depuis l'application. La cle
#  "service_role", qui contourne toutes les regles, n'a rien a
#  faire sur un poste de travail.
#
#  -Simulation pour voir ce qui partirait, sans rien supprimer.
# =========================================================
param(
  [Parameter(Mandatory = $true)][string]$Csv,
  [switch]$Simulation
)

$ErrorActionPreference = "Stop"
# Windows PowerShell parle encore TLS 1.0 par defaut ; Supabase refuse.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$racine = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$seau = "produits"

function Rouge($t) { Write-Host $t -ForegroundColor Red }
function Vert($t)  { Write-Host $t -ForegroundColor Green }
function Gris($t)  { Write-Host $t -ForegroundColor DarkGray }

# ---------- L'adresse du projet, lue dans l'application ----------
$config = Join-Path $racine "client\config.js"
if (-not (Test-Path $config)) { Rouge "client/config.js introuvable."; exit 2 }
$texte = Get-Content $config -Raw
$url = ([regex]::Match($texte, 'SUPABASE_URL:\s*"([^"]+)"')).Groups[1].Value
$cle = ([regex]::Match($texte, 'SUPABASE_ANON_KEY:\s*"([^"]+)"')).Groups[1].Value
if (-not $url -or -not $cle) { Rouge "Adresse Supabase illisible dans client/config.js."; exit 2 }

# ---------- La liste, telle que la requete l'a etablie ----------
if (-not (Test-Path $Csv)) { Rouge "Fichier introuvable : $Csv"; exit 2 }
$lignes = Import-Csv -Path $Csv -Encoding UTF8
$orphelins = @($lignes | Where-Object { $_.section -eq "ORPHELINS" } | ForEach-Object { $_.quoi })

if ($orphelins.Count -eq 0) {
  Vert "Aucun orphelin dans ce fichier : le stockage est deja propre."
  Gris "  (Verifiez que le CSV vient bien de etat-du-stockage.sql.)"
  exit 0
}

Write-Host ""
Write-Host "$($orphelins.Count) fichier(s) que plus aucune ligne de la base ne designe :" -ForegroundColor Cyan
Write-Host ""
foreach ($o in $orphelins) { Write-Host "   $o" }
Write-Host ""

if ($Simulation) {
  Gris "Simulation : rien n'a ete supprime."
  exit 0
}

# ---------- Confirmation ----------
Write-Host "Cette suppression est DEFINITIVE." -ForegroundColor Yellow
$reponse = Read-Host "Tapez SUPPRIMER pour continuer (autre chose annule)"
if ($reponse -cne "SUPPRIMER") { Gris "Annule. Rien n'a ete touche."; exit 0 }

# ---------- Connexion avec VOTRE compte ----------
Write-Host ""
$email = Read-Host "Votre email d'administrateur BIZZOO"
$secret = Read-Host "Votre mot de passe" -AsSecureString
$motDePasse = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret))

try {
  $session = Invoke-RestMethod -Method Post `
    -Uri "$url/auth/v1/token?grant_type=password" `
    -Headers @{ apikey = $cle } -ContentType "application/json" `
    -Body (@{ email = $email; password = $motDePasse } | ConvertTo-Json)
} catch {
  Rouge "Connexion refusee : verifiez l'email et le mot de passe."
  exit 1
} finally {
  # Le mot de passe ne traine pas en memoire plus longtemps que necessaire.
  $motDePasse = $null
}

# ---------- Suppression ----------
# Le meme appel que celui de l'application admin : ce sont les regles de
# la base qui autorisent, ou non, chaque effacement.
$entetes = @{ apikey = $cle; Authorization = "Bearer $($session.access_token)" }
$partis = 0
$refuses = @()

# Par paquets de 50 : une seule requete de 200 chemins serait refusee.
for ($i = 0; $i -lt $orphelins.Count; $i += 50) {
  $paquet = @($orphelins[$i..([Math]::Min($i + 49, $orphelins.Count - 1))])
  try {
    $r = Invoke-RestMethod -Method Delete -Uri "$url/storage/v1/object/$seau" `
      -Headers $entetes -ContentType "application/json" `
      -Body (@{ prefixes = $paquet } | ConvertTo-Json)
    # Supabase renvoie la liste de ce qu'il a REELLEMENT supprime : un
    # fichier que les regles refusent est absent, sans message d'erreur.
    $noms = @($r | ForEach-Object { $_.name })
    $partis += $noms.Count
    $refuses += @($paquet | Where-Object { $noms -notcontains $_ })
  } catch {
    Rouge "Le paquet a partir de $($i + 1) a echoue : $($_.Exception.Message)"
    $refuses += $paquet
  }
}

Write-Host ""
Vert "$partis fichier(s) supprime(s)."
if ($refuses.Count -gt 0) {
  Write-Host ""
  Rouge "$($refuses.Count) refuse(s) par la base - votre compte n'a pas ce droit :"
  foreach ($f in $refuses) { Write-Host "   $f" }
  Gris "  Le dossier « enseigne/ » demande le superadministrateur."
}
Write-Host ""
Gris "Relancez etat-du-stockage.sql pour verifier le nouveau total."
