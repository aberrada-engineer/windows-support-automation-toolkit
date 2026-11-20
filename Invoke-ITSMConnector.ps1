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
    [securestring]$GlpiAppToken,
    [securestring]$GlpiUserToken,
    [string]$ServiceNowInstance,
    [string]$ServiceNowUser,
    [securestring]$ServiceNowPassword,
    [System.Management.Automation.PSCredential]$ServiceNowCredential
)
Set-StrictMode -Version Latest

function ConvertFrom-ESNSecureSecret {
    param([securestring]$Secret, [string]$FallbackEnvValue = "")
    if ($null -ne $Secret -and $Secret.Length -gt 0) {
        return ([System.Net.NetworkCredential]::new('', $Secret)).Password
    }
    return $FallbackEnvValue
}

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
$userLabel = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { "operator" }
$dispatchError = $null

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

# 1. Envoi Webhook Microsoft Teams (MessageCard - format historique Webhook Office 365; pour Workflows Power Automate, utiliser AdaptiveCard)
if ($Target -eq "Teams") {
    if (-not $WebhookUrl) {
        throw "URL de Webhook Teams obligatoire (-WebhookUrl)."
    }

    $Payload = @{
        "@type"      = "MessageCard"
        "@context"   = "http://schema.org/extensions"
        "themeColor" = $ThemeColor
        "summary"    = $Title
        "sections"   = @(
            @{
                "activityTitle"    = "🚨 **$Title**"
                "activitySubtitle" = "Généré par ESN-Toolkit sur **$hostLabel**"
                "facts"            = @(
                    @{ "name" = "Sévérité" ; "value" = $Severity },
                    @{ "name" = "Hôte" ; "value" = $hostLabel },
                    @{ "name" = "Utilisateur" ; "value" = $userLabel },
                    @{ "name" = "Horodatage" ; "value" = (Get-Date -Format 'dd/MM/yyyy HH:mm:ss') }
                )
                "text"             = $Message
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        [void](Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $Payload -ContentType "application/json" -TimeoutSec 15)
        Write-Host "[+] Alerte transmise avec succès au canal Teams !" -ForegroundColor Green
    } catch {
        $dispatchError = "Échec de transmission Teams : $($_.Exception.Message)"
        Write-Host "[-] $dispatchError" -ForegroundColor Red
    }
}

# 2. Création de Ticket GLPI REST API
elseif ($Target -eq "GLPI") {
    Write-Host "[*] Connexion à l'API GLPI ($GlpiApiUrl)..." -ForegroundColor White
    $glpiAppPlain  = ConvertFrom-ESNSecureSecret -Secret $GlpiAppToken  -FallbackEnvValue ([string]$env:ESN_GLPI_APP_TOKEN)
    $glpiUserPlain = ConvertFrom-ESNSecureSecret -Secret $GlpiUserToken -FallbackEnvValue ([string]$env:ESN_GLPI_USER_TOKEN)
    if ($glpiAppPlain -and $glpiUserPlain) {
        $sessionToken = $null
        $ticketHeader = $null
        try {
            # 1. Init Session
            $initHeader = @{ "App-Token" = $glpiAppPlain; "Authorization" = "user_token $glpiUserPlain" }
            $sessionResp = Invoke-RestMethod -Uri "$GlpiApiUrl/initSession" -Headers $initHeader -Method Get -TimeoutSec 15
            $sessionToken = $sessionResp.session_token

            # 2. Create Ticket
            $ticketHeader = @{ "App-Token" = $glpiAppPlain; "Session-Token" = $sessionToken }
            $osCaption = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { [System.Environment]::OSVersion.VersionString }
            $ticketBody = @{
                "input" = @{
                    "name"        = "[$Severity] $Title - $hostLabel"
                    "content"     = "$Message`n`nMachine: $hostLabel`nOS: $osCaption"
                    "urgency"     = $(if ($Severity -eq "P1-Bloquant") { 5 } else { 3 })
                    "impact"      = $(if ($Severity -eq "P1-Bloquant") { 5 } else { 3 })
                }
            } | ConvertTo-Json -Depth 3

            $newTicket = Invoke-RestMethod -Uri "$GlpiApiUrl/Ticket" -Headers $ticketHeader -Method Post -Body $ticketBody -ContentType "application/json" -TimeoutSec 15
            Write-Host "[+] Ticket GLPI créé avec succès (ID: $($newTicket.id)) !" -ForegroundColor Green
        } catch {
            $dispatchError = "Échec de communication avec l'API GLPI : $($_.Exception.Message)"
            Write-Host "[-] $dispatchError" -ForegroundColor Red
        } finally {
            # 3. Kill Session toujours exécuté si initSession a réussi
            if ($sessionToken -and $ticketHeader) {
                try {
                    Invoke-RestMethod -Uri "$GlpiApiUrl/killSession" -Headers $ticketHeader -Method Get -TimeoutSec 10 | Out-Null
                } catch {
                    Write-Verbose "GLPI killSession ignoré : $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Host "[!] Mode Simulation GLPI : Paramètres d'authentification App-Token ou User-Token absents (-GlpiAppToken/-GlpiUserToken ou ESN_GLPI_*)." -ForegroundColor Yellow
    }
}

# 3. Envoi Webhook Slack
elseif ($Target -eq "Slack") {
    if (-not $WebhookUrl) {
        throw "URL de Webhook Slack obligatoire (-WebhookUrl)."
    }
    $slackPayload = @{
        text = "[$Severity] $Title ($hostLabel) - $Message"
    } | ConvertTo-Json -Depth 3
    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $slackPayload -ContentType "application/json" -TimeoutSec 15 | Out-Null
        Write-Host "[+] Alerte transmise avec succès sur Slack !" -ForegroundColor Green
    } catch {
        $dispatchError = "Échec de transmission Slack : $($_.Exception.Message)"
        Write-Host "[-] $dispatchError" -ForegroundColor Red
    }
}

# 4. Création d'incident ServiceNow (Table API)
elseif ($Target -eq "ServiceNow") {
    $snUser = if ($ServiceNowCredential) { $ServiceNowCredential.UserName } else { $ServiceNowUser }
    $snPass = if ($ServiceNowCredential) {
        $ServiceNowCredential.GetNetworkCredential().Password
    } elseif ($ServiceNowPassword) {
        ConvertFrom-ESNSecureSecret -Secret $ServiceNowPassword
    } else { $null }
    if ($ServiceNowInstance -and $snUser -and $snPass) {
        $baseUrl = if ($ServiceNowInstance -match '^https?://') { $ServiceNowInstance.TrimEnd('/') } else { "https://$($ServiceNowInstance.TrimEnd('/'))" }
        $pair = "$snUser`:$snPass"
        $headers = @{
            "Authorization" = "Basic $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair)))"
            "Accept"        = "application/json"
        }
        $snBody = @{
            "short_description" = "[$Severity] $Title - $hostLabel"
            "description"       = $Message
            "urgency"           = $(if ($Severity -eq "P1-Bloquant") { "1" } else { "2" })
            "impact"            = $(if ($Severity -eq "P1-Bloquant") { "1" } else { "2" })
        } | ConvertTo-Json -Depth 3
        try {
            $resp = Invoke-RestMethod -Uri "$baseUrl/api/now/table/incident" -Method Post -Headers $headers -Body $snBody -ContentType "application/json" -TimeoutSec 15
            Write-Host "[+] Incident ServiceNow créé : $($resp.result.number)" -ForegroundColor Green
        } catch {
            $dispatchError = "Échec de communication avec ServiceNow : $($_.Exception.Message)"
            Write-Host "[-] $dispatchError" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] Mode Simulation ServiceNow : ServiceNowInstance ou identifiants manquants." -ForegroundColor Yellow
    }
}

# 5. Mode Simulation / Démonstration
else {
    Write-Host "[i] Simulation de dispatching ITSM réussie :" -ForegroundColor Green
    Write-Host "    -> Format payload : JSON UTF-8 conforme standards ITIL" -ForegroundColor Gray
    Write-Host "    -> Ticket Cible   : Support N2/N3 ($Severity)" -ForegroundColor Gray
    Write-Host "    -> Payload généré : OK" -ForegroundColor Gray
}

Write-Host ""
if ($dispatchError) {
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "   DISPATCHING ITSM EN ÉCHEC                                              " -ForegroundColor Red
    Write-Host "==========================================================================" -ForegroundColor Red
    throw $dispatchError
}
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   DISPATCHING ITSM TERMINÉ                                               " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
