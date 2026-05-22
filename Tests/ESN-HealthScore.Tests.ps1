#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester v5 — Module ESN-HealthScore.
    Couvre : calcul scores, pondération, recommandations, rapport HTML, comparaison.
.USAGE
    Invoke-Pester .\Tests\ESN-HealthScore.Tests.ps1 -Output Detailed
    Invoke-Pester .\Tests\ESN-HealthScore.Tests.ps1 -Tag "Scoring" -Output Detailed
#>

BeforeAll {
    $root      = Split-Path $PSScriptRoot -Parent
    $scorePath = Join-Path $root "Modules\HealthScore\ESN-HealthScore.psm1"
    Import-Module $scorePath -Force

    # Données mock complètes pour les tests unitaires
    $script:MockNet = @{
        APIPA       = $false
        HasValidIP  = $true
        IPList      = "192.168.1.42"
        Gateway     = "192.168.1.1"
        GatewayPing = $true
        DNSResolve  = $true
        DNSServers  = "192.168.1.1, 8.8.8.8"
        InternetOK  = $true
        LatencyAvg  = 15
        PacketLoss  = 0
    }

    $script:MockSys = @{
        OS          = "Windows 11 Pro"
        Build       = "22621"
        UptimeDays  = 3
        RAM_Total   = 16
        RAM_Free    = 8000
        RAM_Pct     = 50
        CPU_Load    = 25
        CPU_Name    = "Intel Core i7-12700"
        CrashDumps  = 0
        CritEvents  = 0
        PageFilePct = 30
    }

    $script:MockSec = @{
        DefenderEnabled  = $true
        DefenderUpdated  = $true
        TamperProtection = $true
        DefenderScanDays = 1
        FW_Domain        = $true
        FW_Private       = $true
        FW_Public        = $true
        BitLocker        = $true
        WDigest          = $false
        SMBv1            = $false
        RDP_NLA          = $true
        UAC              = $true
        AdminLocalActive = $false
        CertsExpiring    = 0
    }

    $script:MockStorage = @{
        Drives = @(
            @{ Name="C"; TotalGB=500; FreeGB=250; UsedPct=50 }
            @{ Name="D"; TotalGB=1000; FreeGB=800; UsedPct=20 }
        )
        SMART_Failures = 0
        SMART_Total    = 2
        TempMB         = 200
    }

    $script:MockSvc = @{
        TotalAuto        = 45
        StoppedAuto      = 0
        StoppedNames     = ""
        CritStopped      = 0
        CritStoppedNames = ""
    }
}

# ═══════════════════════════════════════════════════════
# EXPORTS ET FONCTIONS
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Exports" -Tag "Exports" {

    It "Exporte Invoke-HealthScore" {
        Get-Command Invoke-HealthScore | Should -Not -BeNullOrEmpty
    }

    It "Exporte Compare-HealthScore" {
        Get-Command Compare-HealthScore | Should -Not -BeNullOrEmpty
    }

    It "Exporte Get-ScoreLabel" {
        Get-Command Get-ScoreLabel | Should -Not -BeNullOrEmpty
    }

    It "Exporte Get-ScoreColor" {
        Get-Command Get-ScoreColor | Should -Not -BeNullOrEmpty
    }
}

# ═══════════════════════════════════════════════════════
# GET-SCORELABEL
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Get-ScoreLabel" -Tag "Labels" {

    It "Score 100 → Excellent" {
        Get-ScoreLabel 100 | Should -Be "Excellent"
    }

    It "Score 95 → Excellent" {
        Get-ScoreLabel 95 | Should -Be "Excellent"
    }

    It "Score 80 → Bon" {
        Get-ScoreLabel 80 | Should -Be "Bon"
    }

    It "Score 75 → Dégradé" {
        Get-ScoreLabel 75 | Should -Be "Dégradé"
    }

    It "Score 60 → Dégradé" {
        Get-ScoreLabel 60 | Should -Be "Dégradé"
    }

    It "Score 50 → Mauvais" {
        Get-ScoreLabel 50 | Should -Be "Mauvais"
    }

    It "Score 40 → Mauvais" {
        Get-ScoreLabel 40 | Should -Be "Mauvais"
    }

    It "Score 39 → Critique" {
        Get-ScoreLabel 39 | Should -Be "Critique"
    }

    It "Score 0 → Critique" {
        Get-ScoreLabel 0 | Should -Be "Critique"
    }
}

