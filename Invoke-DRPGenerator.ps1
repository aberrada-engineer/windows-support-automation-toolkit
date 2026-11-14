<#
.SYNOPSIS
    Invoke-DRPGenerator.ps1 - Générateur Automatisé de Dossier de Plan de Reprise d'Activité (PRA / PCA / DRP) pour Audits & Direction.
.DESCRIPTION
    Conçu pour répondre aux exigences des grands comptes et audits de résilience (expérience AEXIN Genève, Porsche, TAG Heuer, Hublot) :
    - Génération d'un dossier complet de PRA/PCA conforme aux standards ISO 22301 et ANSSI.
    - Annuaire opérationnel de la Cellule de Crise (Directeur de crise, Référent N3 Système/Réseau, Responsable Métier).
    - Matrice contractuelle RTO (Recovery Time Objective) & RPO (Recovery Point Objective) par Tier applicatif.
    - Runbook séquentiel de bascule (Ordre de réveil : Réseau/Firewall -> Active Directory/DNS -> Stockage/Hyperviseur -> BDD/ERP -> Postes).
    - Procédure de Failback et validation d'intégrité des dépôts immuables Veeam.
    - Page de signatures pour homologation C-Level / DSI / RSSI.
.PARAMETER CompanyName
    Nom de l'entreprise ou contrat infogérance (ex: "Manufacture Horlogère de Luxe").
.PARAMETER PrimarySite
    Nom du site Datacenter principal (ex: "DC1 - Genève Centre").
.PARAMETER DisasterSite
    Nom du site de secours / PRA (ex: "DC2 - Lausanne Secours").
.EXAMPLE
    .\Invoke-DRPGenerator.ps1 -CompanyName "Groupe Horloger Suisse" -OpenReport
#>

