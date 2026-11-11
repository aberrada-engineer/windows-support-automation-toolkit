#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Toolkit v3.0 - Interface Graphique Officielle (GUI Windows Forms).
    Plateforme d'administration, de dépannage automatisé et de MCO.
    Développé pour Amine BERRADA — Administrateur Systèmes & Réseaux.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

# ─────────────────────────────────────────────
# 1. FENETRE PRINCIPALE
# ─────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "ESN-Toolkit v3.0 — Console d'Administration & Support IT"
$form.Size = New-Object System.Drawing.Size(950, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# ─────────────────────────────────────────────
# 2. EN-TÊTE MODERNE
# ─────────────────────────────────────────────
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 85
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(24, 43, 73) # Bleu Marine Navy

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "🖥️ ESN-TOOLKIT v3.0 — Workstation & Infrastructure Automation"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.AutoSize = $true

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "MCO, Diagnostics N1-N3, Résolution Automatique, Active Directory, SecOps & Veeam"
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 205, 237)
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitleLabel.Location = New-Object System.Drawing.Point(22, 45)
$subtitleLabel.AutoSize = $true

$headerPanel.Controls.Add($titleLabel)
$headerPanel.Controls.Add($subtitleLabel)
$form.Controls.Add($headerPanel)

# ─────────────────────────────────────────────
# 3. ONGLETS METIERS
# ─────────────────────────────────────────────
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(15, 95)
$tabControl.Size = New-Object System.Drawing.Size(905, 280)
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)

# Helper pour créer un bouton moderne
function Create-ModernButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 260,
        [int]$Height = 45,
        [System.Drawing.Color]$BgColor,
        [scriptblock]$Action
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, $Height)
    $btn.BackColor = $BgColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($Action)
    return $btn
}

# --- ONGLET 1 : DIAGNOSTIC & AUTO-FIX (ACTIONS MAJEURES) ---
$tab1 = New-Object System.Windows.Forms.TabPage
$tab1.Text = "🚀 Diagnostics & Auto-Fix"
$tab1.BackColor = [System.Drawing.Color]::White

$btnHealth = Create-ModernButton -Text "📊 Audit Sante + Rapport HTML" -X 20 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Lancement de l'audit de sante global..." "Cyan"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -OpenReport"
}
$tab1.Controls.Add($btnHealth)

$btnAutoFix = Create-ModernButton -Text "⚡ Auto-Reparation Complete (AutoFix)" -X 310 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(216, 59, 1)) -Action {
    Append-Log "Lancement de l'auto-remediation globale (-AutoFix)..." "Red"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -AutoFix -OpenReport"
}
$tab1.Controls.Add($btnAutoFix)

$btnSimulation = Create-ModernButton -Text "🔍 Mode Simulation (Zero modif)" -X 600 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Lancement du diagnostic en mode Simulation..." "Blue"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Simulation -OpenReport"
}
$tab1.Controls.Add($btnSimulation)

$btnOpenRep = Create-ModernButton -Text "📂 Ouvrir le Dernier Rapport HTML" -X 20 -Y 90 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(43, 87, 154)) -Action {
    $latest = Get-ChildItem "C:\ESN-Toolkit\Reports\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Start-Process $latest.FullName
        Append-Log "Rapport ouvert : $($latest.FullName)" "Green"
    } else {
        Append-Log "Aucun rapport trouve dans C:\ESN-Toolkit\Reports" "Yellow"
    }
}
$tab1.Controls.Add($btnOpenRep)

$btnZip = Create-ModernButton -Text "📦 Generer Archive ZIP Incident" -X 310 -Y 90 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(85, 85, 85)) -Action {
    $ticket = [Microsoft.VisualBasic.Interaction]::InputBox("Entrez le numero de ticket (ex: INC-8492) :", "Archive Incident ZIP", "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')")
    if ($ticket) {
        Append-Log "Generation du ZIP incident $ticket..." "Cyan"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -IncidentId `"$ticket`" -ExportZip"
    }
}
$tab1.Controls.Add($btnZip)

