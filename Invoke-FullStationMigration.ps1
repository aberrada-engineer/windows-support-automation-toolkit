#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-FullStationMigration v3.0 - Assistant Complet de Migration de Poste (A à Z).
    Conçu pour les Techniciens Informatiques et Administrateurs Systèmes en ESN ou Entreprise.

.DESCRIPTION
    Guide pas-à-pas pour transférer 100% de l'environnement d'un utilisateur :
    - Données : Bureau, Documents, Téléchargements, Images, Vidéos, Musique
    - Messagerie : PST Outlook, Signatures, Registre Office
    - Navigateurs : Favoris Chrome, Edge, Firefox
    - Réseau : Lecteurs réseau remappés, Imprimantes documentées et réinstallées, Profils Wi-Fi
    - Système : Clés SSH (.ssh), .gitconfig, Inventaire complet des logiciels installés (HTML/CSV)
    - Rapport HTML et Score de conformité 0-100%
#>

[CmdletBinding()]
param(
    [string]$DefaultBackupPath = ""
)

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent
Import-Module "$ScriptDir\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($DefaultBackupPath)) {
    $DefaultBackupPath = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Migrations" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Migrations" }
}
Import-Module "$ScriptDir\Modules\Migration\ESN-Migration.psm1" -Force

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   🚚  ASSISTANT DE MIGRATION DE POSTE DE A A Z — ESN-TOOLKIT v3.0" -ForegroundColor White
    Write-Host "       Sauvegarde & Restauration Intégrale de Profils — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  Hôte : $env:COMPUTERNAME  |  Session : $env:USERNAME  |  Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkCyan
    Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkGray
}

Show-Header
Write-Host " Que souhaitez-vous faire ?`n" -ForegroundColor White
Write-Host "  [1] 📤 ETAPE 1 : Sauvegarder l'Ancien Poste (Capture complète A à Z)" -ForegroundColor Green
Write-Host "  [2] 📥 ETAPE 2 : Restaurer sur le Nouveau Poste (Restauration 1-Clic)" -ForegroundColor Yellow
Write-Host "  [3] 🔍 Mode Audit / Simulation (Calculer volume sans copier)" -ForegroundColor Cyan
Write-Host "  [Q] ❌ Quitter`n" -ForegroundColor DarkGray

$choice = Read-Host " Votre choix (1, 2, 3 ou Q)"

if ($choice.ToUpper() -eq "Q") { exit }

# ─────────────────────────────────────────────────────────────
# OPTION 1 & 3 : CAPTURE (SAUVEGARDE)
# ─────────────────────────────────────────────────────────────
if ($choice -in @("1", "3")) {
    $isSimulation = ($choice -eq "3")
    Show-Header
    Write-Host "--- ETAPE 1 : SELECTION DU PROFIL A SAUVEGARDER ---`n" -ForegroundColor Yellow

    # Liste des profils locaux sur la machine
    $profiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }
    Write-Host " Profils utilisateurs détectés sur ce poste :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  [$($i+1)] $($profiles[$i].Name)" -ForegroundColor White
    }
    Write-Host "  [M] Saisie manuelle d'un autre nom d'utilisateur`n" -ForegroundColor DarkGray

    $userChoice = Read-Host " Sélectionnez le profil à capturer (1-$($profiles.Count) ou M)"
    $selectedUser = $env:USERNAME
    if ($userChoice -match "^\d+$" -and [int]$userChoice -le $profiles.Count) {
        $selectedUser = $profiles[[int]$userChoice - 1].Name
    } elseif ($userChoice.ToUpper() -eq "M") {
        $selectedUser = Read-Host " Entrez le nom exact du compte utilisateur"
    }

    Write-Host "`n Utilisateur sélectionné : $selectedUser" -ForegroundColor Green

    # Destination de la sauvegarde
    Write-Host "`n Emplacement de sauvegarde :" -ForegroundColor Cyan
    Write-Host "  Par défaut : $DefaultBackupPath" -ForegroundColor DarkGray
    Write-Host "  (Vous pouvez spécifier une clé USB ex: E:\Migrations ou un partage réseau ex: \\NAS\Partage)`n" -ForegroundColor DarkGray
    $customBackup = Read-Host " Dossier cible (Appuyez sur Entrée pour le dossier par défaut)"
    if ([string]::IsNullOrWhiteSpace($customBackup)) {
        $customBackup = $DefaultBackupPath
    }

    if (-not (Test-Path $customBackup)) {
        New-Item -ItemType Directory -Path $customBackup -Force | Out-Null
    }

    Write-Host "`n Options incluses dans la capture A à Z :" -ForegroundColor Cyan
    Write-Host "  [✓] Données personnelles (Bureau, Documents, Téléchargements, Images, Vidéos)" -ForegroundColor Green
    Write-Host "  [✓] Outlook (Fichiers PST, Signatures, Registre profils Office)" -ForegroundColor Green
    Write-Host "  [✓] Navigateurs (Favoris Chrome, Edge, Firefox)" -ForegroundColor Green
    Write-Host "  [✓] Réseau (Lecteurs réseau remappés, Imprimantes documentées)" -ForegroundColor Green
    Write-Host "  [✓] Profils Wi-Fi de la machine (avec clés)" -ForegroundColor Green
    Write-Host "  [✓] Inventaire complet des logiciels installés (CSV + HTML)" -ForegroundColor Green
    Write-Host "  [✓] Clés SSH (.ssh) et configuration Git" -ForegroundColor Green

    Write-Host "`n Démarrage de la capture..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1

    $params = @{
        SourceComputer   = $env:COMPUTERNAME
        Username         = $selectedUser
        BackupRoot       = $customBackup
        All              = $true
        Simulation       = $isSimulation
    }

    $backupResult = Invoke-UserStateCapture @params

    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "   CAPTURE TERMINEE AVEC SUCCES !" -ForegroundColor White
    Write-Host "   Dossier de sauvegarde : $backupResult" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Green
    Read-Host "`nAppuyez sur Entrée pour quitter..."
}

