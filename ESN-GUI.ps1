#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Toolkit v3.9 - Interface Graphique Officielle (GUI Windows Forms).
    Plateforme d'administration, de dépannage automatisé, de MCO et de projets d'infrastructure.
    Développé pour Amine BERRADA — Administrateur Systèmes & Réseaux / Référent Technique N3.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent
$script:PwshHost = if ($PSVersionTable.PSEdition -eq "Core" -and (Get-Command pwsh -ErrorAction SilentlyContinue)) { "pwsh" } else { "powershell.exe" }

function Start-ESNModuleProcess {
    param([Parameter(Mandatory)][string]$ArgumentList)
    try {
        Start-Process $script:PwshHost -ArgumentList $ArgumentList -ErrorAction Stop
    }
    catch [System.Exception] {
        Append-Log "[ERREUR] Impossible de lancer le module : $($_.Exception.Message)" "Red"
    }
}

# ─────────────────────────────────────────────
# 1. FENÊTRE PRINCIPALE
# ─────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "ESN-Toolkit v3.9 — Plateforme AIOps, MCO & Projets d'Infrastructure"
$form.Size = New-Object System.Drawing.Size(960, 800)
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
$titleLabel.Text = "🖥️ ESN-TOOLKIT v3.9 — Workstation, Infrastructure & Cloud AIOps"
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.AutoSize = $true

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Support N1-N3, Résolution Automatisée, MCO, VMware/Nutanix, Active Directory, SecOps & Projets — Amine BERRADA"
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 205, 237)
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitleLabel.Location = New-Object System.Drawing.Point(22, 45)
$subtitleLabel.AutoSize = $true

$headerPanel.Controls.Add($titleLabel)
$headerPanel.Controls.Add($subtitleLabel)
$form.Controls.Add($headerPanel)

# ─────────────────────────────────────────────
# 3. ONGLETS MÉTIERS
# ─────────────────────────────────────────────
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(15, 95)
$tabControl.Size = New-Object System.Drawing.Size(915, 330)
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)

function Create-ModernButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 270,
        [int]$Height = 42,
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
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8.8, [System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($Action)
    return $btn
}

# --- ONGLET 1 : DIAGNOSTIC & AUTO-FIX ---
$tab1 = New-Object System.Windows.Forms.TabPage
$tab1.Text = "🚀 Diagnostics & Auto-Fix"
$tab1.BackColor = [System.Drawing.Color]::White

$tab1.Controls.Add((Create-ModernButton -Text "📊 Audit Santé + Rapport HTML" -X 20 -Y 20 -Width 270 -Height 48 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Lancement de l'audit de santé global..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -OpenReport"
}))

$tab1.Controls.Add((Create-ModernButton -Text "⚡ Auto-Réparation Complète (AutoFix)" -X 310 -Y 20 -Width 270 -Height 48 -BgColor ([System.Drawing.Color]::FromArgb(216, 59, 1)) -Action {
    Append-Log "Lancement de l'auto-remédiation globale (-AutoFix)..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -AutoFix -OpenReport"
}))

$tab1.Controls.Add((Create-ModernButton -Text "🔍 Mode Simulation (Zéro modif)" -X 600 -Y 20 -Width 270 -Height 48 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Lancement du diagnostic en mode Simulation..." "Blue"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Simulation -OpenReport"
}))

$tab1.Controls.Add((Create-ModernButton -Text "📂 Ouvrir Dernier Rapport HTML" -X 20 -Y 85 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(43, 87, 154)) -Action {
    $repDir = if ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Reports" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
    $latest = Get-ChildItem (Join-Path $repDir "*.html"), "$env:SystemDrive\ESN-Reports\*\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { Start-Process $latest.FullName; Append-Log "Rapport ouvert : $($latest.FullName)" "Green" }
    else { Append-Log "Aucun rapport trouvé." "Yellow" }
}))

