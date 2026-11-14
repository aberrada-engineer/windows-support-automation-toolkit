#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-M365 — Audit Microsoft 365 : licences, utilisateurs, Exchange,
    MFA, Intune. Utilise Microsoft.Graph.
#>

function Test-GraphAvailable {
    return ($null -ne (Get-Module -ListAvailable Microsoft.Graph.Users -EA SilentlyContinue))
}

function Connect-ESNGraph {
    [CmdletBinding()]
    param([string[]]$Scopes = @('User.Read.All','Directory.Read.All','Reports.Read.All'))

    if (-not (Test-GraphAvailable)) {
        Write-ESNLog "Module Microsoft.Graph non installé. Installer : Install-Module Microsoft.Graph -Scope CurrentUser" "WARN"
        return $false
    }

    try {
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
        Write-ESNLog "Connecté à Microsoft Graph" "OK"
        return $true
    } catch {
        Write-ESNLog "Connexion Graph échouée : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────
# AUDIT M365
# ─────────────────────────────────────────────────────────────
function Invoke-M365Audit {
<#
.SYNOPSIS
    Audit rapide Microsoft 365 : utilisateurs, licences, MFA, invités.
.PARAMETER ExportCsv
    Dossier d'export CSV (optionnel).
.PARAMETER InactiveDays
    Seuil d'inactivité en jours.
#>
    [CmdletBinding()]
    param(
        [string]$ExportCsv    = "",
        [int]$InactiveDays    = 90,
        [switch]$AutoDisconnect
    )

    if (-not (Test-GraphAvailable)) {
        Add-ESNResult "M365" "Module Microsoft.Graph" "WARN" "Non installé" `
            "Install-Module Microsoft.Graph -Scope CurrentUser"
        return
    }

    $connected = Connect-ESNGraph -Scopes @(
        'User.Read.All','Directory.Read.All',
        'AuditLog.Read.All','Reports.Read.All'
    )
    if (-not $connected) {
        Add-ESNResult "M365" "Connexion Graph" "ERROR" "Échec" "" 15
        return
    }

    try {
        # ── Utilisateurs ──────────────────────────────
        Write-ESNLog "Récupération utilisateurs M365..." "INFO"
        $users = Get-MgUser -All -Property `
            DisplayName,UserPrincipalName,AccountEnabled,UserType,
            AssignedLicenses,CreatedDateTime,SignInActivity -ErrorAction Stop |
            Select-Object DisplayName, UserPrincipalName, AccountEnabled, UserType,
                @{N='LicCount';E={ $_.AssignedLicenses.Count }},
                @{N='LastSignIn';E={ $_.SignInActivity.LastSignInDateTime }},
                CreatedDateTime

        $total    = $users.Count
        $enabled  = ($users | Where-Object AccountEnabled).Count
        $disabled = $total - $enabled
        $guests   = ($users | Where-Object UserType -eq 'Guest').Count
        $noLic    = ($users | Where-Object { $_.AccountEnabled -and $_.LicCount -eq 0 -and $_.UserType -eq 'Member' }).Count

        $cutoff  = (Get-Date).AddDays(-$InactiveDays)
        $inactive = ($users | Where-Object {
            $_.AccountEnabled -and $_.UserType -eq 'Member' -and
            ($_.LastSignIn -eq $null -or [datetime]$_.LastSignIn -lt $cutoff)
        }).Count

        Add-ESNResult "M365" "Utilisateurs total"        "INFO" $total   ""
        Add-ESNResult "M365" "Utilisateurs actifs"       "INFO" $enabled ""
        Add-ESNResult "M365" "Utilisateurs désactivés"   "INFO" $disabled ""
        Add-ESNResult "M365" "Comptes invités (Guest)"   $(if($guests -gt 10){"WARN"}else{"INFO"}) $guests "" `
            -ScoreImpact $(if($guests -gt 50){5}else{0})
        Add-ESNResult "M365" "Actifs sans licence"       $(if($noLic -gt 0){"WARN"}else{"OK"}) $noLic "" `
            -ScoreImpact $(if($noLic -gt 5){5}else{0})
        Add-ESNResult "M365" "Inactifs +$InactiveDays j" $(if($inactive -gt 20){"WARN"}else{"OK"}) $inactive "" `
            -ScoreImpact $(if($inactive -gt 50){5}else{0})

        # ── Licences (SKUs) ───────────────────────────
        Write-ESNLog "Récupération licences..." "INFO"
        $skus = Get-MgSubscribedSku -ErrorAction SilentlyContinue
        foreach ($sku in $skus) {
            $achetees  = $sku.PrepaidUnits.Enabled
            $consommees= $sku.ConsumedUnits
            $dispos    = $achetees - $consommees
            $pct       = if ($achetees -gt 0) { [math]::Round($consommees/$achetees*100,1) } else { 0 }
            $skuSt     = if ($dispos -le 0) { "WARN" } elseif ($pct -ge 90) { "WARN" } else { "OK" }
            Add-ESNResult "M365" "Licence $($sku.SkuPartNumber)" $skuSt `
                "$consommees/$achetees utilisées ($dispos dispo)" "$pct% consommé" `
                -ScoreImpact $(if($dispos -le 0){5}else{0})
        }

        # ── MFA (méthodes d'auth) ─────────────────────
        try {
            Write-ESNLog "Vérification MFA..." "INFO"
            $authMethods = Get-MgReportAuthenticationMethodUserRegistrationDetail -All `
                -ErrorAction Stop | Select-Object -First 500

            $mfaRegistered = ($authMethods | Where-Object IsMfaRegistered).Count
            $total2        = $authMethods.Count
            $pctMFA        = if ($total2 -gt 0) { [math]::Round($mfaRegistered/$total2*100,1) } else { 0 }
            $mfaSt         = if ($pctMFA -lt 70) { "ERROR" } elseif ($pctMFA -lt 90) { "WARN" } else { "OK" }
            Add-ESNResult "M365" "MFA enregistré" $mfaSt "$mfaRegistered/$total2 utilisateurs ($pctMFA%)" "" `
                -ScoreImpact $(if($mfaSt -eq "ERROR"){15}elseif($mfaSt -eq "WARN"){8}else{0})
        } catch {
            Add-ESNResult "M365" "MFA" "WARN" "Rapport non accessible" "Scope Reports.Read.All requis"
        }

        # ── Export CSV ────────────────────────────────
        if ($ExportCsv) {
            New-Item -Path $ExportCsv -ItemType Directory -Force | Out-Null
            $users | Export-Csv (Join-Path $ExportCsv "M365_Users_$(Get-Date -Format 'yyyyMMdd').csv") `
                -NoTypeInformation -Encoding UTF8
            Add-ESNResult "M365" "Export CSV" "OK" $ExportCsv ""
        }

    } catch {
        Add-ESNResult "M365" "Audit M365" "ERROR" $_.Exception.Message "" 10
    } finally {
        if ($AutoDisconnect) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    }
}

# ─────────────────────────────────────────────────────────────
# GÉRER LICENCE UTILISATEUR
# ─────────────────────────────────────────────────────────────
function Set-M365UserLicense {
<#
.SYNOPSIS
    Assigne ou retire une licence M365 à un utilisateur.
.PARAMETER UserUPN
    UPN de l'utilisateur.
.PARAMETER Action
    Assign ou Remove.
.PARAMETER SkuPartNumber
    Numéro de SKU (ex: ENTERPRISEPACK, SPB). Laissez vide pour voir les disponibles.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserUPN,
        [ValidateSet("Assign","Remove")][string]$Action = "Assign",
        [string]$SkuPartNumber = "",
        [switch]$Simulation
    )

    if (-not (Test-GraphAvailable)) {
        Add-ESNResult "M365" "Licence $UserUPN" "ERROR" "Module Graph non disponible" ""
        return
    }

    $connected = Connect-ESNGraph -Scopes @('User.ReadWrite.All','Directory.ReadWrite.All')
    if (-not $connected) { return }

    # Lister les SKUs disponibles si non précisé
    $skus = Get-MgSubscribedSku
    if (-not $SkuPartNumber) {
        Write-ESNLog "Licences disponibles :" "INFO"
        $skus | ForEach-Object {
            Write-ESNLog "  $($_.SkuPartNumber) — $($_.PrepaidUnits.Enabled - $_.ConsumedUnits) dispo" "INFO"
        }
        $SkuPartNumber = Read-Host "Entrez le SkuPartNumber"
    }

    $sku = $skus | Where-Object SkuPartNumber -eq $SkuPartNumber | Select-Object -First 1
    if (-not $sku) {
        Add-ESNResult "M365" "SKU $SkuPartNumber" "ERROR" "Introuvable" ""
        return
    }

    try {
        $user = Get-MgUser -UserId $UserUPN -ErrorAction Stop
        if (-not $Simulation) {
            if ($Action -eq "Assign") {
                Set-MgUserLicense -UserId $user.Id `
                    -AddLicenses @{ SkuId = $sku.SkuId } -RemoveLicenses @()
            } else {
                Set-MgUserLicense -UserId $user.Id `
                    -AddLicenses @() -RemoveLicenses @($sku.SkuId)
            }
        }
        Add-ESNResult "M365" "Licence $Action $UserUPN" "OK" `
            $(if($Simulation){"[SIM] $SkuPartNumber"}else{$SkuPartNumber}) ""
    } catch {
        Add-ESNResult "M365" "Licence $Action $UserUPN" "ERROR" $_.Exception.Message "" 5
    }
}

Export-ModuleMember -Function @(
    'Invoke-M365Audit','Set-M365UserLicense',
    'Connect-ESNGraph','Test-GraphAvailable'
)