$tabControl.Controls.Add($tab1)

# --- ONGLET 2 : SUPPORT POSTE & M365 (N1/N2) ---
$tab2 = New-Object System.Windows.Forms.TabPage
$tab2.Text = "🛠️ Support N1/N2 & Caches"
$tab2.BackColor = [System.Drawing.Color]::White

$btnSpooler = Create-ModernButton -Text "🖨️ Purger le Spooler d'impression" -X 20 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Append-Log "Nettoyage du spooler d'impression en cours..." "White"
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    Append-Log "[OK] Spooler d'impression purge et redemarre avec succes." "Green"
}
$tab2.Controls.Add($btnSpooler)

$btnNetwork = Create-ModernButton -Text "🌐 Reset Pile Reseau (DNS + Winsock)" -X 310 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Append-Log "Reinitialisation DNS et Winsock..." "White"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix DNS,Winsock"
}
$tab2.Controls.Add($btnNetwork)

$btnM365 = Create-ModernButton -Text "☁️ Vider Caches M365 (Teams, Outlook)" -X 600 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Append-Log "Purge des caches Teams, Outlook et OneDrive..." "White"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix Teams,Outlook,OneDrive"
}
$tab2.Controls.Add($btnM365)

$btnTemp = Create-ModernButton -Text "🧹 Nettoyer Fichiers Temp Disque C:" -X 20 -Y 80 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(100, 100, 100)) -Action {
    Append-Log "Nettoyage des fichiers temporaires..." "White"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix TempFiles"
}
$tab2.Controls.Add($btnTemp)

$btnWinUp = Create-ModernButton -Text "🔄 Reinitialiser Windows Update" -X 310 -Y 80 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(100, 100, 100)) -Action {
    Append-Log "Reinitialisation du cache Windows Update..." "White"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix WindowsUpdate"
}
$tab2.Controls.Add($btnWinUp)

$tabControl.Controls.Add($tab2)

# --- ONGLET 3 : INFRASTRUCTURE, AD & SECOPS (ADMIN / INGÉNIEUR) ---
$tab3 = New-Object System.Windows.Forms.TabPage
$tab3.Text = "🏢 Infra, AD & SecOps"
$tab3.BackColor = [System.Drawing.Color]::White

$btnAD = Create-ModernButton -Text "🏢 Audit Active Directory & FSMO" -X 20 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(90, 40, 130)) -Action {
    Append-Log "Verification Active Directory et FSMO..." "Cyan"
    if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
        Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
        $res = Test-ESNADHealth
        Append-Log "[AD] Domaine: $($res.DomainName) | Est-DC: $($res.IsDomainCtrl) | FSMO: $($res.FSMOReachable)" "Green"
    }
}
$tab3.Controls.Add($btnAD)

$btnSec = Create-ModernButton -Text "🛡️ Audit Posture Securite (BitLocker, EDR)" -X 310 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(180, 40, 40)) -Action {
    Append-Log "Verification posture de securite (BitLocker, SMBv1, EDR)..." "Cyan"
    if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
        Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
        $sec = Test-ESNSecurityPosture
        Append-Log "[SecOps] BitLocker: $($sec.BitLockerStatus) | SMBv1: $($sec.SMBv1Status) | EDR: $($sec.EDRActive)" "Green"
    }
}
$tab3.Controls.Add($btnSec)

$btnVeeam = Create-ModernButton -Text "💾 Audit Sauvegardes Veeam" -X 600 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(0, 100, 80)) -Action {
    Append-Log "Verification des services et journaux Veeam..." "Cyan"
    if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
        Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
        $v = Test-ESNVeeamStatus
        Append-Log "[Veeam] Statut: $($v.Status) | Services actifs: $($v.ServicesRunning)" "Green"
    }
}
$tab3.Controls.Add($btnVeeam)

$tabControl.Controls.Add($tab3)