$tab1.Controls.Add((Create-ModernButton -Text "📦 Générer Archive ZIP Incident" -X 310 -Y 85 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(85, 85, 85)) -Action {
    $ticket = [Microsoft.VisualBasic.Interaction]::InputBox("Entrez le numéro de ticket (ex: INC-8492) :", "Archive Incident ZIP", "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')")
    if ($ticket) {
        Append-Log "Génération du ZIP incident $ticket..." "Cyan"
        Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -IncidentId `"$ticket`" -ExportZip"
    }
}))

$tab1.Controls.Add((Create-ModernButton -Text "🖥️ Tableau de Bord Centralisé (Web)" -X 600 -Y 85 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(30, 60, 100)) -Action {
    Append-Log "Ouverture du Dashboard Datadog-like..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-CentralDashboard.ps1`""
}))

$tab1.Controls.Add((Create-ModernButton -Text "🎬 Simulateur Live Demo (Auto-Fix)" -X 20 -Y 138 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(0, 130, 90)) -Action {
    Append-Log "Lancement de la simulation d'incident pour démonstration..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentLabSimulator.ps1`" -Scenario N1-Workstation"
}))

$tab1.Controls.Add((Create-ModernButton -Text "📊 Pitch Deck Présentation (Slides HTML)" -X 310 -Y 138 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(100, 40, 140)) -Action {
    $slides = Join-Path $ScriptDir "Presentation\index.html"
    if (Test-Path $slides) { Start-Process $slides; Append-Log "Pitch Deck ouvert dans le navigateur." "Cyan" }
}))

$tabControl.Controls.Add($tab1)

# --- ONGLET 2 : SUPPORT POSTE & M365 (N1/N2) ---
$tab2 = New-Object System.Windows.Forms.TabPage
$tab2.Text = "🛠️ Support N1/N2 & Caches"
$tab2.BackColor = [System.Drawing.Color]::White

$tab2.Controls.Add((Create-ModernButton -Text "🖨️ Purger le Spooler d'impression" -X 20 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    Append-Log "[OK] Spooler d'impression purgé et redémarré avec succès." "Green"
}))

$tab2.Controls.Add((Create-ModernButton -Text "🌐 Reset Pile Réseau (DNS + Winsock)" -X 310 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Append-Log "Réinitialisation DNS et Winsock..." "White"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix DNS,Winsock"
}))

$tab2.Controls.Add((Create-ModernButton -Text "☁️ Vider Caches M365 (Teams, Outlook)" -X 600 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(50, 110, 150)) -Action {
    Append-Log "Purge des caches Teams, Outlook et OneDrive..." "White"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix Teams,Outlook,OneDrive"
}))

$tab2.Controls.Add((Create-ModernButton -Text "🧹 Nettoyer Fichiers Temp Disque C:" -X 20 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(100, 100, 100)) -Action {
    Append-Log "Nettoyage des fichiers temporaires..." "White"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix TempFiles"
}))

$tab2.Controls.Add((Create-ModernButton -Text "🔄 Réinitialiser Windows Update" -X 310 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(100, 100, 100)) -Action {
    Append-Log "Réinitialisation du cache Windows Update..." "White"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-IncidentAnalysis.ps1`" -Fix WindowsUpdate"
}))

$tab2.Controls.Add((Create-ModernButton -Text "📦 Inventaire GLPI / OCS Parc" -X 600 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(0, 130, 150)) -Action {
    Append-Log "Génération de l'inventaire matériel/logiciel GLPI..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-GLPIInventoryAgent.ps1`""
}))

$tab2.Controls.Add((Create-ModernButton -Text "🔄 Conformité WSUS & Patch Management" -X 20 -Y 120 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(40, 90, 130)) -Action {
    Append-Log "Contrôle de conformité et synchronisation WSUS..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-WSUSComplianceManager.ps1`" -OpenReport"
}))

$tabControl.Controls.Add($tab2)

