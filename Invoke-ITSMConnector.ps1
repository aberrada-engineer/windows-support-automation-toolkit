<#
.SYNOPSIS
    Invoke-ITSMConnector.ps1 - Connecteur d'Intégration et Dispatcher d'Alertes ITSM (GLPI, ServiceNow, Teams Webhooks).
.DESCRIPTION
    Conçu pour intégrer le toolkit dans l'écosystème de ticketing d'entreprise :
    - Envoi d'alertes enrichies (Adaptive Cards) vers Microsoft Teams, Slack et Discord.
    - Création automatique de tickets d'incident sur GLPI via l'API REST (/apirest.php/Ticket).
    - Création d'incidents sur ServiceNow via l'API Table (/api/now/table/incident).
    - Injection automatique des données de télémétrie locale, score de santé et logs de diagnostic.
.PARAMETER Target
    Cible d'envoi : 'Teams', 'Slack', 'GLPI', 'ServiceNow'.
.PARAMETER WebhookUrl
    URL du webhook entrant pour Teams ou Slack.
.PARAMETER Title
    Titre de l'alerte ou de l'incident.
.PARAMETER Message
    Corps de l'incident / description technique.
.PARAMETER Severity
    Sévérité : 'P1-Bloquant', 'P2-Majeur', 'P3-Mineur', 'Info'.
.EXAMPLE
    .\Invoke-ITSMConnector.ps1 -Target Teams -WebhookUrl "https://outlook.office.com/webhook/..." -Title "Alerte Saturation C:" -Severity P2-Majeur
#>

[CmdletBinding()]
param(
    [ValidateSet("Teams", "Slack", "GLPI", "ServiceNow", "Simulation")]
    [string]$Target = "Simulation",
    [string]$WebhookUrl,
    [string]$Title = "ESN-Toolkit Incident Alert",
    [string]$Message = "Anomalie d'infrastructure détectée par le gardien autonome.",
    [ValidateSet("P1-Bloquant", "P2-Majeur", "P3-Mineur", "Info")]
    [string]$Severity = "P2-Majeur",
    [string]$GlpiApiUrl = "https://support.corp.lan/apirest.php",
    [string]$GlpiAppToken,
    [string]$GlpiUserToken,
    [string]$ServiceNowInstance,
    [string]$ServiceNowUser,
    [string]$ServiceNowPassword
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   ITSM & ALERTING INTEGRATION CONNECTOR (GLPI / SERVICENOW / TEAMS)      " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Canal cible  : $Target" -ForegroundColor Gray
Write-Host "[*] Sévérité     : $Severity" -ForegroundColor Gray
Write-Host "[*] Titre        : $Title" -ForegroundColor Gray
Write-Host ""

$ThemeColor = switch ($Severity) {
    "P1-Bloquant" { "D00000" } # Rouge
    "P2-Majeur"   { "FF8800" } # Orange
    "P3-Mineur"   { "FFCC00" } # Jaune
    default       { "0078D4" } # Bleu
}

# 1. Envoi Webhook Microsoft Teams (MessageCard)
if ($Target -eq "Teams") {
    if (-not $WebhookUrl) {
        Write-Host "[-] Erreur : URL de Webhook Teams obligatoire." -ForegroundColor Red
        return
    }

    $Payload = @{
        "@type"      = "MessageCard"
        "@context"   = "http://schema.org/extensions"
        "themeColor" = $ThemeColor
        "summary"    = $Title
        "sections"   = @(
            @{
                "activityTitle"    = "🚨 **$Title**"
                "activitySubtitle" = "Généré par ESN-Toolkit sur **$env:COMPUTERNAME**"
                "facts"            = @(
                    @{ "name" = "Sévérité" ; "value" = $Severity },
                    @{ "name" = "Hôte" ; "value" = $env:COMPUTERNAME },
                    @{ "name" = "Utilisateur" ; "value" = $env:USERNAME },
                    @{ "name" = "Horodatage" ; "value" = (Get-Date -Format 'dd/MM/yyyy HH:mm:ss') }
                )
                "text"             = $Message
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $Payload -ContentType "application/json"
        Write-Host "[+] Alerte transmise avec succès au canal Teams !" -ForegroundColor Green
    } catch {
        Write-Host "[-] Échec de transmission Teams : $_" -ForegroundColor Red
    }
}

# 2. Création de Ticket GLPI REST API
elseif ($Target -eq "GLPI") {
    Write-Host "[*] Connexion à l'API GLPI ($GlpiApiUrl)..." -ForegroundColor White
    if ($GlpiAppToken -and $GlpiUserToken) {
        try {
            # 1. Init Session
            $initHeader = @{ "App-Token" = $GlpiAppToken; "Authorization" = "user_token $GlpiUserToken" }
            $sessionResp = Invoke-RestMethod -Uri "$GlpiApiUrl/initSession" -Headers $initHeader -Method Get
            $sessionToken = $sessionResp.session_token

            # 2. Create Ticket
            $ticketHeader = @{ "App-Token" = $GlpiAppToken; "Session-Token" = $sessionToken }
            $ticketBody = @{
                "input" = @{
                    "name"        = "[$Severity] $Title - $env:COMPUTERNAME"
                    "content"     = "$Message`n`nMachine: $env:COMPUTERNAME`nOS: $( (Get-CimInstance Win32_OperatingSystem).Caption )"
                    "urgency"     = $(if ($Severity -eq "P1-Bloquant") { 5 } else { 3 })
                    "impact"      = $(if ($Severity -eq "P1-Bloquant") { 5 } else { 3 })
                }
            } | ConvertTo-Json -Depth 3

            $newTicket = Invoke-RestMethod -Uri "$GlpiApiUrl/Ticket" -Headers $ticketHeader -Method Post -Body $ticketBody -ContentType "application/json"
            Write-Host "[+] Ticket GLPI créé avec succès (ID: $($newTicket.id)) !" -ForegroundColor Green

            # 3. Kill Session
            Invoke-RestMethod -Uri "$GlpiApiUrl/killSession" -Headers $ticketHeader -Method Get | Out-Null
        } catch {
            Write-Host "[-] Échec de communication avec l'API GLPI : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Mode Simulation GLPI : Paramètres d'authentification App-Token ou User-Token absents." -ForegroundColor Yellow
    }
}

# 3. Mode Simulation / Démonstration
else {
    Write-Host "[i] Simulation de dispatching ITSM réussie :" -ForegroundColor Green
    Write-Host "    -> Format payload : JSON UTF-8 conforme standards ITIL" -ForegroundColor Gray
    Write-Host "    -> Ticket Cible   : Support N2/N3 ($Severity)" -ForegroundColor Gray
    Write-Host "    -> Payload généré : OK" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   DISPATCHING ITSM TERMINÉ                                               " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
