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

# UN ORPHELIN D'HIER PEUT ETRE EN LIGNE AUJOURD'HUI. Une photo ajoutee
# depuis l'export serait supprimee sans que rien ne le signale, et une
# suppression ne se rattrape pas. Relancer la requete prend trente
# secondes ; retrouver une photo perdue, non.
$date = (Get-Item $Csv).LastWriteTime
$age = (Get-Date) - $date
if (-not $Simulation -and $age.TotalHours -gt 24) {
  Rouge "Ce fichier date du $($date.ToString('dd/MM/yyyy a HH:mm')) - $([int]$age.TotalDays) jour(s)."
  Rouge "Trop vieux pour servir de liste de suppression : ce qui etait"
  Rouge "orphelin ce jour-la peut etre affiche dans la boutique aujourd'hui."
  Write-Host ""
  Gris "Relancez supabase/etat-du-stockage.sql, exportez un CSV frais,"
  Gris "et rappelez ce script avec lui."
  exit 2
}
Gris "Liste etablie le $($date.ToString('dd/MM/yyyy a HH:mm'))."

$lignes = Import-Csv -Path $Csv -Encoding UTF8
$tous = @($lignes | Where-Object { $_.section -eq "ORPHELINS" } | ForEach-Object { $_.quoi })

# La requete ecrit « seau/chemin ». Le seau ne se devine pas : deux seaux
# peuvent porter le meme chemin, et supprimer dans le mauvais effacerait
# un fichier bien vivant en laissant l'orphelin en place.
#
# Un chemin ecrit par l'application ne contient que des lettres, des
# chiffres, un point, un tiret, un souligne et des barres. Tout le reste
# est ECARTE plutot qu'echappe : mal echapper un guillemet ou un
# antislash, c'est envoyer un chemin different de celui qu'on a lu - et
# supprimer autre chose que ce qu'on croyait.
$orphelins = @()
$ecartes = @()
foreach ($t in $tous) {
  $m = [regex]::Match($t, '^([A-Za-z0-9_-]+)/(.+)$')
  if ($m.Success -and $m.Groups[2].Value -match '^[A-Za-z0-9_./-]+$') {
    $orphelins += [pscustomobject]@{
      Seau = $m.Groups[1].Value; Chemin = $m.Groups[2].Value; Complet = $t
    }
  } else {
    $ecartes += $t
  }
}

if ($ecartes.Count -gt 0) {
  Rouge "$($ecartes.Count) ligne(s) au format inattendu, ECARTEES par prudence :"
  foreach ($x in $ecartes) { Write-Host "   $x" }
  Gris "  (Attendu : « seau/chemin ». Un CSV d'avant cette version n'a pas"
  Gris "   le seau : relancez etat-du-stockage.sql pour en obtenir un bon.)"
  Write-Host ""
}

if ($orphelins.Count -eq 0) {
  Vert "Aucun orphelin exploitable dans ce fichier."
  Gris "  (Verifiez que le CSV vient bien de etat-du-stockage.sql.)"
  exit 0
}

Write-Host ""
Write-Host "$($orphelins.Count) fichier(s) que plus aucune ligne de la base ne designe :" -ForegroundColor Cyan
Write-Host ""
foreach ($groupe in ($orphelins | Group-Object Seau)) {
  Write-Host "  seau « $($groupe.Name) » - $($groupe.Count) fichier(s)" -ForegroundColor Cyan
  foreach ($o in $groupe.Group) { Write-Host "     $($o.Chemin)" }
}
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

# Seau par seau : l'adresse de suppression porte le nom du seau, et un
# chemin n'a de sens que dans le sien.
foreach ($groupe in ($orphelins | Group-Object Seau)) {
  $seau = $groupe.Name
  $chemins = @($groupe.Group | ForEach-Object { $_.Chemin })

  # Par paquets de 50 : une seule requete de 200 chemins serait refusee.
  for ($i = 0; $i -lt $chemins.Count; $i += 50) {
    $paquet = @($chemins[$i..([Math]::Min($i + 49, $chemins.Count - 1))])
    # Le corps est ecrit a la main : « ConvertTo-Json » deballe un tableau
    # d'un seul element et enverrait une chaine la ou Supabase attend une
    # liste. Le dernier paquet peut n'en contenir qu'un.
    $corps = '{"prefixes":[' +
      (($paquet | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']}'
    try {
      $r = Invoke-RestMethod -Method Delete -Uri "$url/storage/v1/object/$seau" `
        -Headers $entetes -ContentType "application/json" -Body $corps
      # Supabase renvoie la liste de ce qu'il a REELLEMENT supprime : un
      # fichier que les regles refusent est absent, sans message d'erreur.
      $noms = @($r | ForEach-Object { $_.name })
      $partis += $noms.Count
      $refuses += @($paquet | Where-Object { $noms -notcontains $_ } |
                    ForEach-Object { "$seau/$_" })
    } catch {
      Rouge "Un paquet du seau « $seau » a echoue : $($_.Exception.Message)"
      $refuses += @($paquet | ForEach-Object { "$seau/$_" })
    }
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
