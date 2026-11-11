<#
.SYNOPSIS
    New-ArubaSwitchConfig - Générateur Industriel de Configuration de Switches Aruba (~20 Switches).
    Reproduction du projet de déploiement réseau réalisé en autonomie complète par Amine BERRADA.

.DESCRIPTION
    Génère automatiquement les fichiers de configuration prêts à injecter sur les switches Aruba (ArubaOS-CX / ProCurve) :
    1. Paramétrage des VLANs normalisés (Data, VoIP, Wi-Fi, Management)
    2. Configuration des agrégations de liens LACP et Trunks 802.1Q vers le pare-feu / cœur
    3. Durcissement Spanning-Tree (RSTP, BPDU Guard sur ports accès) & Port-Security
    4. Intégration dans la supervision PRTG via SNMP v2c/v3
    5. Export du fichier .cfg prêt pour déploiement sur site
#>

[CmdletBinding()]
param(
    [string]$Hostname = "SW-ETAGE1-01",
    [string]$ManagementIP = "192.168.99.10",
    [string]$SubnetMask = "255.255.255.0",
    [string]$DefaultGateway = "192.168.99.254",
    [string]$VlanData = "10",
    [string]$VlanVoIP = "20",
    [string]$VlanWiFi = "30",
    [string]$VlanMgmt = "99",
    [string]$SNMPCommunity = "PRTG_Monitoring",
    [string]$OutputDir = "C:\ESN-Toolkit\Aruba_Deployments"
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🌐  GENERATEUR DE CONFIGURATION SWITCHES ARUBA (~20 SWITCHES)" -ForegroundColor White
Write-Host "       Projet d'Ingénierie Réseau Réalisé en Autonomie — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Switch : $Hostname | IP Management : $ManagementIP`n" -ForegroundColor Yellow

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$configFile = Join-Path $OutputDir "$Hostname.cfg"

$arubaConfig = @"
; ============================================================================
; CONFIGURATION ARUBAOS-CX / PROCURVE GENEREE AUTOMATIQUEMENT
; Switch : $Hostname
; Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')
; Concu pour integration PRTG & MCO par Amine BERRADA
; ============================================================================

hostname "$Hostname"

; 1. DEFINITION DES VLANS
vlan $VlanData
   name "DATA_UTILISATEURS"
   untagged 1-20
   exit

vlan $VlanVoIP
   name "VOIP_TELEPHONIE"
   tagged 1-20
   qos priority 6
   exit

vlan $VlanWiFi
   name "WIFI_BORNES"
   tagged 21-24
   exit

vlan $VlanMgmt
   name "MANAGEMENT_INFRA"
   ip address $ManagementIP $SubnetMask
   exit

; 2. PASSERELLE PAR DEFAUT
ip default-gateway $DefaultGateway

; 3. LIAISON UPLINK / TRUNK LACP VERS CŒUR DE RESEAU / PARE-FEU
trunk 47-48 trk1 lacp
vlan $VlanData tagged trk1
vlan $VlanVoIP tagged trk1
vlan $VlanWiFi tagged trk1
vlan $VlanMgmt tagged trk1

; 4. SPANNING-TREE RAPIDE & SECURITE ACCES
spanning-tree
spanning-tree priority 8
spanning-tree config-name "CORP-RSTP"
spanning-tree 1-24 bpdu-protection

; 5. SECURITE DES PORTS (PORT-SECURITY)
port-security 1-20 learn-mode limited-continuous address-limit 2 action send-alarm

; 6. GESTION ADMINISTRATIVE & SUPERVISION PRTG (SNMP)
snmp-server community "$SNMPCommunity" operator
snmp-server host $DefaultGateway community "$SNMPCommunity"
snmp-server enable traps

; 7. ACCES DISTANT SECURISE SSH
crypto key generate ssh rsa 2048
ip ssh
no telnet-server
no web-management
web-management ssl

; 8. BANNIERE LEGALE
banner motd "========================================================
ACCES RESERVE AU PERSONNEL AUTORISE - DSI
Tout acces non autorise fera l'objet de poursuites.
========================================================"

write memory
; FIN DE CONFIGURATION
"@

$arubaConfig | Out-File -FilePath $configFile -Encoding ASCII
Write-Host " [OK] Fichier de configuration généré : $configFile" -ForegroundColor Green
Write-Host "      Prêt à être téléversé via console Série / SSH ou TFTP sur le switch physique." -ForegroundColor DarkGray

# RAPPORT DE DEPLOIEMENT DU PARC ARUBA
$reportPath = Join-Path $OutputDir "Fiche-Projet-Switches-Aruba.html"
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Projet Déploiement Réseau Aruba (~20 Switches)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 30px; }
        .card { background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 35px; max-width: 900px; margin: auto; box-shadow: 0 4px 20px rgba(0,0,0,0.06); }
        h1 { color: #ea580c; margin-top: 0; }
        .badge { background: #107c41; color: white; padding: 5px 12px; border-radius: 20px; font-weight: bold; font-size: 13px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #ea580c; color: white; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🌐 Dossier Projet : Déploiement Réseau de ~20 Switches Aruba</h1>
        <p><b>Ingénieur Réseau :</b> Amine BERRADA | <b>Contexte :</b> Modernisation & Refonte d'Infrastructure Commutation</p>
        <span class='badge'>Déploiement Physique & Intégration Supervision PRTG</span>

        <h3>Architecture & Standards Implémentés :</h3>
        <table>
            <thead><tr><th>Composant</th><th>Configuration Standardisée</th><th>Objectif Technique</th></tr></thead>
            <tbody>
                <tr><td><b>VLANs Étanches</b></td><td>Data (10), VoIP (20), Wi-Fi (30), Mgmt (99)</td><td>Cloisonnement des flux et sécurité réseau.</td></tr>
                <tr><td><b>Uplinks LACP</b></td><td>Agrégation de 2 ports 10G/1G (Trunk trk1)</td><td>Haute disponibilité et doublement de la bande passante.</td></tr>
                <tr><td><b>RSTP & BPDU Guard</b></td><td>Spanning-Tree rapide + protection BPDU</td><td>Prévention des boucles réseaux accidentelles par les utilisateurs.</td></tr>
                <tr><td><b>Supervision PRTG</b></td><td>SNMP v2c/v3 + Sondes de trafic par port</td><td>Surveillance 24/7 du MCO et alertes en cas de coupure de port.</td></tr>
            </tbody>
        </table>
    </div>
</body>
</html>
"@
$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host " [OK] Fiche projet générée : $reportPath" -ForegroundColor Green
Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "   PROJET ARUBA NETWORK OPERATIONNEL !" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