# --- ONGLET 3 : INFRASTRUCTURE & MCO N3 ---
$tab3 = New-Object System.Windows.Forms.TabPage
$tab3.Text = "🏢 Infra, AD & Serveurs"
$tab3.BackColor = [System.Drawing.Color]::White

$tab3.Controls.Add((Create-ModernButton -Text "🏢 Audit Active Directory & Hygiène" -X 20 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(90, 40, 130)) -Action {
    Append-Log "Audit d'hygiène Active Directory..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-ADHygieneCheck.ps1`" -OpenReport"
}))

$tab3.Controls.Add((Create-ModernButton -Text "🖥️ Audit Hyperviseurs (VMware / Nutanix)" -X 310 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 80)) -Action {
    Append-Log "Audit santé clusters VMware vSphere & Nutanix..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-HypervisorAudit.ps1`""
}))

$tab3.Controls.Add((Create-ModernButton -Text "✉️ Audit Exchange & Routage SMTP" -X 600 -Y 15 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(0, 100, 160)) -Action {
    Append-Log "Audit Exchange Hybride / On-Premise..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-ExchangeHealthCheck.ps1`""
}))

$tab3.Controls.Add((Create-ModernButton -Text "🌐 Audit Cœur Réseau (DHCP/DNS/PKI)" -X 20 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(40, 80, 120)) -Action {
    Append-Log "Audit DHCP Scopes, DNS Scavenging et Certificats SSL..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-CoreServicesAudit.ps1`""
}))

$tab3.Controls.Add((Create-ModernButton -Text "☁️ Audit Cloud Hybride (Entra ID, Intune)" -X 310 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Audit Cloud Hybride Entra ID Connect / Intune..." "Blue"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-CloudHybridAudit.ps1`" -OpenReport"
}))

$tab3.Controls.Add((Create-ModernButton -Text "💾 Audit Sauvegardes Veeam & SecOps" -X 600 -Y 68 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Audit des sauvegardes Veeam et immutabilité..." "Green"
    if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
        Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
        $v = Test-ESNVeeamStatus
        Append-Log "[Veeam] Statut: $($v.Status) | Services actifs: $($v.ServicesRunning)" "Green"
    }
}))

$tabControl.Controls.Add($tab3)

# --- ONGLET 4 : MIGRATION DE POSTE DE A A Z ---
$tab4 = New-Object System.Windows.Forms.TabPage
$tab4.Text = "🚚 Migration Poste (A à Z)"
$tab4.BackColor = [System.Drawing.Color]::White

$tab4.Controls.Add((Create-ModernButton -Text "📤 Sauvegarder Ancien Poste (Capture A-Z)" -X 20 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Lancement de l'Assistant de Sauvegarde / Migration..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-FullStationMigration.ps1`""
}))

$tab4.Controls.Add((Create-ModernButton -Text "📥 Restaurer sur Nouveau Poste (1-Clic)" -X 310 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Lancement de la Restauration Nouveau Poste..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-FullStationMigration.ps1`""
}))

$tab4.Controls.Add((Create-ModernButton -Text "📂 Ouvrir Dossier Migrations" -X 600 -Y 20 -Width 270 -Height 50 -BgColor ([System.Drawing.Color]::FromArgb(85, 85, 85)) -Action {
    $migDir = if ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Migrations" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Migrations" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Migrations" }
    if (-not (Test-Path $migDir)) { New-Item $migDir -ItemType Directory -Force | Out-Null }
    Start-Process "explorer.exe" $migDir
    Append-Log "Dossier ouvert : $migDir" "Green"
}))

$tab4.Controls.Add((Create-ModernButton -Text "📄 Consulter Dernier Rapport Migration" -X 20 -Y 85 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(43, 87, 154)) -Action {
    $migRoot = if ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Migrations" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Migrations" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Migrations" }
    $latestReport = Get-ChildItem (Join-Path $migRoot "*\Migration-Report.html") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestReport) {
        Start-Process $latestReport.FullName
        Append-Log "Rapport ouvert : $($latestReport.FullName)" "Green"
    } else {
        Append-Log "Aucun rapport de migration trouvé." "Yellow"
    }
}))

$tabControl.Controls.Add($tab4)

# --- ONGLET 5 : AIOPS & SÉCURITÉ ---
$tab5 = New-Object System.Windows.Forms.TabPage
$tab5.Text = "🤖 AIOps & SecOps"
$tab5.BackColor = [System.Drawing.Color]::White

$tab5.Controls.Add((Create-ModernButton -Text "🤖 Activer Gardien Self-Healing" -X 20 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Installation de la tâche planifiée Self-Healing (15 min)..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-SelfHealingService.ps1`" -InstallServiceTask"
}))