# ─────────────────────────────────────────────────────────────
# OPTION 2 : RESTAURATION SUR LE NOUVEAU POSTE
# ─────────────────────────────────────────────────────────────
elseif ($choice -eq "2") {
    Show-Header
    Write-Host "--- ETAPE 2 : RESTAURATION SUR LE NOUVEAU POSTE ---`n" -ForegroundColor Yellow

    Write-Host " Emplacement des sauvegardes à analyser :" -ForegroundColor Cyan
    Write-Host "  Par défaut : $DefaultBackupPath" -ForegroundColor DarkGray
    $searchDir = Read-Host " Dossier source de sauvegarde (Entrée pour défaut)"
    if ([string]::IsNullOrWhiteSpace($searchDir)) {
        $searchDir = $DefaultBackupPath
    }

    if (-not (Test-Path $searchDir)) {
        Write-Host " [!] Dossier introuvable : $searchDir" -ForegroundColor Red
        Read-Host "Appuyez sur Entrée pour quitter..."
        exit
    }

    # Recherche des sauvegardes contenant un manifest.json
    $backups = Get-ChildItem -Path $searchDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "manifest.json") }

    if (-not $backups) {
        Write-Host " [!] Aucune sauvegarde valide trouvée dans $searchDir" -ForegroundColor Red
        Read-Host "Appuyez sur Entrée pour quitter..."
        exit
    }

    Write-Host "`n Sauvegardes disponibles :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host "  [$($i+1)] $($backups[$i].Name)" -ForegroundColor White
    }

    $bkChoice = Read-Host "`n Sélectionnez la sauvegarde à restaurer (1-$($backups.Count))"
    if ($bkChoice -match "^\d+$" -and [int]$bkChoice -le $backups.Count) {
        $chosenBackup = $backups[[int]$bkChoice - 1].FullName
    } else {
        Write-Host " [!] Choix invalide." -ForegroundColor Red
        exit
    }

    Write-Host "`n Utilisateur cible sur cette machine :" -ForegroundColor Cyan
    Write-Host "  Par défaut : $env:USERNAME" -ForegroundColor DarkGray
    $targetUser = Read-Host " Nom d'utilisateur cible (Entrée pour '$env:USERNAME')"
    if ([string]::IsNullOrWhiteSpace($targetUser)) {
        $targetUser = $env:USERNAME
    }

    Write-Host "`n Démarrage de la restauration..." -ForegroundColor Yellow
    $res = Invoke-UserStateRestore -BackupDir $chosenBackup -TargetComputer $env:COMPUTERNAME -Username $targetUser

    # Restauration automatique Wi-Fi si présent
    $wifiBat = Join-Path $chosenBackup "WiFi\Restore-WiFi.bat"
    if (Test-Path $wifiBat) {
        Write-Host "`n [*] Restauration des profils Wi-Fi..." -ForegroundColor Cyan
        Start-Process "cmd.exe" -ArgumentList "/c `"$wifiBat`"" -Wait -WindowStyle Hidden
        Write-Host " [OK] Profils Wi-Fi importés." -ForegroundColor Green
    }

    if ($res -and $res.ReportPath -and (Test-Path $res.ReportPath)) {
        Start-Process $res.ReportPath
    }

    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "   RESTAURATION TERMINEE ! SCORE : $($res.Score)/100" -ForegroundColor White
    Write-Host "   Rapport ouvert dans le navigateur." -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Green
    Read-Host "`nAppuyez sur Entrée pour quitter..."
}