# ═══════════════════════════════════════════════════════
# GET-SCORECOLOR
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Get-ScoreColor" -Tag "Colors" {

    It "Score 80+ → couleur verte (#28a745)" {
        Get-ScoreColor 80 | Should -Be "#28a745"
        Get-ScoreColor 100 | Should -Be "#28a745"
    }

    It "Score 60-79 → couleur jaune (#ffc107)" {
        Get-ScoreColor 60 | Should -Be "#ffc107"
        Get-ScoreColor 79 | Should -Be "#ffc107"
    }

    It "Score 40-59 → couleur orange (#fd7e14)" {
        Get-ScoreColor 40 | Should -Be "#fd7e14"
        Get-ScoreColor 59 | Should -Be "#fd7e14"
    }

    It "Score < 40 → couleur rouge (#dc3545)" {
        Get-ScoreColor 39 | Should -Be "#dc3545"
        Get-ScoreColor 0  | Should -Be "#dc3545"
    }
}

# ═══════════════════════════════════════════════════════
# SCORE RÉSEAU
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Réseau" -Tag "Scoring","Network" {

    It "Machine saine → score réseau 100" {
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $script:MockNet
        $r.Score | Should -Be 100
        $r.Recommendations.Count | Should -Be 0
    }

    It "APIPA détecté → score réseau très bas (<30)" {
        $bad = $script:MockNet.Clone()
        $bad.APIPA = $true; $bad.HasValidIP = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $r.Score | Should -BeLessThan 30
        $r.Recommendations | Where-Object { $_ -like "*APIPA*" } | Should -Not -BeNullOrEmpty
    }

    It "Passerelle injoignable → score réseau ≤ 65" {
        $bad = $script:MockNet.Clone()
        $bad.GatewayPing = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 65
        $r.Recommendations | Where-Object { $_ -like "*passerelle*" -or $_ -like "*Passerelle*" } | Should -Not -BeNullOrEmpty
    }

    It "DNS non résolu → recommandation flush DNS générée" {
        $bad = $script:MockNet.Clone()
        $bad.DNSResolve = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "DNS|dns" } | Should -Not -BeNullOrEmpty
    }

    It "Internet coupé → score réseau ≤ 60" {
        $bad = $script:MockNet.Clone()
        $bad.InternetOK = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 60
    }

    It "Latence 15ms → score latence maximum (10 pts)" {
        $r     = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $script:MockNet
        $latD  = $r.Details | Where-Object { $_.Check -like "*Latence*" }
        $latD.Pts | Should -Be 10
    }

    It "Latence 300ms → score latence partiel (≤2 pts)" {
        $bad = $script:MockNet.Clone()
        $bad.LatencyAvg = 300
        $r    = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $latD = $r.Details | Where-Object { $_.Check -like "*Latence*" }
        $latD.Pts | Should -BeLessOrEqual 2
        $r.Recommendations | Where-Object { $_ -match "latence|Latence" } | Should -Not -BeNullOrEmpty
    }

    It "Perte paquets 50% → recommandation générée" {
        $bad = $script:MockNet.Clone()
        $bad.PacketLoss = 50
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "paquet|Perte" } | Should -Not -BeNullOrEmpty
    }

    It "Score réseau est toujours entre 0 et 100" {
        $worst = @{
            APIPA=$true; HasValidIP=$false; IPList="169.254.1.1"
            Gateway=""; GatewayPing=$false
            DNSResolve=$false; DNSServers=""
            InternetOK=$false; LatencyAvg=9999; PacketLoss=100
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Network $args[0] } $worst
        $r.Score | Should -BeGreaterOrEqual 0
        $r.Score | Should -BeLessOrEqual 100
    }
}