$tab5.Controls.Add((Create-ModernButton -Text "🚀 Zero-Touch Provisioning (Poste Neuf)" -X 310 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Lancement de la préparation de poste neuf..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-ZeroTouchProvisioning.ps1`""
}))

$tab5.Controls.Add((Create-ModernButton -Text "🛡️ Audit & Durcissement ANSSI" -X 600 -Y 20 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(180, 40, 40)) -Action {
    Append-Log "Lancement de l'audit de sécurité et durcissement..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-SecurityHardening.ps1`" -OpenReport"
}))

$tab5.Controls.Add((Create-ModernButton -Text "🚨 Triage Urgence P1 (Astreinte 24/7)" -X 20 -Y 78 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(180, 0, 0)) -Action {
    Append-Log "Extraction crash dumps et boîte noire P1..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-P1EmergencyTriage.ps1`""
}))

$tab5.Controls.Add((Create-ModernButton -Text "🛑 Ransomware Emergency KillSwitch" -X 310 -Y 78 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(120, 0, 0)) -Action {
    Append-Log "Isolement d'urgence de la machine..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-RansomwareShield.ps1`""
}))

$tab5.Controls.Add((Create-ModernButton -Text "🔮 Analyse Prédictive Saturation & SSD" -X 600 -Y 78 -Width 270 -Height 45 -BgColor ([System.Drawing.Color]::FromArgb(90, 40, 130)) -Action {
    Append-Log "Calcul prédictif saturation disque et usure..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-PredictiveHealthAnalysis.ps1`""
}))

$tab5.Controls.Add((Create-ModernButton -Text "🛡️ Audit Posture Zero-Trust (TPM/VBS)" -X 20 -Y 130 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(140, 20, 20)) -Action {
    Append-Log "Lancement de l'audit Zero-Trust (TPM 2.0, VBS, LSA)..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-ZeroTrustAudit.ps1`" -OpenReport"
}))

$tab5.Controls.Add((Create-ModernButton -Text "📢 Dispatcher Alertes ITSM (GLPI/Teams)" -X 310 -Y 130 -Width 270 -Height 42 -BgColor ([System.Drawing.Color]::FromArgb(200, 100, 0)) -Action {
    Append-Log "Simulation de transmission d'incident ITSM..." "Yellow"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-ITSMConnector.ps1`" -Target Simulation"
}))

$tabControl.Controls.Add($tab5)

# --- ONGLET 6 : PROJETS RÉFÉRENTS & GOUVERNANCE COPIL ---
$tab6 = New-Object System.Windows.Forms.TabPage
$tab6.Text = "💼 Projets Référents & COPIL"
$tab6.BackColor = [System.Drawing.Color]::White

$tab6.Controls.Add((Create-ModernButton -Text "🔄 Migration Inter-Domaines AD" -X 20 -Y 12 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(40, 70, 120)) -Action {
    Append-Log "Simulation / Exécution Migration Inter-Domaines AD..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\AD-Migration\Invoke-ADDomainMigration.ps1`" -ReportOnly"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🛡️ Rollout EDR Massif (+200 Postes)" -X 310 -Y 12 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(150, 40, 40)) -Action {
    Append-Log "Déploiement industrialisé EDR SentinelOne..." "Red"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\EDR-Deployment\Invoke-EDRMassRollout.ps1`" -ReportOnly"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🔌 Config Switchs Aruba CX" -X 600 -Y 12 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(216, 90, 0)) -Action {
    Append-Log "Génération configuration Switchs Aruba CX (VLAN/LACP)..." "Yellow"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\Network-Aruba\New-ArubaSwitchConfig.ps1`""
}))

