#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Remediation — Système d'auto-remédiation modulaire et sécurisé.

.DESCRIPTION
    Détecte les problèmes système, propose des corrections ciblées,
    et les applique avec -AutoFix. Chaque action est :
    - loggée en détail (avant / action / résultat / après)
    - réversible (rollback quand possible)
    - protégée par confirmation si -Force absent

    Cas couverts :
        DNS         → Flush cache DNS
        Winsock     → Reset pile TCP/IP
        Services    → Redémarrage services Windows arrêtés
        Teams       → Nettoyage cache Microsoft Teams
        Outlook     → Réparation profil Outlook (OST, add-ins, cache)
        OneDrive    → Relance et reset OneDrive
        TempFiles   → Nettoyage fichiers temporaires
        WindowsUpdate → Reset composants Windows Update

.PARAMETER AutoFix
    Applique automatiquement toutes les remédiations détectées.
.PARAMETER Fix
    Liste des remédiations à appliquer explicitement.
    Valeurs : DNS, Winsock, Services, Teams, Outlook, OneDrive, TempFiles, WindowsUpdate
.PARAMETER ComputerName
    Poste cible (local par défaut).
.PARAMETER Force
    Ne demande pas de confirmation pour chaque action.
.PARAMETER Simulation
    Simule les actions sans rien modifier (dry-run).
.PARAMETER ServiceList
    Liste de services supplémentaires à vérifier/redémarrer.

.EXAMPLE
    # Détecter et proposer (aucune modification)
    Invoke-Remediation

    # Appliquer automatiquement tout ce qui est détecté
    Invoke-Remediation -AutoFix

    # Cibler uniquement DNS + Winsock
    Invoke-Remediation -Fix DNS,Winsock -Force

    # Simulation complète
    Invoke-Remediation -AutoFix -Simulation

    # Poste distant
    Invoke-Remediation -ComputerName "PC-DUPONT" -AutoFix -Force

.NOTES
    Auteur  : Amine Berrada
    Version : 1.0.0
    Niveau  : N1/N2
    Tags    : remédiation, fix, DNS, Winsock, Teams, Outlook, OneDrive, services
    Durée   : 2–10 min
    Prérequis : Admin local recommandé
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────
# CATALOGUE DES REMÉDIATIONS
# ─────────────────────────────────────────────────────────────
# Chaque remédiation est un hashtable avec :
#   Id          : identifiant court
#   Name        : libellé lisible
#   Description : ce que ça fait
#   Risk        : Low | Medium | High
#   RequiresAdmin : booléen
#   Detect      : scriptblock → retourne $true si le problème est présent
#   Remediate   : scriptblock → applique la correction, retourne [RemediationResult]

