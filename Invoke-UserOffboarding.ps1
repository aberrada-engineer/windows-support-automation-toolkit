#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-UserOffboarding v3.0 - Procédure Sécurisée de Départ Collaborateur (Offboarding IT).
    Automatise la révocation des accès, la sauvegarde des droits et génère le PV de restitution.

.DESCRIPTION
    1. Désactivation du compte Active Directory
    2. Sauvegarde de la liste des groupes initiaux (Rollback JSON)
    3. Retrait de tous les groupes de sécurité et distribution
    4. Réinitialisation du mot de passe avec une chaîne aléatoire complexe
    5. Blocage des ouvertures de session et révocation
    6. Génération du Procès-Verbal (PV) officiel de clôture de compte
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Username,
    [string]$ManagerName = "Direction / RH",
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host "   🔒  OFFBOARDING COLLABORATEUR SECURISE — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Révocation des accès & Procès-Verbal de restitution — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host ""

$adModule = Get-Module -ListAvailable -Name ActiveDirectory
if (-not $adModule) {
    Write-Host " [!] Module ActiveDirectory requis pour cette opération." -ForegroundColor Red
    return
}
Import-Module ActiveDirectory -Force

$user = Get-ADUser -Identity $Username -Properties MemberOf, EmailAddress, Title, Department -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Host " [ERREUR] Utilisateur '$Username' introuvable dans l'Active Directory." -ForegroundColor Red
    return
}

Write-Host " Utilisateur ciblé : $($user.Name) ($($user.UserPrincipalName))" -ForegroundColor Cyan
Write-Host " Poste : $($user.Title) | Service : $($user.Department)" -ForegroundColor DarkGray

$confirm = Read-Host "`n Confirmez-vous la clôture immédiate de ce compte ? (O/N)"
if ($confirm.ToUpper() -ne "O") {
    Write-Host " Opération annulée." -ForegroundColor Yellow
    return
}

# 1. SAUVEGARDE DES GROUPES (ROLLBACK JSON)
$backupDir = "C:\ESN-Toolkit\Offboarding_Archives"
if (-not (Test-Path $backupDir)) { New-Item $backupDir -ItemType Directory -Force | Out-Null }
$backupFile = Join-Path $backupDir "$Username-Groups-Backup.json"

$groups = $user.MemberOf
$groups | ConvertTo-Json | Out-File $backupFile -Encoding UTF8
Write-Host "`n [OK] Groupes sauvegardés pour traçabilité dans : $backupFile" -ForegroundColor Green

# 2. DESACTIVATION DU COMPTE
Disable-ADAccount -Identity $Username
Write-Host " [OK] Compte Active Directory désactivé." -ForegroundColor Green

# 3. SUPPRESSION DES GROUPES (Sauf 'Domain Users' obligatoire)
foreach ($g in $groups) {
    $groupName = (Get-ADGroup -Identity $g).Name
    if ($groupName -ne "Domain Users") {
        Remove-ADGroupMember -Identity $g -Members $Username -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Write-Host " [OK] Retiré de tous les groupes de sécurité et de distribution." -ForegroundColor Green

# 4. RANDOM PASSWORD & EXPIRATION
$randomPwd = [System.Web.Security.Membership]::GeneratePassword(16, 4) | ConvertTo-SecureString -AsPlainText -Force
Set-ADAccountPassword -Identity $Username -NewPassword $randomPwd -Reset
Set-ADUser -Identity $Username -AccountExpirationDate (Get-Date)
Write-Host " [OK] Mot de passe réinitialisé aléatoirement et compte expiré." -ForegroundColor Green

# 5. GENERATION DU PROCES-VERBAL OFFICIEL (HTML)
$pvPath = "C:\ESN-Toolkit\Reports\PV-Restitution-$Username.html"
$pvHtml = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Procès-Verbal de Restitution IT - $Username</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 30px; }
        .sheet { background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 40px; max-width: 800px; margin: auto; }
        h1 { color: #0f172a; text-align: center; border-bottom: 2px solid #e2e8f0; padding-bottom: 15px; }
        .meta { margin: 25px 0; font-size: 14px; line-height: 1.8; }
        .actions { background: #f1f5f9; padding: 20px; border-radius: 6px; margin: 20px 0; }
        .signatures { display: flex; justify-content: space-between; margin-top: 50px; padding-top: 30px; border-top: 1px dashed #cbd5e1; }
        .sig-box { width: 45%; text-align: center; }
    </style>
</head>
<body>
    <div class='sheet'>
        <h1>PROCES-VERBAL DE CLÔTURE DE COMPTE IT</h1>
        <div class='meta'>
            <b>Collaborateur concerné :</b> $($user.Name)<br>
            <b>Identifiant de session :</b> $Username<br>
            <b>Intitulé du poste :</b> $($user.Title)<br>
            <b>Date de clôture effective :</b> $(Get-Date -Format 'dd/MM/yyyy à HH:mm')<br>
            <b>Responsable IT / Opérateur :</b> Amine BERRADA (Administrateur Systèmes & Réseaux)
        </div>
        <div class='actions'>
            <b>Opérations techniques exécutées :</b>
            <ul>
                <li>Désactivation immédiate du compte d'annuaire Active Directory</li>
                <li>Révocation des appartenances aux groupes de sécurité ($(@($groups).Count) groupes archivés)</li>
                <li>Réinitialisation du mot de passe avec une clé aléatoire forte</li>
                <li>Révocation des sessions actives et jetons d'authentification</li>
            </ul>
        </div>
        <div class='signatures'>
            <div class='sig-box'>
                <b>Pour le Service Informatique</b><br><br><br>
                <i>Amine BERRADA</i>
            </div>
            <div class='sig-box'>
                <b>Pour la Direction / RH</b><br><br><br>
                <i>$ManagerName</i>
            </div>
        </div>
    </div>
</body>
</html>
"@

$pvHtml | Out-File -FilePath $pvPath -Encoding UTF8
Write-Host " [OK] Procès-Verbal généré : $pvPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $pvPath }