$tab6.Controls.Add((Create-ModernButton -Text "🔐 Déploiement Windows LAPS" -X 20 -Y 56 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(0, 100, 100)) -Action {
    Append-Log "Audit & Déploiement Windows LAPS (Anti-Pass-the-Hash)..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\Windows-LAPS\Deploy-WindowsLAPS.ps1`" -ReportOnly"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🏢 Bascule Datacenter Veeam (PRA)" -X 310 -Y 56 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(16, 124, 65)) -Action {
    Append-Log "Orchestration Failover Plan Veeam Datacenter..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\Datacenter-Migration\Invoke-VeeamFailoverPlan.ps1`" -DryRun"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🖥️ Industrialisation MDT (Parc 200+)" -X 600 -Y 56 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(0, 120, 212)) -Action {
    Append-Log "Industrialisation MDT / WDS Postes Texdecor..." "Blue"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\MDT-Deployment\Invoke-MDTIndustrialization.ps1`" -ReportOnly"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🌐 Refonte WAN & PRA Intersites" -X 20 -Y 100 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(120, 60, 140)) -Action {
    Append-Log "Audit WAN MPLS & Réplication PRA Intersites..." "Magenta"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Projects\WAN-MPLS-Refonte\Invoke-WANMigrationPlan.ps1`" -ReportOnly"
}))

$tab6.Controls.Add((Create-ModernButton -Text "📑 Rapport Mensuel COPIL / COTECH" -X 310 -Y 100 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(0, 130, 90)) -Action {
    Append-Log "Génération du rapport exécutif COPIL (SLA 99.9%)..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-COPILReportGenerator.ps1`""
}))

$tab6.Controls.Add((Create-ModernButton -Text "📊 Sizing Infrastructure N+1 Stockage" -X 600 -Y 100 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(70, 70, 70)) -Action {
    Append-Log "Calcul de dimensionnement cluster N+1 et stockage..." "White"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-InfrastructureSizing.ps1`""
}))

$tab6.Controls.Add((Create-ModernButton -Text "📑 Dossier Officiel PRA / DRP" -X 20 -Y 144 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(160, 40, 90)) -Action {
    Append-Log "Génération du dossier officiel PRA / DRP pour audit..." "Cyan"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-DRPGenerator.ps1`" -OpenReport"
}))

$tab6.Controls.Add((Create-ModernButton -Text "🐧 Audit Serveur Linux (SSH)" -X 310 -Y 144 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(40, 110, 40)) -Action {
    Append-Log "Audit de santé serveur Linux via SSH natif..." "Green"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-LinuxHeterogeneousAudit.ps1`" -SimulationMode -OpenReport"
}))

$tab6.Controls.Add((Create-ModernButton -Text "📡 Déployer Sondes PRTG (XML)" -X 600 -Y 144 -Width 270 -Height 38 -BgColor ([System.Drawing.Color]::FromArgb(200, 120, 0)) -Action {
    Append-Log "Génération et déploiement des sondes PRTG..." "Yellow"
    Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-PRTGSensorDeployer.ps1`" -TargetSensor All"
}))

$tabControl.Controls.Add($tab6)

# --- ONGLET 7 : ELITE AIOPS & CHAOS LAB (v3.9) ---
$tab7 = New-Object System.Windows.Forms.TabPage
$tab7.Text = "🧠 Elite AIOps v3.9"
$tab7.BackColor = [System.Drawing.Color]::White