# --- ONGLET 4 : MIGRATION DE POSTE DE A A Z ---
$tab4 = New-Object System.Windows.Forms.TabPage
$tab4.Text = "🚚 Migration de Poste (A à Z)"
$tab4.BackColor = [System.Drawing.Color]::White

$btnMigWizard = Create-ModernButton -Text "📤 Sauvegarder Ancien Poste (Capture A-Z)" -X 20 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Lancement de l'Assistant de Sauvegarde / Migration..." "Cyan"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-FullStationMigration.ps1`""
}
$tab4.Controls.Add($btnMigWizard)

$btnMigRestore = Create-ModernButton -Text "📥 Restaurer sur Nouveau Poste (1-Clic)" -X 310 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Lancement de la Restauration Nouveau Poste..." "Cyan"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-FullStationMigration.ps1`""
}
$tab4.Controls.Add($btnMigRestore)

$btnOpenMigDir = Create-ModernButton -Text "📂 Ouvrir Dossier Migrations" -X 600 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(85, 85, 85)) -Action {
    $migDir = "C:\ESN-Toolkit\Migrations"
    if (-not (Test-Path $migDir)) { New-Item $migDir -ItemType Directory -Force | Out-Null }
    Start-Process "explorer.exe" $migDir
    Append-Log "Dossier ouvert : $migDir" "Green"
}
$tab4.Controls.Add($btnOpenMigDir)

$btnLastMigReport = Create-ModernButton -Text "📄 Consulter Dernier Rapport Migration" -X 20 -Y 85 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(43, 87, 154)) -Action {
    $latestReport = Get-ChildItem "C:\ESN-Toolkit\Migrations\*\Migration-Report.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestReport) {
        Start-Process $latestReport.FullName
        Append-Log "Rapport ouvert : $($latestReport.FullName)" "Green"
    } else {
        Append-Log "Aucun rapport de migration trouvé." "Yellow"
    }
}
$tab4.Controls.Add($btnLastMigReport)

$tabControl.Controls.Add($tab4)
$form.Controls.Add($tabControl)

# ─────────────────────────────────────────────
# 4. CONSOLE DE SORTIE / LOGS EN TEMPS REEL
# ─────────────────────────────────────────────
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(15, 390)
$logBox.Size = New-Object System.Drawing.Size(905, 240)
$logBox.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 33)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 242)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$logBox.ReadOnly = $true
$logBox.BorderStyle = "None"
$form.Controls.Add($logBox)

# Helper pour ajouter du texte dans la console
function Append-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $fullMsg = "[$timestamp] $Message`n"
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionLength = 0
    $logBox.SelectionColor = switch ($Color) {
        "Green"  { [System.Drawing.Color]::FromArgb(78, 201, 176) }
        "Red"    { [System.Drawing.Color]::FromArgb(244, 71, 71) }
        "Yellow" { [System.Drawing.Color]::FromArgb(220, 200, 90) }
        "Cyan"   { [System.Drawing.Color]::FromArgb(86, 156, 214) }
        "Blue"   { [System.Drawing.Color]::FromArgb(100, 160, 250) }
        default  { [System.Drawing.Color]::White }
    }
    $logBox.AppendText($fullMsg)
    $logBox.ScrollToCaret()
}

# Message initial
Append-Log "Bienvenue dans ESN-Toolkit v3.0 (Environnement initialise)" "Green"
Append-Log "Hôte local : $env:COMPUTERNAME | Session : $env:USERNAME" "Cyan"
Append-Log "Prêt pour les opérations de diagnostic, remédiation et audit d'infrastructure." "White"

# Bouton pour effacer les logs
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Vider la console"
$btnClear.Location = New-Object System.Drawing.Point(800, 640)
$btnClear.Size = New-Object System.Drawing.Size(120, 28)
$btnClear.Add_Click({ $logBox.Clear(); Append-Log "Console réinitialisée." "Cyan" })
$form.Controls.Add($btnClear)

# ─────────────────────────────────────────────
# 5. AFFICHAGE DE LA FENETRE
# ─────────────────────────────────────────────
[void]$form.ShowDialog()