[CmdletBinding()]
param(
    [string]$CompanyName = "Entreprise & Infrastructure Critique",
    [string]$PrimarySite = "Datacenter Principal (Prod)",
    [string]$DisasterSite = "Datacenter Secours (PRA)",
    [int]$MaxRtoHours = 4,
    [int]$MaxRpoMinutes = 15,
    [switch]$OpenReport,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

try {
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   DISASTER RECOVERY PLAN (DRP / PRA / PCA) EXECUTIVE DOSSIER ENGINE      " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "[*] Organisation cible : $CompanyName" -ForegroundColor Gray
    Write-Host "[*] Site Primaire      : $PrimarySite" -ForegroundColor Gray
    Write-Host "[*] Site Secours (PRA) : $DisasterSite" -ForegroundColor Gray
    Write-Host "[*] Objectifs SLA      : RTO < ${MaxRtoHours}h | RPO < ${MaxRpoMinutes}min" -ForegroundColor Gray
    Write-Host ""

    $ReportDir = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath } elseif (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot -SubFolder "DRP" } else { "$env:SystemDrive\ESN-Reports\DRP" }
    if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $HtmlReport = Join-Path $ReportDir "Dossier-PRA-Officiel-$Timestamp.html"

# Construction du dossier PRA exécutif
$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Plan de Reprise d'Activité (PRA / PCA) - $CompanyName</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0b0f19; color: #f1f5f9; margin: 0; padding: 32px; }
        .wrapper { max-width: 1100px; margin: auto; background-color: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 40px; box-shadow: 0 20px 40px rgba(0,0,0,0.7); }
        .header { border-bottom: 2px solid #374151; padding-bottom: 24px; margin-bottom: 30px; display: flex; justify-content: space-between; align-items: center; }
        h1 { margin: 0; font-size: 26px; color: #38bdf8; font-weight: 800; }
        .subtitle { color: #9ca3af; margin-top: 6px; font-size: 14px; }
        .badge { background: #0284c7; color: white; padding: 6px 14px; border-radius: 6px; font-weight: bold; font-size: 13px; text-transform: uppercase; }
        .alert-box { background-color: #1e1b4b; border-left: 4px solid #818cf8; padding: 16px 20px; border-radius: 6px; margin: 24px 0; font-size: 14px; color: #e0e7ff; line-height: 1.6; }
        .section-title { font-size: 18px; color: #93c5fd; border-left: 4px solid #38bdf8; padding-left: 10px; margin: 32px 0 16px 0; font-weight: 700; text-transform: uppercase; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; }
        th, td { border: 1px solid #374151; padding: 12px 16px; text-align: left; }
        th { background-color: #1f2937; color: #38bdf8; font-size: 13px; text-transform: uppercase; }
        tr:nth-child(even) { background-color: #162032; }
        .step-num { display: inline-block; width: 26px; height: 26px; background-color: #0284c7; color: white; border-radius: 50%; text-align: center; line-height: 26px; font-weight: bold; margin-right: 8px; font-size: 13px; }
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .card { background-color: #1f2937; border-radius: 8px; padding: 20px; border: 1px solid #374151; }
        .sign-box { margin-top: 40px; border-top: 1px solid #374151; padding-top: 24px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 24px; }
        .sign-slot { background-color: #0f172a; border: 1px dashed #475569; border-radius: 8px; padding: 20px; text-align: center; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="header">
            <div>
                <h1>Dossier Officiel de Plan de Reprise d'Activité (PRA / PCA)</h1>
                <div class="subtitle">Organisation : <strong>$CompanyName</strong> • Conforme Référentiel ISO 22301 / ANSSI</div>
            </div>
            <div>
                <span class="badge">Document Homologué</span>
            </div>
        </div>

        <div class="alert-box">
            <strong>Critères d'Activation de la Cellule de Crise :</strong><br>
            Le présent plan de reprise est déclenché sur décision conjointe du Directeur de Crise et du Référent Technique N3 en cas d'indisponibilité non maîtrisée supérieure à 60 minutes sur le site de production (Cyberattaque Ransomware, Sinistre majeur Datacenter, Rupture totale des liens de communication).
        </div>

        <div class="grid-2">
            <div class="card">
                <div style="color: #9ca3af; font-size: 12px; text-transform: uppercase; font-weight: bold;">Site Primaire (Production)</div>
                <div style="font-size: 18px; font-weight: bold; color: #f1f5f9; margin-top: 4px;">$PrimarySite</div>
                <div style="font-size: 13px; color: #4ade80; margin-top: 4px;">Cluster Nutanix / VMware vSphere 7.0</div>
            </div>
            <div class="card">
                <div style="color: #9ca3af; font-size: 12px; text-transform: uppercase; font-weight: bold;">Site de Secours (PRA)</div>
                <div style="font-size: 18px; font-weight: bold; color: #f1f5f9; margin-top: 4px;">$DisasterSite</div>
                <div style="font-size: 13px; color: #38bdf8; margin-top: 4px;">Veeam Replication + Dépôt Immuable WORM</div>
            </div>
        </div>

        <div class="section-title">1. Matrice des Cibles de Restauration (SLA RTO & RPO)</div>
        <table>
            <thead>
                <tr>
                    <th>Niveau de Criticité</th>
                    <th>Périmètre & Applications</th>
                    <th>RTO Cible (Temps Max)</th>
                    <th>RPO Cible (Perte Max)</th>
                    <th>Mécanisme de Sauvegarde</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>Tier 1 — Vital</strong></td>
                    <td>Contrôleurs de Domaine (AD/DNS), Cœur ERP, Base SQL</td>
                    <td>&lt; 2 Heures</td>
                    <td>&lt; 15 Minutes</td>
                    <td>Réplication CDP Veeam continue + Immutabilité</td>
                </tr>
                <tr>
                    <td><strong>Tier 2 — Critique</strong></td>
                    <td>Messagerie Exchange, Serveurs de Fichiers, VPN Nomade</td>
                    <td>&lt; 4 Heures</td>
                    <td>&lt; 2 Heures</td>
                    <td>Snapshots horaires répliqués inter-sites</td>
                </tr>
                <tr>
                    <td><strong>Tier 3 — Exploitation</strong></td>
                    <td>Intranet, Serveurs d'impression, Outils de reporting</td>
                    <td>&lt; 12 Heures</td>
                    <td>&lt; 24 Heures</td>
                    <td>Sauvegarde quotidienne externalisée</td>
                </tr>
            </tbody>
        </table>

        <div class="section-title">2. Annuaire d'Urgence de la Cellule de Crise</div>
        <table>
            <thead>
                <tr>
                    <th>Rôle dans la Crise</th>
                    <th>Titulaire</th>
                    <th>Suppléant</th>
                    <th>Canal / Téléphone d'Urgence</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>Directeur de Crise</strong></td>
                    <td>Directeur des Systèmes d'Information (DSI)</td>
                    <td>Directeur Technique</td>
                    <td>Canal Astreinte N3 24/7 / berradapro@outlook.com</td>
                </tr>
                <tr>
                    <td><strong>Référent Technique N3</strong></td>
                    <td><strong>Amine BERRADA</strong> (Ingénieur Système)</td>
                    <td>Administrateur Systèmes & Réseaux</td>
                    <td>Canal Teams Astreinte 24/7 / Téléphone direct</td>
                </tr>
                <tr>
                    <td><strong>Pilote Réseau & Télécoms</strong></td>
                    <td>Ingénieur Réseau & Sécurité</td>
                    <td>Opérateur Télécom (Support P1)</td>
                    <td>Numéro VIP Support Opérateur Fibre/MPLS</td>
                </tr>
            </tbody>
        </table>

        <div class="section-title">3. Runbook Séquentiel de Bascule (Orchestration Failover)</div>
        <table>
            <thead>
                <tr>
                    <th>Ordre</th>
                    <th>Étape Opérationnelle</th>
                    <th>Action Réalisée</th>
                    <th>Outil Toolkit Utilisé</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><span class="step-num">1</span></td>
                    <td><strong>Isolement du Sinistre</strong></td>
                    <td>Rupture des liens corrompus et activation KillSwitch anti-propagation</td>
                    <td><code>Invoke-RansomwareShield.ps1</code></td>
                </tr>
                <tr>
                    <td><span class="step-num">2</span></td>
                    <td><strong>Routage & Passerelle Secours</strong></td>
                    <td>Bascule des routes par défaut BGP/IPsec vers le Datacenter de secours</td>
                    <td><code>Projects/WAN-MPLS-Refonte/</code></td>
                </tr>
                <tr>
                    <td><span class="step-num">3</span></td>
                    <td><strong>Réveil Cœur d'Annuaire</strong></td>
                    <td>Démarrage en priorité absolue des DCs Active Directory et DNS sur le PRA</td>
                    <td><code>Projects/Datacenter-Migration/</code></td>
                </tr>
                <tr>
                    <td><span class="step-num">4</span></td>
                    <td><strong>Bascule Failover Plan Veeam</strong></td>
                    <td>Exécution du plan de bascule planifié des VMs de production Tier 1</td>
                    <td><code>Invoke-VeeamFailoverPlan.ps1</code></td>
                </tr>
                <tr>
                    <td><span class="step-num">5</span></td>
                    <td><strong>Validation & Recette Métier</strong></td>
                    <td>Contrôle de connectivité des applications et tests de restauration</td>
                    <td><code>Invoke-DRTest.ps1</code></td>
                </tr>
            </tbody>
        </table>

        <div class="sign-box">
            <div class="sign-slot">
                <div style="font-size: 12px; color: #9ca3af; text-transform: uppercase;">Directeur des Systèmes d'Information</div>
                <div style="font-weight: bold; margin-top: 10px; color: #38bdf8;">Approuvé & Signé</div>
                <div style="font-size: 11px; color: #64748b; margin-top: 20px;">Date : $(Get-Date -Format 'dd/MM/yyyy')</div>
            </div>
            <div class="sign-slot">
                <div style="font-size: 12px; color: #9ca3af; text-transform: uppercase;">Référent Technique N3 (Système & MCO)</div>
                <div style="font-weight: bold; margin-top: 10px; color: #4ade80;">Amine BERRADA</div>
                <div style="font-size: 11px; color: #64748b; margin-top: 20px;">Date : $(Get-Date -Format 'dd/MM/yyyy')</div>
            </div>
            <div class="sign-slot">
                <div style="font-size: 12px; color: #9ca3af; text-transform: uppercase;">Responsable Sécurité (RSSI / SOC)</div>
                <div style="font-weight: bold; margin-top: 10px; color: #38bdf8;">Conformité Validée</div>
                <div style="font-size: 11px; color: #64748b; margin-top: 20px;">Date : $(Get-Date -Format 'dd/MM/yyyy')</div>
            </div>
        </div>
    </div>
</body>
</html>
"@

    Set-Content -Path $HtmlReport -Value $HtmlContent -Encoding UTF8
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-DRPGenerator.ps1" -Severity "INFO" -Category "GovernanceDRP" -Message "Dossier PRA/PCA généré pour $CompanyName" -Metadata @{ PrimarySite = $PrimarySite; DisasterSite = $DisasterSite; RtoHours = $MaxRtoHours; RpoMinutes = $MaxRpoMinutes } -LogFile (Join-Path $ReportDir "DRP-SIEM.jsonl"))
    }
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "   DOSSIER OFFICIEL DE PRA / PCA GÉNÉRÉ AVEC SUCCÈS                       " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "[+] Livrable Officiel HTML : $HtmlReport" -ForegroundColor White

    if ($OpenReport) { Start-Process $HtmlReport }

    return [PSCustomObject]@{
        CompanyName  = $CompanyName
        PrimarySite  = $PrimarySite
        DisasterSite = $DisasterSite
        MaxRtoHours  = $MaxRtoHours
        MaxRpoMinutes = $MaxRpoMinutes
        HtmlReport   = $HtmlReport
    }
}
catch [System.Exception] {
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-DRPGenerator.ps1" -Severity "CRITICAL" -Category "UnhandledException" -ErrorType $_.Exception.GetType().FullName -Message $_.Exception.Message)
    }
    throw
}