$eliteButtons = @(
    @{ Text = "🧠 Nutanix Prism Health AI"; Script = "Invoke-NutanixPrismHealthAI.ps1"; Args = "-Simulate"; Log = "Nutanix Prism AI (CVM / IOPS / Runway)..."; R = 16; G = 124; B = 65; X = 20; Y = 20 },
    @{ Text = "🕵️ AD Threat Hunter (Kerberoast)"; Script = "Invoke-ActiveDirectoryThreatHunter.ps1"; Args = "-Simulate"; Log = "Active Directory Threat Hunter (MITRE ATT&CK)..."; R = 190; G = 40; B = 40; X = 310; Y = 20 },
    @{ Text = "⚡ Audit Parallèle 500+ Serveurs"; Script = "Invoke-HighSpeedParallelAuditor.ps1"; Args = "-Simulate"; Log = "RunspacePool Haute Vitesse (500 noeuds)..."; R = 0; G = 120; B = 212; X = 600; Y = 20 },
    @{ Text = "🔒 Veeam Immutabilité Linux XFS"; Script = "Invoke-VeeamImmutableAudit.ps1"; Args = "-Simulate"; Log = "Audit Veeam Hardened Repo (chattr +i)..."; R = 120; G = 60; B = 140; X = 20; Y = 85 },
    @{ Text = "📈 Dashboard COPIL HTML5 SVG"; Script = "Invoke-CopilDashboardGenerator.ps1"; Args = ""; Log = "Génération Dashboard COPIL Dark Mode SVG..."; R = 0; G = 130; B = 90; X = 310; Y = 85 },
    @{ Text = "🧪 Chaos Lab (DNS/Disk/DFSR)"; Script = "Invoke-IncidentLabSimulator.ps1"; Args = "-Scenario Chaos-DnsNtpStorm -Simulate"; Log = "Chaos Engineering Lab Simulator..."; R = 200; G = 120; B = 0; X = 600; Y = 85 }
)
foreach ($eb in $eliteButtons) {
    $b = Create-ModernButton -Text $eb.Text -X $eb.X -Y $eb.Y -Width 270 -Height 46 -BgColor ([System.Drawing.Color]::FromArgb($eb.R, $eb.G, $eb.B)) -Action {
        param($sender, $e)
        $cfg = $sender.Tag
        Append-Log $cfg.Log "Cyan"
        Start-ESNModuleProcess -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\$($cfg.Script)`" $($cfg.Args)"
    }
    $b.Tag = $eb
    $tab7.Controls.Add($b)
}
$tabControl.Controls.Add($tab7)

$form.Controls.Add($tabControl)

# ─────────────────────────────────────────────
# 4. CONSOLE DE SORTIE / LOGS EN TEMPS REEL
# ─────────────────────────────────────────────
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(15, 435)
$logBox.Size = New-Object System.Drawing.Size(915, 275)
$logBox.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 33)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 242)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$logBox.ReadOnly = $true
$logBox.BorderStyle = "None"
$form.Controls.Add($logBox)

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
        "Magenta"{ [System.Drawing.Color]::FromArgb(218, 112, 214) }
        default  { [System.Drawing.Color]::White }
    }
    $logBox.AppendText($fullMsg)
    $logBox.ScrollToCaret()
}

# Message initial
Append-Log "Bienvenue dans ESN-Toolkit v3.9 (Environnement Enterprise Initialisé)" "Green"
Append-Log "Hôte local : $env:COMPUTERNAME | Session : $env:USERNAME" "Cyan"
Append-Log "Prêt pour le diagnostic, l'astreinte 24/7, la gouvernance COPIL et les projets d'infrastructure." "White"

# Bouton pour effacer les logs
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Vider la console"
$btnClear.Location = New-Object System.Drawing.Point(810, 720)
$btnClear.Size = New-Object System.Drawing.Size(120, 28)
$btnClear.Add_Click({ $logBox.Clear(); Append-Log "Console réinitialisée." "Cyan" })
$form.Controls.Add($btnClear)

# ─────────────────────────────────────────────
# 5. AFFICHAGE DE LA FENETRE
# ─────────────────────────────────────────────
[void]$form.ShowDialog()