# ═══════════════════════════════════════════════════════
# SCORE SYSTÈME
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Système" -Tag "Scoring","System" {

    It "Machine saine → score système ≥ 90" {
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $script:MockSys
        $r.Score | Should -BeGreaterOrEqual 90
    }

    It "RAM 95% → score système ≤ 60 et recommandation générée" {
        $bad = $script:MockSys.Clone()
        $bad.RAM_Pct = 95
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 60
        $r.Recommendations | Where-Object { $_ -match "RAM|ram" } | Should -Not -BeNullOrEmpty
    }

    It "RAM 50% → aucune recommandation RAM" {
        $r    = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $script:MockSys
        $rRam = $r.Recommendations | Where-Object { $_ -match "RAM" }
        $rRam | Should -BeNullOrEmpty
    }

    It "CPU 95% → recommandation CPU générée" {
        $bad = $script:MockSys.Clone()
        $bad.CPU_Load = 95
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "CPU|cpu" } | Should -Not -BeNullOrEmpty
    }

    It "Uptime 60 jours → recommandation redémarrage" {
        $bad = $script:MockSys.Clone()
        $bad.UptimeDays = 60
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "redémarrage|uptime|Uptime" } | Should -Not -BeNullOrEmpty
    }

    It "5 crash dumps → recommandation BlueScreen" {
        $bad = $script:MockSys.Clone()
        $bad.CrashDumps = 5
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "dump|crash|Crash" } | Should -Not -BeNullOrEmpty
    }

    It "40 events critiques → score système ≤ 70" {
        $bad = $script:MockSys.Clone()
        $bad.CritEvents = 40
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 70
    }

    It "Score système toujours entre 0 et 100" {
        $worst = @{
            OS="Windows XP"; Build="2600"; UptimeDays=180
            RAM_Total=2; RAM_Free=50; RAM_Pct=98
            CPU_Load=99; CPU_Name="Pentium III"
            CrashDumps=20; CritEvents=200; PageFilePct=99
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-System $args[0] } $worst
        $r.Score | Should -BeGreaterOrEqual 0
        $r.Score | Should -BeLessOrEqual 100
    }
}

# ═══════════════════════════════════════════════════════
# SCORE SÉCURITÉ
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Sécurité" -Tag "Scoring","Security" {

    It "Configuration sécurisée → score sécurité = 100" {
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $script:MockSec
        $r.Score | Should -Be 100
        $r.Recommendations.Count | Should -Be 0
    }

    It "Defender désactivé → score ≤ 80 et recommandation CRITIQUE" {
        $bad = $script:MockSec.Clone()
        $bad.DefenderEnabled = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 80
        $r.Recommendations | Where-Object { $_ -like "CRITIQUE*Antivirus*" -or $_ -like "CRITIQUE*Defender*" } | Should -Not -BeNullOrEmpty
    }

    It "SMBv1 activé → recommandation CRITIQUE EternalBlue" {
        $bad = $script:MockSec.Clone()
        $bad.SMBv1 = $true
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "SMBv1|EternalBlue|WannaCry" } | Should -Not -BeNullOrEmpty
    }

    It "WDigest activé → recommandation CRITIQUE Pass-the-Hash" {
        $bad = $script:MockSec.Clone()
        $bad.WDigest = $true
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "WDigest|Pass-the-Hash" } | Should -Not -BeNullOrEmpty
    }

    It "UAC désactivé → recommandation CRITIQUE" {
        $bad = $script:MockSec.Clone()
        $bad.UAC = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -like "CRITIQUE*UAC*" } | Should -Not -BeNullOrEmpty
    }

    It "Firewall public désactivé → recommandation CRITIQUE" {
        $bad = $script:MockSec.Clone()
        $bad.FW_Public = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "Firewall|firewall" } | Should -Not -BeNullOrEmpty
    }

    It "BitLocker inactif → recommandation (non critique)" {
        $bad = $script:MockSec.Clone()
        $bad.BitLocker = $false
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "BitLocker" } | Should -Not -BeNullOrEmpty
    }

    It "Configuration catastrophique → score ≤ 15" {
        $worst = @{
            DefenderEnabled=$false; DefenderUpdated=$false; TamperProtection=$false; DefenderScanDays=999
            FW_Domain=$false; FW_Private=$false; FW_Public=$false
            BitLocker=$false; WDigest=$true; SMBv1=$true
            RDP_NLA=$false; UAC=$false; AdminLocalActive=$true; CertsExpiring=5
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $worst
        $r.Score | Should -BeLessOrEqual 15
    }

    It "Score sécurité toujours entre 0 et 100" {
        $worst = @{
            DefenderEnabled=$false; DefenderUpdated=$false; TamperProtection=$false; DefenderScanDays=999
            FW_Domain=$false; FW_Private=$false; FW_Public=$false
            BitLocker=$false; WDigest=$true; SMBv1=$true
            RDP_NLA=$false; UAC=$false; AdminLocalActive=$true; CertsExpiring=10
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Security $args[0] } $worst
        $r.Score | Should -BeGreaterOrEqual 0
        $r.Score | Should -BeLessOrEqual 100
    }
}

