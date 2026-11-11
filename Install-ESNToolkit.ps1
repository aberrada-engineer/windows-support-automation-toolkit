#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script d'installation et de déploiement d'ESN-Toolkit.
    Crée l'arborescence standard C:\ESN-Toolkit, configure la politique d'exécution,
    et génère les raccourcis Bureau pour l'Interface Graphique et la Console.
#>

[CmdletBinding()]
param(
    [string]$TargetDir = "C:\ESN-Toolkit",
    [switch]$CreateDesktopShortcut = $true,
    [switch]$RegisterDailyAuditTask = $false
)

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "        DEPLOIEMENT D'ESN-TOOLKIT - AMINE BERRADA" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$SourceDir = $PSScriptRoot

# 1. Vérification / Création des répertoires cibles
Write-Host "[1/5] Verification des repertoires cibles..." -ForegroundColor Yellow
$Directories = @(
    $TargetDir,
    "$TargetDir\Logs",
    "$TargetDir\Reports",
    "$TargetDir\ZipIncidents",
    "$TargetDir\Modules",
    "$TargetDir\Core",
    "$TargetDir\Clients"
)

foreach ($dir in $Directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  [+] Repertoire cree : $dir" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Repertoire existant : $dir" -ForegroundColor DarkGray
    }
}

# 2. Copie / Synchronisation des fichiers
Write-Host ""
Write-Host "[2/5] Deploiement des fichiers du toolkit..." -ForegroundColor Yellow
try {
    # Copie récursive en excluant les dossiers temporaires et logs
    $Exclude = @('.git', 'Logs', 'Reports', 'ZipIncidents', '.vscode')
    Get-ChildItem -Path $SourceDir | Where-Object { $_.Name -notin $Exclude } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $TargetDir -Recurse -Force
    }
    Write-Host "  [OK] Tous les modules, scripts et ressources ont ete synchronises." -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] Impossible de copier certains fichiers : $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Configuration de la politique d'exécution PowerShell
Write-Host ""
Write-Host "[3/5] Configuration des autorisations PowerShell..." -ForegroundColor Yellow
try {
    $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
    if ($currentPolicy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Write-Host "  [+] ExecutionPolicy LocalMachine definie sur RemoteSigned" -ForegroundColor Green
    } else {
        Write-Host "  [OK] ExecutionPolicy valide : $currentPolicy" -ForegroundColor Green
    }
} catch {
    Write-Host "  [AVERTISSEMENT] Impossible d'ajuster l'ExecutionPolicy systeme : $($_.Exception.Message)" -ForegroundColor Yellow
}

# 4. Création des raccourcis Bureau
if ($CreateDesktopShortcut) {
    Write-Host ""
    Write-Host "[4/5] Creation des raccourcis Bureau..." -ForegroundColor Yellow
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)

        # Raccourci GUI
        $GuiShortcutPath = Join-Path $DesktopPath "ESN-Toolkit (Interface Graphique).lnk"
        $GuiShortcut = $WshShell.CreateShortcut($GuiShortcutPath)
        $GuiShortcut.TargetPath = "$TargetDir\ESN-Launcher.bat"
        $GuiShortcut.WorkingDirectory = $TargetDir
        $GuiShortcut.Description = "ESN-Toolkit - Tableau de bord et depannage 1-clic"
        $GuiShortcut.IconLocation = "shell32.dll,22" # Icône écran bleu / système
        $GuiShortcut.Save()
        Write-Host "  [+] Raccourci Interface Graphique cree sur le Bureau" -ForegroundColor Green

        # Raccourci Console TUI
        $CliShortcutPath = Join-Path $DesktopPath "ESN-Toolkit (Console Interactive).lnk"
        $CliShortcut = $WshShell.CreateShortcut($CliShortcutPath)
        $CliShortcut.TargetPath = "$TargetDir\ESN-Console.bat"
        $CliShortcut.WorkingDirectory = $TargetDir
        $CliShortcut.Description = "ESN-Toolkit - Console d'administration interactive"
        $CliShortcut.IconLocation = "shell32.dll,27" # Icône terminal
        $CliShortcut.Save()
        Write-Host "  [+] Raccourci Console Interactive cree sur le Bureau" -ForegroundColor Green
    } catch {
        Write-Host "  [AVERTISSEMENT] Erreur lors de la creation des raccourcis : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 5. Tâche planifiée optionnelle
if ($RegisterDailyAuditTask) {
    Write-Host ""
    Write-Host "[5/5] Enregistrement de la tache planifiee d'audit quotidien..." -ForegroundColor Yellow
    try {
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TargetDir\Invoke-IncidentAnalysis.ps1`" -SkipHealthScore:`$false"
        $Trigger = New-ScheduledTaskTrigger -Daily -At "08:00"
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "ESN-Toolkit-DailyAudit" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
        Write-Host "  [+] Tache planifiee 'ESN-Toolkit-DailyAudit' activee a 08:00 chaque matin." -ForegroundColor Green
    } catch {
        Write-Host "  [AVERTISSEMENT] Impossible d'enregistrer la tache planifiee : $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[5/5] Tache planifiee automatique : ignoree (activer avec -RegisterDailyAuditTask)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "       INSTALLATION REUSSIE AVEC SUCCES !" -ForegroundColor White
Write-Host "       Emplacement : $TargetDir" -ForegroundColor White
Write-Host "       Lancez 'ESN-Toolkit (Interface Graphique)' depuis votre Bureau." -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""