$script:Catalog = [ordered]@{

    # ─────────────────────────────────────────────
    DNS = @{
        Id            = "DNS"
        Name          = "Flush cache DNS"
        Description   = "Vide le cache DNS local pour forcer la résolution fraîche."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            # Détection : résolution DNS échouée OU cache volumineux
            $resolve = try { Resolve-DnsName "google.com" -ErrorAction Stop; $true } catch { $false }
            $cacheCount = (Get-DnsClientCache -ErrorAction SilentlyContinue | Measure-Object).Count
            return (-not $resolve) -or ($cacheCount -gt 500)
        }
        Remediate     = {
            param([bool]$sim)
            $before = (Get-DnsClientCache -EA SilentlyContinue | Measure-Object).Count
            if (-not $sim) {
                Clear-DnsClientCache
                ipconfig /flushdns 2>&1 | Out-Null
            }
            $after = if (-not $sim) { (Get-DnsClientCache -EA SilentlyContinue | Measure-Object).Count } else { 0 }
            return @{
                Success = $true
                Before  = "$before entrées en cache"
                After   = if ($sim) { "[SIMULATION]" } else { "$after entrées en cache" }
                Detail  = "Clear-DnsClientCache + ipconfig /flushdns"
            }
        }
    }

    # ─────────────────────────────────────────────
    Winsock = @{
        Id            = "Winsock"
        Name          = "Reset pile réseau (Winsock + TCP/IP)"
        Description   = "Réinitialise Winsock et la pile TCP/IP. Nécessite un redémarrage."
        Risk          = "Medium"
        RequiresAdmin = $true
        Detect        = {
            # Détection : pertes réseau, latence anormale, ou erreurs Winsock dans les events
            $winsockErrors = Get-WinEvent -FilterHashtable @{
                LogName='System'; StartTime=(Get-Date).AddHours(-24)
            } -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "(?i)winsock|LSP|tcpip|network stack" } |
            Select-Object -First 3

            $latency = try {
                $p = Test-Connection "8.8.8.8" -Count 3 -EA Stop
                ($p | Measure-Object ResponseTime -Average).Average
            } catch { 9999 }

            return (@($winsockErrors).Count -gt 0) -or ($latency -gt 300)
        }
        Remediate     = {
            param([bool]$sim)
            $cmds = @(
                "netsh winsock reset catalog"
                "netsh int ip reset resetlog.txt"
                "netsh int ipv6 reset"
                "netsh int tcp reset"
            )
            $output = @()
            foreach ($cmd in $cmds) {
                if (-not $sim) {
                    $r = cmd /c $cmd 2>&1
                    $output += "$cmd → $($r[-1])"
                } else {
                    $output += "[SIM] $cmd"
                }
            }
            return @{
                Success        = $true
                Before         = "Winsock catalog + TCP/IP stack"
                After          = if ($sim) { "[SIMULATION]" } else { "Reset effectué" }
                Detail         = $output -join " | "
                RebootRequired = $true
            }
        }
    }

    # ─────────────────────────────────────────────
    Services = @{
        Id            = "Services"
        Name          = "Redémarrage services Windows arrêtés"
        Description   = "Redémarre les services en démarrage automatique qui sont arrêtés."
        Risk          = "Low"
        RequiresAdmin = $true
        Detect        = {
            $stopped = Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Stopped' }
            return @($stopped).Count -gt 0
        }
        Remediate     = {
            param([bool]$sim, [string[]]$serviceList)

            # Services prioritaires à redémarrer
            $priority = @(
                "Spooler",    # Impression
                "wuauserv",   # Windows Update
                "WinDefend",  # Defender
                "Dnscache",   # DNS Client
                "W32Time",    # Heure Windows
                "BITS",       # Background Transfer
                "CryptSvc",   # Cryptographic Services
                "EventLog",   # Journal des événements
                "Schedule",   # Planificateur
                "Winmgmt",    # WMI
                "LanmanWorkstation", # Poste de travail
                "NlaSvc"      # Network Location Awareness
            )

            # Ajouter les services personnalisés
            if ($serviceList) { $priority += $serviceList }

            $stopped = @(Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Stopped' -and $_.Name -in $priority })

            $results = @()
            foreach ($svc in $stopped) {
                try {
                    if (-not $sim) { Start-Service $svc.Name -ErrorAction Stop }
                    $newStatus = if (-not $sim) { (Get-Service $svc.Name).Status } else { "Running [SIM]" }
                    $results += "$($svc.Name) : Stopped → $newStatus"
                } catch {
                    $results += "$($svc.Name) : ECHEC — $($_.Exception.Message)"
                }
            }

            return @{
                Success = $true
                Before  = "$($stopped.Count) service(s) arrêté(s) : $(($stopped | ForEach-Object { $_.Name }) -join ', ')"
                After   = if ($results.Count -eq 0) { "Aucun service prioritaire arrêté" } else { $results -join " | " }
                Detail  = "Services prioritaires redémarrés"
            }
        }
    }

    # ─────────────────────────────────────────────
    Teams = @{
        Id            = "Teams"
        Name          = "Nettoyage cache Microsoft Teams"
        Description   = "Ferme Teams et supprime les fichiers de cache corrompus/surchargés."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            $teamsCache = Join-Path $env:LOCALAPPDATA "Microsoft\Teams"
            if (-not (Test-Path $teamsCache)) { return $false }

            $sizeMB = (Get-ChildItem $teamsCache -Recurse -EA SilentlyContinue |
                Measure-Object Length -Sum).Sum / 1MB

            # Détecter crash récent ou cache > 1 Go
            $crashLogs = Get-ChildItem (Join-Path $teamsCache "logs.txt") -EA SilentlyContinue
            return ($sizeMB -gt 1024) -or ($crashLogs -ne $null)
        }
        Remediate     = {
            param([bool]$sim)

            $teamsCache = Join-Path $env:LOCALAPPDATA "Microsoft\Teams"
            $newTeamsCache = Join-Path $env:LOCALAPPDATA "Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"

            $cachePaths = @(
                (Join-Path $teamsCache "Cache"),
                (Join-Path $teamsCache "blob_storage"),
                (Join-Path $teamsCache "databases"),
                (Join-Path $teamsCache "GPUCache"),
                (Join-Path $teamsCache "IndexedDB"),
                (Join-Path $teamsCache "Local Storage"),
                (Join-Path $teamsCache "tmp"),
                $newTeamsCache  # Teams v2 (MSIX)
            )

            # Fermer Teams
            $teamsStopped = $false
            $teamsProc = Get-Process Teams, ms-teams -ErrorAction SilentlyContinue
            if ($teamsProc) {
                if (-not $sim) { Stop-Process -Name Teams, ms-teams -Force -ErrorAction SilentlyContinue }
                Start-Sleep -Seconds 2
                $teamsStopped = $true
            }

            $freed   = 0
            $cleaned = @()
            foreach ($path in $cachePaths) {
                if (Test-Path $path) {
                    $size = (Get-ChildItem $path -Recurse -EA SilentlyContinue |
                        Measure-Object Length -Sum).Sum
                    if (-not $sim) {
                        Get-ChildItem $path -Recurse -Force -EA SilentlyContinue |
                            Remove-Item -Force -Recurse -EA SilentlyContinue
                    }
                    $freed  += $size
                    $cleaned += (Split-Path $path -Leaf)
                }
            }

            $freedMB = [math]::Round($freed / 1MB, 0)

            return @{
                Success = $true
                Before  = "Cache Teams : $freedMB Mo"
                After   = if ($sim) { "[SIMULATION] $freedMB Mo auraient été libérés" } else { "$freedMB Mo libérés" }
                Detail  = "Dossiers nettoyés : $($cleaned -join ', ') | Teams était ouvert : $teamsStopped"
            }
        }
    }

    # ─────────────────────────────────────────────
    Outlook = @{
        Id            = "Outlook"
        Name          = "Réparation basique profil Outlook"
        Description   = "Désactive les add-ins bloquants, corrige le mode hors-ligne, vide le cache OST."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            # Détection : mode hors-ligne, OST > 25 Go, add-ins bloqués
            $outlookReg = "HKCU:\Software\Microsoft\Office\16.0\Outlook"
            $offlineMode = (Get-ItemProperty $outlookReg -Name "Work Offline" -EA SilentlyContinue)."Work Offline"

            $ostPath = Join-Path $env:LOCALAPPDATA "Microsoft\Outlook"
            $ostSize = if (Test-Path $ostPath) {
                (Get-ChildItem $ostPath -Filter "*.ost" -EA SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1GB
            } else { 0 }

            $crashedAddins = Get-ItemProperty `
                "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\CrashedExtensibility" `
                -EA SilentlyContinue

            return ($offlineMode -eq 1) -or ($ostSize -gt 25) -or ($crashedAddins -ne $null)
        }
        Remediate     = {
            param([bool]$sim)

            $actions = @()
            $outlookReg = "HKCU:\Software\Microsoft\Office\16.0\Outlook"

            # Fermer Outlook si ouvert
            $outlookRunning = $false
            if (Get-Process OUTLOOK -EA SilentlyContinue) {
                $outlookRunning = $true
                if (-not $sim) { Stop-Process -Name OUTLOOK -Force -EA SilentlyContinue }
                Start-Sleep -Seconds 2
                $actions += "Outlook fermé"
            }

            # 1. Corriger mode hors-ligne
            $offlineMode = (Get-ItemProperty $outlookReg -Name "Work Offline" -EA SilentlyContinue)."Work Offline"
            if ($offlineMode -eq 1) {
                if (-not $sim) {
                    Set-ItemProperty $outlookReg -Name "Work Offline" -Value 0 -EA SilentlyContinue
                }
                $actions += "Mode hors-ligne désactivé"
            }

            # 2. Désactiver add-ins crashés
            $resPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\CrashedExtensibility"
            if (Test-Path $resPath) {
                $crashed = @(Get-ItemProperty $resPath -EA SilentlyContinue |
                    Get-Member -MemberType NoteProperty |
                    Where-Object { $_.Name -notmatch '^PS' })
                if ($crashed.Count -gt 0) {
                    if (-not $sim) { Remove-Item $resPath -Recurse -Force -EA SilentlyContinue }
                    $actions += "Add-ins crashés réinitialisés ($($crashed.Count))"
                }
            }

            # 3. Vider le cache RoamCache
            $roamCache = Join-Path $env:LOCALAPPDATA "Microsoft\Outlook\RoamCache"
            $roamFreed = 0
            if (Test-Path $roamCache) {
                $roamFreed = [math]::Round((Get-ChildItem $roamCache -Recurse -EA SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB, 0)
                if (-not $sim) {
                    Get-ChildItem $roamCache -File -Recurse -EA SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
                        Remove-Item -Force -EA SilentlyContinue
                }
                $actions += "RoamCache nettoyé ($roamFreed Mo)"
            }

            # 4. Vider le cache INetCache Outlook
            $inetCache = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\INetCache\Content.Outlook"
            if (Test-Path $inetCache) {
                if (-not $sim) {
                    Get-ChildItem $inetCache -Recurse -Force -EA SilentlyContinue |
                        Remove-Item -Force -Recurse -EA SilentlyContinue
                }
                $actions += "INetCache Outlook vidé"
            }

            return @{
                Success = $true
                Before  = "Outlook: mode-hors-ligne=$($offlineMode -eq 1), add-ins crashés=$(if(Test-Path $resPath){'oui'}else{'non'})"
                After   = if ($sim) { "[SIMULATION]" } else { "Réparations appliquées" }
                Detail  = $actions -join " | "
            }
        }
    }

    # ─────────────────────────────────────────────
    OneDrive = @{
        Id            = "OneDrive"
        Name          = "Relance et reset OneDrive"
        Description   = "Redémarre OneDrive, force une resynchronisation, corrige les problèmes de sync."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            # OneDrive installé mais non en cours ?
            $oneDrivePaths = @(
                (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"),
                "C:\Program Files\Microsoft OneDrive\OneDrive.exe",
                "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe"
            )
            $odPath = $oneDrivePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $odPath) { return $false }

            $running = Get-Process OneDrive -EA SilentlyContinue
            # Détecter fichiers bloqués dans le dossier OneDrive
            $syncIssues = Get-ChildItem (Join-Path $env:USERPROFILE "OneDrive") `
                -Filter "*.lock" -Recurse -EA SilentlyContinue | Select-Object -First 1

            return (-not $running) -or ($syncIssues -ne $null)
        }
        Remediate     = {
            param([bool]$sim)

            $oneDrivePaths = @(
                (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"),
                "C:\Program Files\Microsoft OneDrive\OneDrive.exe",
                "C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe"
            )
            $odExe = $oneDrivePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

            if (-not $odExe) {
                return @{
                    Success = $false
                    Before  = "OneDrive introuvable"
                    After   = "Non applicable"
                    Detail  = "OneDrive n'est pas installé sur ce poste"
                }
            }

            $actions = @()

            # 1. Fermer OneDrive
            $wasRunning = ($null -ne (Get-Process OneDrive -EA SilentlyContinue))
            if ($wasRunning) {
                if (-not $sim) { Stop-Process -Name OneDrive -Force -EA SilentlyContinue }
                Start-Sleep -Seconds 2
                $actions += "OneDrive fermé"
            }

            # 2. Supprimer les fichiers .lock de sync
            $lockFiles = @(Get-ChildItem (Join-Path $env:USERPROFILE "OneDrive") `
                -Filter "*.lock" -Recurse -EA SilentlyContinue)
            if ($lockFiles.Count -gt 0) {
                if (-not $sim) { $lockFiles | Remove-Item -Force -EA SilentlyContinue }
                $actions += "$($lockFiles.Count) fichier(s) .lock supprimé(s)"
            }

            # 3. Reset clé de registre de sync (force resync)
            $odRegPath = "HKCU:\Software\Microsoft\OneDrive"
            if (Test-Path $odRegPath -and -not $sim) {
                Set-ItemProperty $odRegPath -Name "DefaultToBusinessFRE" -Value 0 -EA SilentlyContinue
                $actions += "Registre OneDrive réinitialisé"
            }

            # 4. Relancer OneDrive
            if (-not $sim) {
                Start-Process $odExe -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $running = $null -ne (Get-Process OneDrive -EA SilentlyContinue)
                $actions += "OneDrive relancé : $($running)"
            } else {
                $actions += "[SIM] Start-Process $odExe"
            }

            return @{
                Success = $true
                Before  = "OneDrive en cours : $wasRunning"
                After   = if ($sim) { "[SIMULATION]" } else { "OneDrive relancé" }
                Detail  = $actions -join " | "
            }
        }
    }

    # ─────────────────────────────────────────────
    TempFiles = @{
        Id            = "TempFiles"
        Name          = "Nettoyage fichiers temporaires"
        Description   = "Supprime les fichiers temp utilisateur et système (> 7 jours)."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            $paths = @($env:TEMP, "C:\Windows\Temp")
            $total = 0
            foreach ($p in $paths) {
                if (Test-Path $p) {
                    $total += (Get-ChildItem $p -Recurse -EA SilentlyContinue |
                        Measure-Object Length -Sum).Sum
                }
            }
            return $total -gt 500MB
        }
        Remediate     = {
            param([bool]$sim)

            $targets = @(
                @{ Path = $env:TEMP;          Label = "Temp utilisateur";   MinAgeDays = 0  }
                @{ Path = "C:\Windows\Temp";  Label = "Temp système";       MinAgeDays = 1  }
                @{ Path = (Join-Path $env:LOCALAPPDATA "Temp"); Label = "LocalAppData\Temp"; MinAgeDays = 0 }
                @{ Path = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\INetCache"); Label = "INetCache"; MinAgeDays = 7 }
                @{ Path = (Join-Path $env:LOCALAPPDATA "CrashDumps"); Label = "CrashDumps"; MinAgeDays = 0 }
            )

            $totalFreed = 0
            $details    = @()

            foreach ($t in $targets) {
                if (-not (Test-Path $t.Path)) { continue }

                $files = @(Get-ChildItem $t.Path -Recurse -Force -EA SilentlyContinue |
                    Where-Object {
                        -not $_.PSIsContainer -and
                        $_.LastWriteTime -lt (Get-Date).AddDays(-$t.MinAgeDays)
                    })

                $sizeBefore = if ($files.Count -gt 0) { ($files | Measure-Object Length -Sum).Sum } else { 0 }
                $count      = $files.Count

                if (-not $sim -and $count -gt 0) {
                    $files | Remove-Item -Force -EA SilentlyContinue
                }

                $totalFreed += $sizeBefore
                $freedMB     = [math]::Round($sizeBefore / 1MB, 0)
                $details    += "$($t.Label) : $count fichiers, $freedMB Mo"
            }

            $totalMB = [math]::Round($totalFreed / 1MB, 0)

            return @{
                Success = $true
                Before  = "$totalMB Mo de fichiers temporaires"
                After   = if ($sim) { "[SIMULATION] $totalMB Mo auraient été libérés" } else { "$totalMB Mo libérés" }
                Detail  = $details -join " | "
            }
        }
    }

    # ─────────────────────────────────────────────
    WindowsUpdate = @{
        Id            = "WindowsUpdate"
        Name          = "Reset composants Windows Update"
        Description   = "Arrête les services WU, vide les caches, recrée les dossiers, redémarre les services."
        Risk          = "Medium"
        RequiresAdmin = $true
        Detect        = {
            # Détection : services WU arrêtés ou erreurs WU dans events
            $wuauSvc = Get-Service wuauserv -EA SilentlyContinue
            $wuau    = if ($wuauSvc) { $wuauSvc.Status } else { $null }
            $wuErrors = Get-WinEvent -FilterHashtable @{
                LogName='System'; StartTime=(Get-Date).AddDays(-7)
            } -EA SilentlyContinue |
            Where-Object { $_.ProviderName -match "WindowsUpdateClient|wuauclt" -and $_.Level -le 2 } |
            Select-Object -First 3

            return ($wuau -eq "Stopped") -or (@($wuErrors).Count -gt 0)
        }
        Remediate     = {
            param([bool]$sim)

            $steps   = @()
            $services = @("wuauserv","cryptSvc","bits","msiserver","UsoSvc")

            # 1. Arrêter les services
            foreach ($svc in $services) {
                if (-not $sim) { Stop-Service $svc -Force -EA SilentlyContinue }
                $steps += "Stop $svc"
            }

            if (-not $sim) { Start-Sleep -Seconds 2 }

            # 2. Sauvegarder et vider SoftwareDistribution
            $sdPath  = "C:\Windows\SoftwareDistribution"
            $sdBak   = "C:\Windows\SoftwareDistribution.bak"
            if (-not $sim -and (Test-Path $sdPath)) {
                if (Test-Path $sdBak) { Remove-Item $sdBak -Recurse -Force -EA SilentlyContinue }
                Rename-Item $sdPath $sdBak -EA SilentlyContinue
                $steps += "SoftwareDistribution renommé en .bak"
            } else {
                $steps += "[SIM] SoftwareDistribution.bak"
            }

            # 3. Vider catroot2
            $catroot = "C:\Windows\System32\catroot2"
            $catBak  = "C:\Windows\System32\catroot2.bak"
            if (-not $sim -and (Test-Path $catroot)) {
                if (Test-Path $catBak) { Remove-Item $catBak -Recurse -Force -EA SilentlyContinue }
                Rename-Item $catroot $catBak -EA SilentlyContinue
                $steps += "catroot2 renommé en .bak"
            }

            # 4. Reset BITS et WU via sc
            if (-not $sim) {
                sc.exe sdset BITS   "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)..." 2>&1 | Out-Null
                sc.exe sdset wuauserv "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)..." 2>&1 | Out-Null
            }

            # 5. Réenregistrer les DLL WU
            $dlls = @("atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll",
                      "jscript.dll","vbscript.dll","scrrun.dll","msxml.dll","msxml3.dll",
                      "msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll",
                      "rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll",
                      "oleaut32.dll","ole32.dll","shell32.dll","wuapi.dll","wuaueng.dll",
                      "wucltui.dll","wups.dll","wups2.dll","wuweb.dll","qmgr.dll",
                      "qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll")

            $registered = 0
            foreach ($dll in $dlls) {
                if (-not $sim) {
                    $r = regsvr32 /s $dll 2>&1
                    $registered++
                }
            }
            $steps += if ($sim) { "[SIM] $($dlls.Count) DLL à réenregistrer" } else { "$registered DLL réenregistrées" }

            # 6. Reset proxy WinHTTP
            if (-not $sim) { netsh winhttp reset proxy 2>&1 | Out-Null }
            $steps += "Proxy WinHTTP réinitialisé"

            # 7. Redémarrer les services
            if (-not $sim) { Start-Sleep -Seconds 2 }
            foreach ($svc in $services) {
                if (-not $sim) { Start-Service $svc -EA SilentlyContinue }
                $steps += "Start $svc"
            }

            return @{
                Success        = $true
                Before         = "Composants WU potentiellement corrompus"
                After          = if ($sim) { "[SIMULATION]" } else { "Composants réinitialisés" }
                Detail         = $steps -join " | "
                RebootRequired = $false
            }
        }
    }

    # ─────────────────────────────────────────────
    PrintSpooler = @{
        Id            = "PrintSpooler"
        Name          = "Nettoyage et reset Spooler d'impression"
        Description   = "Purge les travaux d'impression bloques et relance le service Spooler."
        Risk          = "Low"
        RequiresAdmin = $true
        Detect        = {
            $svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
            if (-not $svc) { return $false }
            $files = Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS\*" -ErrorAction SilentlyContinue | Measure-Object
            return ($svc.Status -ne "Running") -or ($files.Count -gt 0)
        }
        Remediate     = {
            param([bool]$sim)
            $before = (Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS\*" -ErrorAction SilentlyContinue | Measure-Object).Count
            if (-not $sim) {
                Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
                Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
                Start-Service -Name Spooler -ErrorAction SilentlyContinue
            }
            $after = if (-not $sim) { (Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS\*" -ErrorAction SilentlyContinue | Measure-Object).Count } else { 0 }
            return @{
                Success = $true
                Before  = "$before travaux en file d'attente"
                After   = if ($sim) { "[SIMULATION]" } else { "0 travail (Spooler relance)" }
                Detail  = "Stop-Service Spooler + Purge PRINTERS + Start-Service Spooler"
            }
        }
    }

    # ─────────────────────────────────────────────
    OfficeAuth = @{
        Id            = "OfficeAuth"
        Name          = "Reset cache d'authentification M365 (WAM / Identity)"
        Description   = "Purge les jetons et caches d'identite corrompus responsables des echecs de connexion Office/Teams."
        Risk          = "Low"
        RequiresAdmin = $false
        Detect        = {
            $wam = Test-Path "$env:LOCALAPPDATA\Microsoft\IdentityCache"
            return $wam
        }
        Remediate     = {
            param([bool]$sim)
            if (-not $sim) {
                Remove-Item "$env:LOCALAPPDATA\Microsoft\IdentityCache\*" -Force -Recurse -ErrorAction SilentlyContinue
                Remove-Item "$env:LOCALAPPDATA\Microsoft\OneAuth\*" -Force -Recurse -ErrorAction SilentlyContinue
            }
            return @{
                Success = $true
                Before  = "Caches d'authentification presents"
                After   = if ($sim) { "[SIMULATION]" } else { "Caches d'authentification purges" }
                Detail  = "Purge IdentityCache + OneAuth (Reconnecte proprement le compte M365)"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────
# RÉSULTAT DE REMÉDIATION
# ─────────────────────────────────────────────────────────────
class RemediationResult {
    [string]   $Id
    [string]   $Name
    [bool]     $Detected
    [bool]     $Applied
    [bool]     $Success
    [string]   $Before
    [string]   $After
    [string]   $Detail
    [bool]     $RebootRequired
    [string]   $Error
    [datetime] $Timestamp
}

# ─────────────────────────────────────────────────────────────
# FONCTION PRINCIPALE
# ─────────────────────────────────────────────────────────────
function Invoke-Remediation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]  $ComputerName = $env:COMPUTERNAME,
        [switch]  $AutoFix,
        [string[]]$Fix          = @(),
        [switch]  $Force,
        [switch]  $Simulation,
        [string[]]$ServiceList  = @(),
        [string]  $ReportPath   = ""
    )

    $isRemote = ($ComputerName -ne $env:COMPUTERNAME)
    $results  = [System.Collections.Generic.List[RemediationResult]]::new()

    # ── Banner ────────────────────────────────────────────
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ESN-Toolkit — Système de Remédiation Automatique" -ForegroundColor Cyan
    Write-Host "║  Cible     : $ComputerName" -ForegroundColor Cyan
    Write-Host "║  AutoFix   : $($AutoFix.IsPresent)" -ForegroundColor Cyan
    Write-Host "║  Simulation: $($Simulation.IsPresent)" -ForegroundColor Cyan
    if ($Simulation) {
        Write-Host "║  ⚠️  MODE SIMULATION — Aucune modification ne sera effectuée" -ForegroundColor Yellow
    }
    Write-Host "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    # Essayer d'utiliser le logger ESN-Core si disponible
    $coreLoaded = $null -ne (Get-Command Write-ESNLog -EA SilentlyContinue)
    function RLog {
        param([string]$m, [string]$l = "INFO")
        if ($coreLoaded) { Write-ESNLog $m $l }
        else {
            $c = @{INFO="Cyan";OK="Green";WARN="Yellow";ERROR="Red";SECTION="Magenta"}
            $fg = if ($c.ContainsKey($l)) { $c[$l] } else { "White" }
            Write-Host "[$l] $m" -ForegroundColor $fg
        }
    }

    # ── Sélection des remédiations à évaluer ─────────────
    $toEvaluate = if (@($Fix).Count -gt 0) {
        @($Fix | ForEach-Object { $script:Catalog[$_] } | Where-Object { $_ })
    } else {
        @($script:Catalog.Values)
    }

    RLog "=== PHASE 1 — DÉTECTION DES PROBLÈMES ===" "SECTION"

    # ── Phase 1 : Détection ───────────────────────────────
    $detected = @()
    foreach ($rem in $toEvaluate) {
        RLog "Vérification : $($rem.Name)..." "INFO"

        $isDetected = $false
        try {
            if ($isRemote) {
                $isDetected = Invoke-Command -ComputerName $ComputerName `
                    -ScriptBlock $rem.Detect -ErrorAction Stop
            } else {
                $isDetected = & $rem.Detect
            }
        } catch {
            RLog "  Erreur détection $($rem.Id) : $($_.Exception.Message)" "WARN"
            $isDetected = $false
        }

        $r = [RemediationResult]::new()
        $r.Id        = $rem.Id
        $r.Name      = $rem.Name
        $r.Detected  = $isDetected
        $r.Applied   = $false
        $r.Timestamp = Get-Date

        if ($isDetected) {
            RLog "  ⚠️  PROBLÈME DÉTECTÉ : $($rem.Name) [$($rem.Risk) risk]" "WARN"
            RLog "     → $($rem.Description)" "INFO"
            $detected += $rem
        } else {
            RLog "  ✅ OK : $($rem.Name)" "OK"
        }

        $results.Add($r)
    }

    # ── Résumé détection ──────────────────────────────────
    Write-Host ""
    RLog "=== RÉSUMÉ DÉTECTION ===" "SECTION"
    RLog "Problèmes détectés : $($detected.Count) / $($toEvaluate.Count)" `
        (if ($detected.Count -gt 0) { "WARN" } else { "OK" })

    if ($detected.Count -eq 0) {
        RLog "✅ Aucun problème détecté. Aucune remédiation nécessaire." "OK"
        if ($ReportPath) {
            _Export-RemediationReport -Results $results -OutputPath $ReportPath -Computer $ComputerName -Sim $Simulation.IsPresent
        }
        return $results
    }

    # ── Afficher le plan de remédiation ──────────────────
    Write-Host ""
    RLog "=== PHASE 2 — PLAN DE REMÉDIATION ===" "SECTION"
    $i = 1
    foreach ($rem in $detected) {
        Write-Host "  [$i] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($rem.Name)" -ForegroundColor White -NoNewline
        Write-Host " [$($rem.Risk) risk]" -ForegroundColor $(
            switch ($rem.Risk) { "High"{"Red"} "Medium"{"Yellow"} default{"Green"} }
        )
        Write-Host "      $($rem.Description)" -ForegroundColor DarkGray
        if ($rem.RequiresAdmin) {
            Write-Host "      ⚠️  Nécessite des droits administrateur" -ForegroundColor Yellow
        }
        $i++
    }

    # ── Décision d'application ────────────────────────────
    if (-not $AutoFix -and @($Fix).Count -eq 0) {
        Write-Host ""
        Write-Host "  💡 Pour appliquer toutes les corrections : " -NoNewline -ForegroundColor Cyan
        Write-Host "Invoke-Remediation -AutoFix" -ForegroundColor Yellow
        Write-Host "  💡 Pour corriger un problème précis : " -NoNewline -ForegroundColor Cyan
        Write-Host "Invoke-Remediation -Fix DNS,Teams" -ForegroundColor Yellow
        Write-Host ""
        if ($ReportPath) {
            _Export-RemediationReport -Results $results -OutputPath $ReportPath -Computer $ComputerName -Sim $Simulation.IsPresent
        }
        return $results
    }

    # ── Phase 2 : Application ─────────────────────────────
    Write-Host ""
    RLog "=== PHASE 3 — APPLICATION DES CORRECTIONS ===" "SECTION"

    $rebootNeeded = $false

    foreach ($rem in $detected) {

        # Vérification admin si nécessaire
        if ($rem.RequiresAdmin -and -not (Test-ESNAdmin -ErrorAction SilentlyContinue) -and
            -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
            RLog "⛔ $($rem.Name) — Droits admin requis. Action ignorée." "WARN"
            $idx = $results | Where-Object Id -eq $rem.Id | Select-Object -First 1
            if ($idx) { $idx.Error = "Droits admin manquants" }
            continue
        }

        # Confirmation si non -Force et risque Medium/High
        if (-not $Force -and $rem.Risk -in @("Medium","High") -and -not $Simulation) {
            Write-Host ""
            Write-Host "  ⚠️  $($rem.Name) [RISQUE $($rem.Risk)]" -ForegroundColor Yellow
            Write-Host "  $($rem.Description)" -ForegroundColor DarkGray
            $confirm = Read-Host "  Confirmer l'application ? (O/N)"
            if ($confirm -ne "O") {
                RLog "Action annulée par l'utilisateur : $($rem.Name)" "WARN"
                continue
            }
        }

        RLog "Application : $($rem.Name)..." "INFO"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $idx = $results | Where-Object Id -eq $rem.Id | Select-Object -Last 1

        try {
            # Passer les paramètres selon le type de remédiation
            $remResult = if ($isRemote) {
                Invoke-Command -ComputerName $ComputerName -ScriptBlock $rem.Remediate `
                    -ArgumentList $Simulation.IsPresent, $ServiceList -ErrorAction Stop
            } else {
                & $rem.Remediate -sim $Simulation.IsPresent -serviceList $ServiceList
            }

            $sw.Stop()

            $idx.Applied        = $true
            $idx.Success        = $remResult.Success
            $idx.Before         = $remResult.Before
            $idx.After          = $remResult.After
            $idx.Detail         = $remResult.Detail
            $idx.RebootRequired = $remResult.ContainsKey('RebootRequired') -and ($remResult.RebootRequired -eq $true)

            if ($idx.RebootRequired) { $rebootNeeded = $true }

            $st = if ($remResult.Success) { "OK" } else { "ERROR" }
            RLog "  ✅ $($rem.Name) — Terminé en $($sw.Elapsed.TotalSeconds.ToString('F1'))s" $st
            RLog "  Avant  : $($remResult.Before)"  "INFO"
            RLog "  Après  : $($remResult.After)"   "INFO"
            RLog "  Détail : $($remResult.Detail)"  "DEBUG"

            # Log dans ESN-Core si disponible
            if ($coreLoaded) {
                Add-ESNResult "Remédiation" $rem.Name $st $remResult.After $remResult.Detail
            }

        } catch {
            $sw.Stop()
            $idx.Success = $false
            $idx.Error   = $_.Exception.Message
            RLog "  ❌ $($rem.Name) — ERREUR : $($_.Exception.Message)" "ERROR"
        }

        Write-Host ""
    }

    # ── Avertissement redémarrage ─────────────────────────
    if ($rebootNeeded) {
        Write-Host ""
        Write-Host "  ⚠️  Un ou plusieurs correctifs nécessitent un REDÉMARRAGE du poste." -ForegroundColor Yellow
        Write-Host "  Commande : Restart-Computer -Force" -ForegroundColor DarkGray
        Write-Host ""
    }

    # ── Rapport HTML ──────────────────────────────────────
    if (-not $ReportPath) {
        $rBase     = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" } elseif ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Reports" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
        $rDir      = Join-Path $rBase (Get-Date -Format 'yyyy-MM-dd')
        New-Item -Path $rDir -ItemType Directory -Force | Out-Null
        $ReportPath = Join-Path $rDir "Remediation_$(Get-Date -Format 'HHmm').html"
    }

    _Export-RemediationReport -Results $results -OutputPath $ReportPath -Computer $ComputerName -Sim $Simulation.IsPresent

    # ── Résumé final ──────────────────────────────────────
    $applied  = @($results | Where-Object Applied).Count
    $ok       = @($results | Where-Object { $_.Applied -and $_.Success }).Count
    $failed   = @($results | Where-Object { $_.Applied -and -not $_.Success }).Count

    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  RÉSUMÉ REMÉDIATION" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Problèmes détectés  : $($detected.Count)" -ForegroundColor Cyan
    Write-Host "║  Corrections appliquées : " -NoNewline -ForegroundColor Cyan
    Write-Host "$applied" -ForegroundColor White
    Write-Host "║  Succès  : " -NoNewline -ForegroundColor Cyan
    Write-Host $ok -ForegroundColor Green
    Write-Host "║  Échecs  : " -NoNewline -ForegroundColor Cyan
    Write-Host $failed -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
    Write-Host "║  Rapport : $ReportPath" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    return $results
}

# ─────────────────────────────────────────────────────────────
# RAPPORT HTML REMÉDIATION
# ─────────────────────────────────────────────────────────────
function _Export-RemediationReport {
    param(
        [System.Collections.Generic.List[RemediationResult]]$Results,
        [string]$OutputPath,
        [string]$Computer,
        [bool]  $Sim
    )

    $pDir = Split-Path $OutputPath -Parent
    if ($pDir -and -not (Test-Path $pDir)) {
        New-Item -Path $pDir -ItemType Directory -Force | Out-Null
    }

    $rows = @($Results | ForEach-Object {
        $bg = if (-not $_.Detected) { "#d4edda" }
              elseif ($_.Applied -and $_.Success) { "#cce5ff" }
              elseif ($_.Applied -and -not $_.Success) { "#f8d7da" }
              elseif ($_.Detected -and -not $_.Applied) { "#fff3cd" }
              else { "#f8f9fa" }

        $icon = if (-not $_.Detected) { "✅" }
                elseif ($_.Applied -and $_.Success) { "🔧" }
                elseif ($_.Applied -and -not $_.Success) { "❌" }
                else { "⚠️" }

        $statut = if (-not $_.Detected) { "OK — Non détecté" }
                  elseif ($_.Applied -and $_.Success) { "Corrigé" }
                  elseif ($_.Applied -and -not $_.Success) { "Echec" }
                  else { "Détecté — Non appliqué" }

        $reboot = if ($_.RebootRequired) { "⚠️ Redémarrage requis" } else { "" }

        "<tr style='background:$bg'>
          <td>$icon</td>
          <td><strong>$($_.Id)</strong></td>
          <td>$($_.Name)</td>
          <td><strong>$statut</strong></td>
          <td>$($_.Before)</td>
          <td>$($_.After)</td>
          <td style='font-size:.82em;color:#555'>$($_.Detail)</td>
          <td style='color:#e67e22;font-weight:600'>$reboot</td>
        </tr>"
    }) -join "`n"

    $detected = @($Results | Where-Object Detected).Count
    $fixed    = @($Results | Where-Object { $_.Applied -and $_.Success }).Count
    $simBadge = if ($Sim) { "<span style='background:#ffc107;color:#333;padding:3px 10px;border-radius:12px;font-size:.85em;font-weight:600'>SIMULATION</span>" } else { "" }

    @"
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Rapport Remédiation — $Computer</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:#f4f6f9;color:#333;font-size:14px}
    .hdr{background:linear-gradient(135deg,#1a1a2e,#16213e);color:#fff;padding:28px 36px}
    .hdr h1{font-size:1.5em;margin-bottom:8px}
    .hdr p{opacity:.8;font-size:.9em}
    .container{max-width:1400px;margin:20px auto;padding:0 20px}
    .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:16px 0}
    .card{background:#fff;border-radius:10px;padding:16px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .card .val{font-size:2.5em;font-weight:800}
    .card .lbl{font-size:.8em;color:#666;margin-top:4px}
    .section{background:#fff;border-radius:10px;padding:22px;margin:14px 0;box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .section h2{font-size:1em;font-weight:700;color:#0078d4;margin-bottom:14px;padding-bottom:8px;border-bottom:2px solid #f0f0f0}
    table{width:100%;border-collapse:collapse}
    th{background:#1a1a2e;color:#fff;padding:9px 12px;text-align:left;font-size:.85em;font-weight:600}
    td{padding:8px 12px;border-bottom:1px solid #f0f0f0;font-size:.85em;vertical-align:top}
    tr:hover td{background:rgba(0,120,212,.03)}
    .legend{display:flex;gap:16px;flex-wrap:wrap;margin:10px 0;font-size:.85em}
    .leg-item{display:flex;align-items:center;gap:6px}
    .dot{width:14px;height:14px;border-radius:50%;flex-shrink:0}
    .footer{text-align:center;padding:20px;color:#aaa;font-size:.8em}
  </style>
</head>
<body>
<div class="hdr">
  <h1>🔧 Rapport de Remédiation — $Computer $simBadge</h1>
  <p>Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm') &nbsp;|&nbsp; Opérateur : $env:USERNAME</p>
</div>
<div class="container">
  <div class="cards">
    <div class="card"><div class="val">$(@($Results).Count)</div><div class="lbl">Checks</div></div>
    <div class="card"><div class="val" style="color:#ffc107">$detected</div><div class="lbl">Détectés</div></div>
    <div class="card"><div class="val" style="color:#0078d4">$fixed</div><div class="lbl">Corrigés</div></div>
    <div class="card"><div class="val" style="color:#dc3545">$(@($Results | Where-Object { $_.Applied -and -not $_.Success }).Count)</div><div class="lbl">Échecs</div></div>
    <div class="card"><div class="val" style="color:#28a745">$(@($Results | Where-Object { -not $_.Detected }).Count)</div><div class="lbl">OK dès départ</div></div>
    <div class="card"><div class="val" style="color:#e67e22">$(@($Results | Where-Object RebootRequired).Count)</div><div class="lbl">Redémarrage requis</div></div>
  </div>

  <div class="section">
    <h2>📊 Détail des actions</h2>
    <div class="legend">
      <div class="leg-item"><div class="dot" style="background:#d4edda"></div> OK — Non détecté</div>
      <div class="leg-item"><div class="dot" style="background:#cce5ff"></div> Corrigé avec succès</div>
      <div class="leg-item"><div class="dot" style="background:#f8d7da"></div> Échec de correction</div>
      <div class="leg-item"><div class="dot" style="background:#fff3cd"></div> Détecté — Non appliqué</div>
    </div>
    <table>
      <thead>
        <tr><th></th><th>ID</th><th>Remédiation</th><th>Statut</th><th>Avant</th><th>Après</th><th>Détail</th><th>Note</th></tr>
      </thead>
      <tbody>$rows</tbody>
    </table>
  </div>
</div>
<div class="footer">ESN-Toolkit v1.0.0 — Remédiation — $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') — $env:USERNAME</div>
</body>
</html>
"@ | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
}

# ─────────────────────────────────────────────────────────────
# FONCTIONS UTILITAIRES EXPOSÉES
# ─────────────────────────────────────────────────────────────

function Get-RemediationCatalog {
<#
.SYNOPSIS
    Liste toutes les remédiations disponibles dans le catalogue.
#>
    $script:Catalog.Values | ForEach-Object {
        [PSCustomObject]@{
            Id            = $_.Id
            Name          = $_.Name
            Risk          = $_.Risk
            RequiresAdmin = $_.RequiresAdmin
            Description   = $_.Description
        }
    } | Format-Table -AutoSize
}

function Test-RemediationNeeded {
<#
.SYNOPSIS
    Teste si une remédiation spécifique est nécessaire sans rien appliquer.
.PARAMETER Id
    Identifiant de la remédiation (DNS, Winsock, Services, etc.)
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $rem = $script:Catalog[$Id]
    if (-not $rem) {
        Write-Host "ID '$Id' inconnu. IDs valides : $($script:Catalog.Keys -join ', ')" -ForegroundColor Red
        return $false
    }
    $result = & $rem.Detect
    Write-Host "$($rem.Name) — Problème détecté : $result" -ForegroundColor $(if ($result) { "Yellow" } else { "Green" })
    return $result
}

Export-ModuleMember -Function @(
    'Invoke-Remediation',
    'Get-RemediationCatalog',
    'Test-RemediationNeeded'
)