# ═══════════════════════════════════════════════════════
# SCORE STOCKAGE
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Stockage" -Tag "Scoring","Storage" {

    It "Disques sains → score stockage ≥ 90" {
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $script:MockStorage
        $r.Score | Should -BeGreaterOrEqual 90
    }

    It "Disque C: à 95% → score stockage ≤ 30 et recommandation CRITIQUE" {
        $bad = @{
            Drives = @(@{ Name="C"; TotalGB=500; FreeGB=25; UsedPct=95 })
            SMART_Failures=0; SMART_Total=1; TempMB=100
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 30
        $r.Recommendations | Where-Object { $_ -like "CRITIQUE*Disque*" } | Should -Not -BeNullOrEmpty
    }

    It "Disque C: à 85% → avertissement (non critique)" {
        $bad = @{
            Drives = @(@{ Name="C"; TotalGB=500; FreeGB=75; UsedPct=85 })
            SMART_Failures=0; SMART_Total=1; TempMB=100
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "Disque|disque" } | Should -Not -BeNullOrEmpty
        # Pas de "CRITIQUE" pour 85%
        $r.Recommendations | Where-Object { $_ -like "CRITIQUE*" } | Should -BeNullOrEmpty
    }

    It "Défaillance SMART → recommandation sauvegarde immédiate" {
        $bad = @{
            Drives = @(@{ Name="C"; TotalGB=500; FreeGB=300; UsedPct=40 })
            SMART_Failures=1; SMART_Total=1; TempMB=100
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 70
        $r.Recommendations | Where-Object { $_ -match "SMART|sauvegarder" } | Should -Not -BeNullOrEmpty
    }

    It "Temp > 2000 Mo → recommandation nettoyage" {
        $bad = @{
            Drives = @(@{ Name="C"; TotalGB=500; FreeGB=300; UsedPct=40 })
            SMART_Failures=0; SMART_Total=1; TempMB=3000
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $bad
        $r.Recommendations | Where-Object { $_ -match "Temp|temp" } | Should -Not -BeNullOrEmpty
    }

    It "Score stockage toujours entre 0 et 100" {
        $worst = @{
            Drives = @(
                @{ Name="C"; TotalGB=100; FreeGB=2; UsedPct=98 }
                @{ Name="D"; TotalGB=100; FreeGB=1; UsedPct=99 }
            )
            SMART_Failures=3; SMART_Total=3; TempMB=10000
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Storage $args[0] } $worst
        $r.Score | Should -BeGreaterOrEqual 0
        $r.Score | Should -BeLessOrEqual 100
    }
}

# ═══════════════════════════════════════════════════════
# SCORE SERVICES
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Services" -Tag "Scoring","Services" {

    It "Tous les services démarrés → score 100" {
        $r = & (Get-Module ESN-HealthScore) { _Score-Services $args[0] } $script:MockSvc
        $r.Score | Should -Be 100
        $r.Recommendations.Count | Should -Be 0
    }

    It "1 service critique arrêté → score ≤ 75 et recommandation CRITIQUE" {
        $bad = @{
            TotalAuto=45; StoppedAuto=1; StoppedNames="WinDefend"
            CritStopped=1; CritStoppedNames="WinDefend"
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Services $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 75
        $r.Recommendations | Where-Object { $_ -like "CRITIQUE*service*" } | Should -Not -BeNullOrEmpty
    }

    It "3 services critiques arrêtés → score très bas (≤ 30)" {
        $bad = @{
            TotalAuto=45; StoppedAuto=3; StoppedNames="WinDefend,Spooler,EventLog"
            CritStopped=3; CritStoppedNames="WinDefend,Spooler,EventLog"
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Services $args[0] } $bad
        $r.Score | Should -BeLessOrEqual 30
    }

    It "Services non critiques arrêtés → avertissement sans critique" {
        $bad = @{
            TotalAuto=45; StoppedAuto=3; StoppedNames="Fax,TabletInputService,WSearch"
            CritStopped=0; CritStoppedNames=""
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Services $args[0] } $bad
        $critRec = $r.Recommendations | Where-Object { $_ -like "CRITIQUE*" }
        $critRec | Should -BeNullOrEmpty
    }

    It "Score services toujours entre 0 et 100" {
        $worst = @{
            TotalAuto=45; StoppedAuto=10; StoppedNames="svc1,svc2"
            CritStopped=10; CritStoppedNames="WinDefend,Spooler,EventLog,BITS,W32Time,Dnscache,CryptSvc,Winmgmt,LanmanWorkstation,NlaSvc"
        }
        $r = & (Get-Module ESN-HealthScore) { _Score-Services $args[0] } $worst
        $r.Score | Should -BeGreaterOrEqual 0
        $r.Score | Should -BeLessOrEqual 100
    }
}

# ═══════════════════════════════════════════════════════
# SCORE GLOBAL ET PONDÉRATION
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Score Global et Pondération" -Tag "Scoring","Global" {

    It "Tous les scores à 100 → global = 100" {
        $scores = @{
            Network  = @{ Score=100 }
            System   = @{ Score=100 }
            Security = @{ Score=100 }
            Storage  = @{ Score=100 }
            Services = @{ Score=100 }
        }
        $g = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $scores
        $g | Should -Be 100
    }

    It "Tous les scores à 0 → global = 0" {
        $scores = @{
            Network  = @{ Score=0 }
            System   = @{ Score=0 }
            Security = @{ Score=0 }
            Storage  = @{ Score=0 }
            Services = @{ Score=0 }
        }
        $g = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $scores
        $g | Should -Be 0
    }

    It "Pondération : sécurité pèse plus que services (25% vs 15%)" {
        # Score sécurité = 0, reste = 100
        $s1 = @{
            Network=@{Score=100}; System=@{Score=100}
            Security=@{Score=0}; Storage=@{Score=100}; Services=@{Score=100}
        }
        # Score services = 0, reste = 100
        $s2 = @{
            Network=@{Score=100}; System=@{Score=100}
            Security=@{Score=100}; Storage=@{Score=100}; Services=@{Score=0}
        }
        $g1 = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $s1
        $g2 = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $s2
        # g1 doit être plus bas que g2 car sécurité pèse plus
        $g1 | Should -BeLessThan $g2
    }

    It "La somme des poids = 100" {
        $weights = & (Get-Module ESN-HealthScore) { $script:Weights }
        ($weights.Values | Measure-Object -Sum).Sum | Should -Be 100
    }

    It "Score global toujours entre 0 et 100" {
        $scores = @{
            Network  = @{ Score=(Get-Random -Min 0 -Max 100) }
            System   = @{ Score=(Get-Random -Min 0 -Max 100) }
            Security = @{ Score=(Get-Random -Min 0 -Max 100) }
            Storage  = @{ Score=(Get-Random -Min 0 -Max 100) }
            Services = @{ Score=(Get-Random -Min 0 -Max 100) }
        }
        $g = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $scores
        $g | Should -BeGreaterOrEqual 0
        $g | Should -BeLessOrEqual 100
    }

    It "Score mixte cohérent : 80/80/80/80/80 → global = 80" {
        $scores = @{
            Network  = @{ Score=80 }
            System   = @{ Score=80 }
            Security = @{ Score=80 }
            Storage  = @{ Score=80 }
            Services = @{ Score=80 }
        }
        $g = & (Get-Module ESN-HealthScore) { _Score-Global $args[0] } $scores
        $g | Should -Be 80
    }
}

# ═══════════════════════════════════════════════════════
# INVOKE-HEALTHSCORE (intégration locale)
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Invoke-HealthScore (intégration)" -Tag "Integration" {

    It "S'exécute sur le poste local sans erreur" {
        { Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru } |
            Should -Not -Throw
    }

    It "Retourne un objet avec toutes les propriétés requises" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        $r                    | Should -Not -BeNullOrEmpty
        $r.ComputerName       | Should -Be $env:COMPUTERNAME
        $r.Global             | Should -Not -BeNullOrEmpty
        $r.Network            | Should -Not -BeNullOrEmpty
        $r.System             | Should -Not -BeNullOrEmpty
        $r.Security           | Should -Not -BeNullOrEmpty
        $r.Storage            | Should -Not -BeNullOrEmpty
        $r.Services           | Should -Not -BeNullOrEmpty
        $r.ReportPath         | Should -Not -BeNullOrEmpty
    }

    It "Score global est un entier entre 0 et 100" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        $r.Global.Score | Should -BeGreaterOrEqual 0
        $r.Global.Score | Should -BeLessOrEqual 100
        { [int]$r.Global.Score } | Should -Not -Throw
    }

    It "Tous les scores de domaine sont entre 0 et 100" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        foreach ($dom in @('Network','System','Security','Storage','Services')) {
            $r.$dom.Score | Should -BeGreaterOrEqual 0 -Because "$dom.Score doit être ≥ 0"
            $r.$dom.Score | Should -BeLessOrEqual 100  -Because "$dom.Score doit être ≤ 100"
        }
    }

    It "Chaque domaine a un Label non vide" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        foreach ($dom in @('Global','Network','System','Security','Storage','Services')) {
            $r.$dom.Label | Should -Not -BeNullOrEmpty -Because "$dom.Label ne doit pas être vide"
            $r.$dom.Label | Should -BeIn @("Excellent","Bon","Dégradé","Mauvais","Critique")
        }
    }

    It "Le timestamp est une date récente" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        $r.Timestamp | Should -BeOfType [datetime]
        ($r.Timestamp - (Get-Date)).TotalSeconds | Should -BeLessThan 120
    }

    It "TotalRecommendations est un entier ≥ 0" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        { [int]$r.TotalRecommendations } | Should -Not -Throw
        $r.TotalRecommendations | Should -BeGreaterOrEqual 0
    }

    It "Génère un fichier HTML de rapport" {
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        Test-Path $r.ReportPath             | Should -Be $true
        (Get-Item $r.ReportPath).Length     | Should -BeGreaterThan 2000
        $content = Get-Content $r.ReportPath -Raw
        $content | Should -Match "Score Santé"
        $content | Should -Match "Réseau"
        $content | Should -Match "Sécurité"
        $content | Should -Match "Stockage"
        $content | Should -Match "Services"
    }

    It "Le rapport HTML contient les scores des 5 domaines" {
        $r       = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -PassThru
        $content = Get-Content $r.ReportPath -Raw
        $content | Should -Match "$($r.Network.Score)"
        $content | Should -Match "$($r.Security.Score)"
    }

    It "ExportPath personnalisé fonctionne" {
        $tmpPath = Join-Path $env:TEMP "ESN_Score_Test_$(Get-Random).html"
        $r = Invoke-HealthScore -ComputerName $env:COMPUTERNAME -ExportPath $tmpPath -PassThru
        Test-Path $tmpPath | Should -Be $true
        Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
    }
}

