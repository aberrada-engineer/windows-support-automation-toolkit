#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-AD — Audit Active Directory + actions utilisateur (unlock, reset, audit comptes).
    Fonctionne si le module RSAT ActiveDirectory est installé.
#>

Set-StrictMode -Version Latest

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
    $dcs = @(Get-ADDomainController -Filter *)
    $dcNames = @($dcs | ForEach-Object { $_.Name }) -join ', '
    Add-ESNResult "AD" "Domain Controllers" "INFO" "$($dcs.Count) DC(s)" $dcNames

    foreach ($dc in $dcs) {
        $ping = Test-Connection $dc.Name -Count 1 -Quiet -EA SilentlyContinue
        $st   = if ($ping) { "OK" } else { "ERROR" }
        Add-ESNResult "AD" "DC $($dc.Name)" $st $(if($ping){"Joignable"}else{"INJOIGNABLE"}) $dc.Site `
            -ScoreImpact $(if(-not $ping){20}else{0})
    }

    # ── Réplication ──────────────────────────────────
    if (Get-Command Get-ADReplicationFailure -ErrorAction SilentlyContinue) {
        try {
            $replFails = @(Get-ADReplicationFailure -Target $env:USERDNSDOMAIN -Scope Domain -ErrorAction Stop)
            if ($replFails.Count -gt 0) {
                $detail = ($replFails | ForEach-Object { "$($_.Server):$($_.FailureType)(err $($_.LastError))" }) -join ' | '
                Add-ESNResult "AD" "Réplication" "ERROR" "$($replFails.Count) erreur(s)" $detail 15
            } else {
                Add-ESNResult "AD" "Réplication" "OK" "Aucune erreur (Get-ADReplicationFailure)" ""
            }
        } catch {
            Add-ESNResult "AD" "Réplication" "WARN" "Contrôle réplication impossible" $_.Exception.Message
        }
    } elseif (Get-Command repadmin -ErrorAction SilentlyContinue) {
        $replOut = (& repadmin /replsummary 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $replOut -match '(?i)\b(fail|fails|failure|erreur|échec)\b') {
            Add-ESNResult "AD" "Réplication" "ERROR" "Erreurs détectées" ($replOut -replace '\s+', ' ').Trim() 15
        } else {
            Add-ESNResult "AD" "Réplication" "OK" "Aucune erreur" ""
        }
    } else {
        Add-ESNResult "AD" "Réplication" "WARN" "repadmin/AD indisponible" ""
    }

    # ── Utilisateurs ─────────────────────────────────
    $allUsers = @(Get-ADUser -Filter * -Properties Enabled, LockedOut, PasswordExpired,
        PasswordNeverExpires, PasswordLastSet, LastLogonDate, BadLogonCount)

    $total      = $allUsers.Count
    $enabled    = @($allUsers | Where-Object Enabled).Count
    $disabled   = $total - $enabled
    $locked     = @($allUsers | Where-Object LockedOut).Count
    $pwdExpired = @($allUsers | Where-Object { $_.PasswordExpired -and $_.Enabled }).Count
    $pwdNever   = @($allUsers | Where-Object { $_.PasswordNeverExpires -and $_.Enabled }).Count

    $cutoff  = (Get-Date).AddDays(-$InactiveDays)
    $inactive = @($allUsers | Where-Object {
        $_.Enabled -and ($null -eq $_.LastLogonDate -or $_.LastLogonDate -lt $cutoff)
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

    # ── Domain Admins (SID *-512 agnostique FR/EN) ──
    $daTarget = if ($dom -and $dom.DomainSID) { "$($dom.DomainSID.Value)-512" } else { 'Domain Admins' }
    $da = @(Get-ADGroupMember $daTarget -Recursive -EA SilentlyContinue |
          Where-Object objectClass -eq user)
    if ($da.Count -eq 0 -and $daTarget -eq 'Domain Admins') {
        $da = @(Get-ADGroupMember 'Admins du domaine' -Recursive -EA SilentlyContinue |
              Where-Object objectClass -eq user)
    }
    $daSt = if ($da.Count -gt 5) { "WARN" } else { "OK" }
    $daNames = @($da | ForEach-Object { $_.Name }) -join ', '
    Add-ESNResult "AD" "Domain Admins" $daSt "$($da.Count) membre(s)" $daNames `
        -ScoreImpact $(if($da.Count -gt 10){10}elseif($da.Count -gt 5){5}else{0})

    # ── KRBTGT âge ──────────────────────────────────
    $krb = Get-ADUser krbtgt -Properties PasswordLastSet -EA SilentlyContinue
    if ($krb -and $krb.PasswordLastSet) {
        $krbDays = [math]::Round(((Get-Date) - $krb.PasswordLastSet).TotalDays, 0)
        $krbSt   = if ($krbDays -gt 180) { "WARN" } else { "OK" }
        Add-ESNResult "AD" "Compte KRBTGT" $krbSt "MDP changé il y a $krbDays jours" "" `
            -ScoreImpact $(if($krbDays -gt 365){10}elseif($krbDays -gt 180){5}else{0})
    }

    # ── GPO ─────────────────────────────────────────
    try {
        $gpos = @(Get-GPO -All -EA Stop)
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
# HELPER CSPRNG — Génération mot de passe temporaire robuste
# ─────────────────────────────────────────────────────────────
function New-ESNRandomPassword {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([int]$Length = 16)
    if ($Length -lt 8) { $Length = 8 }
    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghijkmnpqrstuvwxyz"
    $digits = "23456789"
    $special = "!@#$%^&*-_=+"
    $all = $upper + $lower + $digits + $special
    $bytes = New-Object byte[] ($Length * 2)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $chars = [System.Collections.Generic.List[char]]::new()
    $chars.Add($upper[$bytes[0] % $upper.Length])
    $chars.Add($lower[$bytes[1] % $lower.Length])
    $chars.Add($digits[$bytes[2] % $digits.Length])
    $chars.Add($special[$bytes[3] % $special.Length])
    for ($i = 4; $i -lt $Length; $i++) {
        $chars.Add($all[$bytes[$i] % $all.Length])
    }
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = $bytes[$Length + ($i % $Length)] % ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    return (-join $chars)
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
        if (-not $Simulation -and $PSCmdlet.ShouldProcess($Username, "Unlock-ADAccount")) {
            Unlock-ADAccount -Identity $Username
        }
        Add-ESNResult "AD" "Déverrouillage $Username" "OK" $(if($Simulation){"[SIM]"}else{"Déverrouillé"}) ""
    } else {
        Add-ESNResult "AD" "Verrouillage $Username" "OK" "Non verrouillé" "BadLogonCount: $($user.BadLogonCount)"
    }

    if ($UnlockOnly) { return }

    # Génération MDP CSPRNG si non fourni
    $generatedPwd = ""
    if ($null -eq $NewPassword -or $NewPassword.Length -eq 0) {
        $generatedPwd = New-ESNRandomPassword -Length 16
        $secPwd = ([System.Net.NetworkCredential]::new('', $generatedPwd)).SecurePassword
    } else {
        $secPwd = $NewPassword
    }

    if (-not $Simulation -and $PSCmdlet.ShouldProcess($Username, "Set-ADAccountPassword")) {
        Set-ADAccountPassword -Identity $Username `
            -NewPassword $secPwd -Reset
        Set-ADUser -Identity $Username -ChangePasswordAtLogon $true
    }

    Add-ESNResult "AD" "Reset MDP $Username" "OK" `
        $(if($Simulation){"[SIM] MDP généré (masqué)"}else{"MDP réinitialisé (masqué dans le rapport)"}) `
        "Changement requis à la prochaine connexion"

    Write-ESNLog "━━━ INFORMATIONS À TRANSMETTRE À L'UTILISATEUR ━━━" "SECTION"
    Write-ESNLog "Login      : $Username" "OK"
    Write-ESNLog "MDP temp   : [MASQUÉ DANS LES JOURNAUX — Voir retour console/objet]" "INFO"
    Write-ESNLog "Instruction: Changer le MDP à la prochaine connexion" "INFO"
    return [PSCustomObject]@{ Username = $Username; TemporaryPassword = $generatedPwd; Simulation = [bool]$Simulation }
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
    function Clean {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
        param([string]$s)
        $s.ToLower() -replace '[éèêë]','e' -replace '[àâä]','a' -replace '[îï]','i' `
                     -replace '[ôö]','o'   -replace '[ùûü]','u' -replace '[ç]','c' `
                     -replace '[^a-z0-9]',''
    }

    $fnClean = Clean $FirstName
    $lnClean = Clean $LastName
    if (-not $fnClean) { $fnClean = "x" }
    if (-not $lnClean) { $lnClean = "user" }
    $sam     = "$($fnClean.Substring(0,1))$lnClean"
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }

    # Gérer doublons dans la limite AD de 20 caractères
    $base = $sam; $i = 1
    while (Get-ADUser -Filter { SamAccountName -eq $sam } -EA SilentlyContinue) {
        $sfx = "$i"
        $maxBase = 20 - $sfx.Length
        $trimBase = if ($base.Length -gt $maxBase) { $base.Substring(0, $maxBase) } else { $base }
        $sam = "$trimBase$sfx"; $i++
    }

    $upn     = "$sam@$DomainFQDN"
    $display = "$($LastName.ToUpper()) $FirstName"
    $mdpTemp = New-ESNRandomPassword -Length 16

    $ou = if ($OUPath) { $OUPath } else { "CN=Users,$((Get-ADDomain).DistinguishedName)" }

    try {
        if (-not $Simulation -and $PSCmdlet.ShouldProcess($upn, "New-ADUser")) {
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
                $mgr = Get-ADUser -Filter { SamAccountName -eq $Manager } -EA SilentlyContinue
                if ($mgr) { $params.Manager = $mgr.DistinguishedName }
            }
            New-ADUser @params
        }

        Add-ESNResult "AD" "Création utilisateur" "OK" $sam "UPN : $upn"
        Write-ESNLog "━━━ COMPTE CRÉÉ — INFORMATIONS ━━━" "SECTION"
        Write-ESNLog "Display  : $display"  "OK"
        Write-ESNLog "Login    : $sam"       "OK"
        Write-ESNLog "UPN      : $upn"       "OK"
        Write-ESNLog "MDP temp : [MASQUÉ DANS LES JOURNAUX]" "INFO"
        if ($Simulation) { Write-ESNLog "[MODE SIMULATION — aucun compte créé]" "WARN" }

        return [PSCustomObject]@{ Sam=$sam; UPN=$upn; Password=$mdpTemp; Display=$display }

    } catch {
        Add-ESNResult "AD" "Création $sam" "ERROR" $_.Exception.Message "" 5
    }
}

Export-ModuleMember -Function @('Invoke-ADAudit','Invoke-ADUserReset','New-ADUserESN','New-ESNRandomPassword','Test-ADAvailable')
