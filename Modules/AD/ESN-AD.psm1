#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-AD — Audit Active Directory + actions utilisateur (unlock, reset, audit comptes).
    Fonctionne si le module RSAT ActiveDirectory est installé.
#>

function Test-ADAvailable {
    return ($null -ne (Get-Module -ListAvailable ActiveDirectory -ErrorAction SilentlyContinue))
}

# ─────────────────────────────────────────────────────────────
# AUDIT AD
# ─────────────────────────────────────────────────────────────
function Invoke-ADAudit {
<#
.SYNOPSIS
    Audit rapide de l'Active Directory : DCs, comptes à risque, réplication.
.PARAMETER InactiveDays
    Seuil (jours) pour qualifier un compte d'inactif.
.PARAMETER ExportCsv
    Si précisé, exporte les résultats en CSV dans ce dossier.
#>
    [CmdletBinding()]
    param(
        [int]$InactiveDays = 90,
        [string]$ExportCsv = ""
    )

    if (-not (Test-ADAvailable)) {
        Add-ESNResult "AD" "Module ActiveDirectory" "WARN" "Non installé" "Installer RSAT : Get-WindowsCapability -Online | Where-Object Name -like 'Rsat.ActiveDirectory*' | Add-WindowsCapability -Online"
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    # ── Domaine ──────────────────────────────────────
    try {
        $dom = Get-ADDomain
        Add-ESNResult "AD" "Domaine" "OK" $dom.DNSRoot "NetBIOS : $($dom.NetBIOSName)"
    } catch {
        Add-ESNResult "AD" "Domaine" "ERROR" "Inaccessible" $_.Exception.Message 30
        return
    }

    # ── Domain Controllers ───────────────────────────
    $dcs = Get-ADDomainController -Filter *
    Add-ESNResult "AD" "Domain Controllers" "INFO" "$($dcs.Count) DC(s)" ($dcs.Name -join ', ')

    foreach ($dc in $dcs) {
        $ping = Test-Connection $dc.Name -Count 1 -Quiet -EA SilentlyContinue
        $st   = if ($ping) { "OK" } else { "ERROR" }
        Add-ESNResult "AD" "DC $($dc.Name)" $st $(if($ping){"Joignable"}else{"INJOIGNABLE"}) $dc.Site `
            -ScoreImpact $(if(-not $ping){20}else{0})
    }

    # ── Réplication ──────────────────────────────────
    try {
        $replErrors = repadmin /replsummary 2>&1 | Select-String 'fail'
        if ($replErrors) {
            Add-ESNResult "AD" "Réplication" "ERROR" "Erreurs détectées" ($replErrors -join ' | ') 15
        } else {
            Add-ESNResult "AD" "Réplication" "OK" "Aucune erreur" ""
        }
    } catch {
        Add-ESNResult "AD" "Réplication" "WARN" "repadmin indisponible" ""
    }

    # ── Utilisateurs ─────────────────────────────────
    $allUsers = Get-ADUser -Filter * -Properties Enabled, LockedOut, PasswordExpired,
        PasswordNeverExpires, PasswordLastSet, LastLogonDate, BadLogonCount

    $total      = $allUsers.Count
    $enabled    = ($allUsers | Where-Object Enabled).Count
    $disabled   = $total - $enabled
    $locked     = ($allUsers | Where-Object LockedOut).Count
    $pwdExpired = ($allUsers | Where-Object { $_.PasswordExpired -and $_.Enabled }).Count
    $pwdNever   = ($allUsers | Where-Object { $_.PasswordNeverExpires -and $_.Enabled }).Count

    $cutoff  = (Get-Date).AddDays(-$InactiveDays)
    $inactive = ($allUsers | Where-Object {
        $_.Enabled -and ($_.LastLogonDate -eq $null -or $_.LastLogonDate -lt $cutoff)
    }).Count

    Add-ESNResult "AD" "Utilisateurs total"     "INFO" $total       ""
    Add-ESNResult "AD" "Utilisateurs actifs"    "INFO" $enabled     ""
    Add-ESNResult "AD" "Utilisateurs désactivés""INFO" $disabled    ""
    Add-ESNResult "AD" "Comptes verrouillés"    $(if($locked -gt 0){"WARN"}else{"OK"}) $locked "" `
        -ScoreImpact $(if($locked -gt 5){5}else{0})
    Add-ESNResult "AD" "MDP expirés (actifs)"   $(if($pwdExpired -gt 0){"WARN"}else{"OK"}) $pwdExpired "" `
        -ScoreImpact $(if($pwdExpired -gt 10){5}else{0})
    Add-ESNResult "AD" "MDP sans expiration"    $(if($pwdNever -gt 5){"WARN"}else{"OK"}) $pwdNever "" `
        -ScoreImpact $(if($pwdNever -gt 20){5}else{0})
    Add-ESNResult "AD" "Inactifs +$InactiveDays j" $(if($inactive -gt 20){"WARN"}else{"OK"}) $inactive "" `
        -ScoreImpact $(if($inactive -gt 50){5}else{0})

    # ── Domain Admins ────────────────────────────────
    $da = Get-ADGroupMember 'Domain Admins' -Recursive -EA SilentlyContinue |
          Where-Object objectClass -eq user
    $daSt = if ($da.Count -gt 5) { "WARN" } else { "OK" }
    Add-ESNResult "AD" "Domain Admins" $daSt "$($da.Count) membre(s)" ($da.Name -join ', ') `
        -ScoreImpact $(if($da.Count -gt 10){10}elseif($da.Count -gt 5){5}else{0})

    # ── KRBTGT âge ──────────────────────────────────
    $krb = Get-ADUser krbtgt -Properties PasswordLastSet
    $krbDays = [math]::Round(((Get-Date) - $krb.PasswordLastSet).TotalDays, 0)
    $krbSt   = if ($krbDays -gt 180) { "WARN" } else { "OK" }
    Add-ESNResult "AD" "Compte KRBTGT" $krbSt "MDP changé il y a $krbDays jours" "" `
        -ScoreImpact $(if($krbDays -gt 365){10}elseif($krbDays -gt 180){5}else{0})

    # ── GPO ─────────────────────────────────────────
    try {
        $gpos = Get-GPO -All -EA Stop
        Add-ESNResult "AD" "GPOs" "INFO" "$($gpos.Count) GPO(s)" ""
    } catch {
        Add-ESNResult "AD" "GPOs" "WARN" "Module GroupPolicy non disponible" ""
    }

    # ── Export CSV ──────────────────────────────────
    if ($ExportCsv) {
        New-Item -Path $ExportCsv -ItemType Directory -Force | Out-Null
        $allUsers | Select-Object Name, SamAccountName, Enabled, LockedOut,
            PasswordExpired, PasswordNeverExpires, PasswordLastSet, LastLogonDate, BadLogonCount |
            Export-Csv (Join-Path $ExportCsv "AD_Users_$(Get-Date -Format 'yyyyMMdd').csv") `
                -NoTypeInformation -Encoding UTF8
        Add-ESNResult "AD" "Export CSV" "OK" $ExportCsv ""
    }
}

# ─────────────────────────────────────────────────────────────
# RESET / UNLOCK UTILISATEUR
# ─────────────────────────────────────────────────────────────
function Invoke-ADUserReset {
<#
.SYNOPSIS
    Déverrouille et/ou réinitialise le MDP d'un utilisateur AD.
.PARAMETER Username
    SamAccountName de l'utilisateur.
.PARAMETER NewPassword
    Nouveau mot de passe sécurisé (généré si non fourni).
.PARAMETER UnlockOnly
    Seulement déverrouiller sans changer le MDP.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Username,
        [securestring]$NewPassword = $null,
        [switch]$UnlockOnly,
        [switch]$Simulation
    )

    if (-not (Test-ADAvailable)) {
        Add-ESNResult "AD" "Reset $Username" "ERROR" "Module AD non disponible" ""
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    $user = Get-ADUser -Filter { SamAccountName -eq $Username } `
        -Properties LockedOut, Enabled, PasswordExpired, BadLogonCount,
                    LastLogonDate, EmailAddress, DisplayName -EA SilentlyContinue

    if (-not $user) {
        Add-ESNResult "AD" "Utilisateur $Username" "ERROR" "Introuvable" "" 5
        return
    }

    Add-ESNResult "AD" "Utilisateur trouvé" "OK" $user.DisplayName `
        "Actif:$($user.Enabled) Verrouillé:$($user.LockedOut) MDP expiré:$($user.PasswordExpired)"

    # Déverrouillage
    if ($user.LockedOut) {
        if (-not $Simulation) { Unlock-ADAccount -Identity $Username }
        Add-ESNResult "AD" "Déverrouillage $Username" "OK" $(if($Simulation){"[SIM]"}else{"Déverrouillé"}) ""
    } else {
        Add-ESNResult "AD" "Verrouillage $Username" "OK" "Non verrouillé" "BadLogonCount: $($user.BadLogonCount)"
    }

    if ($UnlockOnly) { return }

    # Génération MDP si non fourni
    $generatedPwd = ""
    if ($null -eq $NewPassword -or $NewPassword.Length -eq 0) {
        $chars   = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$'
        $generatedPwd = -join (1..10 | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })
        $generatedPwd += 'Aa1!'  # garantit complexité
        $secPwd = ([System.Net.NetworkCredential]::new('', $generatedPwd)).SecurePassword
    } else {
        $secPwd = $NewPassword
    }

    if (-not $Simulation) {
        Set-ADAccountPassword -Identity $Username `
            -NewPassword $secPwd -Reset
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $true
    }

    $pwdSummary = if ($generatedPwd) { $generatedPwd } else { "(SecureString fourni)" }
    Add-ESNResult "AD" "Reset MDP $Username" "OK" `
        $(if($Simulation){"[SIM] MDP: $pwdSummary"}else{"MDP réinitialisé — À communiquer : $pwdSummary"}) `
        "Changement requis à la prochaine connexion"

    Write-ESNLog "━━━ INFORMATIONS À TRANSMETTRE À L'UTILISATEUR ━━━" "SECTION"
    Write-ESNLog "Login      : $Username" "OK"
    Write-ESNLog "MDP temp   : $pwdSummary" "WARN"
    Write-ESNLog "Instruction: Changer le MDP à la prochaine connexion" "INFO"
}

# ─────────────────────────────────────────────────────────────
# CRÉATION UTILISATEUR
# ─────────────────────────────────────────────────────────────
function New-ADUserESN {
<#
.SYNOPSIS
    Crée un utilisateur AD avec convention de nommage ESN.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName,
        [Parameter(Mandatory)][string]$Department,
        [string]$Title       = "",
        [string]$Manager     = "",
        [string]$OUPath      = "",
        [string]$Company     = "Ma Société",
        [string]$DomainFQDN  = $env:USERDNSDOMAIN,
        [switch]$Simulation
    )

    if (-not (Test-ADAvailable)) {
        Add-ESNResult "AD" "Création utilisateur" "ERROR" "Module AD non disponible" ""
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    # Nettoyage accent → ASCII
    function Clean([string]$s) {
        $s.ToLower() -replace '[éèêë]','e' -replace '[àâä]','a' -replace '[îï]','i' `
                     -replace '[ôö]','o'   -replace '[ùûü]','u' -replace '[ç]','c' `
                     -replace '[^a-z0-9]',''
    }

    $fnClean = Clean $FirstName
    $lnClean = Clean $LastName
    $sam     = "$($fnClean.Substring(0,1))$lnClean"
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }

    # Gérer doublons
    $base = $sam; $i = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -EA SilentlyContinue) {
        $sam = "$base$i"; $i++
    }

    $upn     = "$sam@$DomainFQDN"
    $display = "$($LastName.ToUpper()) $FirstName"
    $chars   = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$'
    $mdpTemp = (-join (1..10 | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })) + 'Aa1!'

    $ou = if ($OUPath) { $OUPath } else { "CN=Users,$((Get-ADDomain).DistinguishedName)" }

    try {
        if (-not $Simulation) {
            $params = @{
                Name                  = $display
                GivenName             = $FirstName
                Surname               = $LastName
                SamAccountName        = $sam
                UserPrincipalName     = $upn
                DisplayName           = $display
                Department            = $Department
                Title                 = $Title
                Company               = $Company
                AccountPassword       = ([System.Net.NetworkCredential]::new('', $mdpTemp)).SecurePassword
                Enabled               = $true
                ChangePasswordAtLogon = $true
                Path                  = $ou
            }
            if ($Manager) {
                $mgr = Get-ADUser -Filter "SamAccountName -eq '$Manager'" -EA SilentlyContinue
                if ($mgr) { $params.Manager = $mgr.DistinguishedName }
            }
            New-ADUser @params
        }

        Add-ESNResult "AD" "Création utilisateur" "OK" $sam "UPN : $upn"
        Write-ESNLog "━━━ COMPTE CRÉÉ — INFORMATIONS ━━━" "SECTION"
        Write-ESNLog "Display  : $display"  "OK"
        Write-ESNLog "Login    : $sam"       "OK"
        Write-ESNLog "UPN      : $upn"       "OK"
        Write-ESNLog "MDP temp : $mdpTemp"   "WARN"
        if ($Simulation) { Write-ESNLog "[MODE SIMULATION — aucun compte créé]" "WARN" }

        return [PSCustomObject]@{ Sam=$sam; UPN=$upn; Password=$mdpTemp; Display=$display }

    } catch {
        Add-ESNResult "AD" "Création $sam" "ERROR" $_.Exception.Message "" 5
    }
}

Export-ModuleMember -Function @('Invoke-ADAudit','Invoke-ADUserReset','New-ADUserESN','Test-ADAvailable')