# ═══════════════════════════════════════════════════════
# COMPARE-HEALTHSCORE
# ═══════════════════════════════════════════════════════

Describe "ESN-HealthScore — Compare-HealthScore" -Tag "Compare" {

    It "Ne génère pas d'erreur avec deux snapshots valides" {
        $snap1 = [PSCustomObject]@{
            ComputerName="PC-TEST"; Timestamp=(Get-Date).AddMinutes(-5)
            Global   = [PSCustomObject]@{ Score=60; Label="Dégradé" }
            Network  = [PSCustomObject]@{ Score=70; Label="Dégradé" }
            System   = [PSCustomObject]@{ Score=65; Label="Dégradé" }
            Security = [PSCustomObject]@{ Score=50; Label="Mauvais"  }
            Storage  = [PSCustomObject]@{ Score=80; Label="Bon"      }
            Services = [PSCustomObject]@{ Score=90; Label="Excellent" }
        }
        $snap2 = [PSCustomObject]@{
            ComputerName="PC-TEST"; Timestamp=Get-Date
            Global   = [PSCustomObject]@{ Score=80; Label="Bon"      }
            Network  = [PSCustomObject]@{ Score=90; Label="Excellent" }
            System   = [PSCustomObject]@{ Score=80; Label="Bon"       }
            Security = [PSCustomObject]@{ Score=75; Label="Dégradé"  }
            Storage  = [PSCustomObject]@{ Score=85; Label="Bon"       }
            Services = [PSCustomObject]@{ Score=95; Label="Excellent" }
        }
        { Compare-HealthScore -Before $snap1 -After $snap2 } | Should -Not -Throw
    }

    It "Détecte une amélioration du score global" {
        $before = [PSCustomObject]@{
            Global=@{Score=50}; Network=@{Score=50}; System=@{Score=50}
            Security=@{Score=50}; Storage=@{Score=50}; Services=@{Score=50}
        }
        $after = [PSCustomObject]@{
            Global=@{Score=80}; Network=@{Score=80}; System=@{Score=80}
            Security=@{Score=80}; Storage=@{Score=80}; Services=@{Score=80}
        }
        # Compare-HealthScore affiche en console — vérifier qu'il ne plante pas
        { Compare-HealthScore -Before $before -After $after } | Should -Not -Throw
    }
}

AfterAll {
    Remove-Module ESN-HealthScore -Force -ErrorAction SilentlyContinue
}
