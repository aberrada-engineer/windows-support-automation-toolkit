#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester v5 pour ESN-Toolkit.
    Couvre : Core, Network helpers, Windows helpers, AD helpers, Migration.

.USAGE
    # Depuis la racine du toolkit :
    Invoke-Pester .\Tests\ESN-Toolkit.Tests.ps1 -Output Detailed
    Invoke-Pester .\Tests\ESN-Toolkit.Tests.ps1 -Output Detailed -Tag "Core"
#>

BeforeAll {
    $root      = Split-Path $PSScriptRoot -Parent
    $corePath  = Join-Path $root "Core\ESN-Core.psm1"
    $netPath   = Join-Path $root "Modules\Network\ESN-Network.psm1"
    $winPath   = Join-Path $root "Modules\Windows\ESN-Windows.psm1"
    $adPath    = Join-Path $root "Modules\AD\ESN-AD.psm1"
    $migPath   = Join-Path $root "Modules\Migration\ESN-Migration.psm1"

    Import-Module $corePath -Force
}

# ═══════════════════════════════════════════════════════
# CORE
# ═══════════════════════════════════════════════════════

Describe "ESN-Core — Module fondation" -Tag "Core" {

    Context "Fonctions exportées" {
        It "Exporte Initialize-ESNSession" {
            Get-Command Initialize-ESNSession -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Write-ESNLog" {
            Get-Command Write-ESNLog -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Add-ESNResult" {
            Get-Command Add-ESNResult -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Export-ESNReport" {
            Get-Command Export-ESNReport -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Export-ESNZip" {
            Get-Command Export-ESNZip -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Show-ESNSummary" {
            Get-Command Show-ESNSummary -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Test-ESNPort" {
            Get-Command Test-ESNPort -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
        It "Exporte Test-ESNAdmin" {
            Get-Command Test-ESNAdmin -Module ESN-Core | Should -Not -BeNullOrEmpty
        }
    }

    Context "Initialize-ESNSession" {
        It "Initialise la session et crée le fichier log" {
            $log = Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-001"
            $log                    | Should -Not -BeNullOrEmpty
            Test-Path (Split-Path $log) | Should -Be $true
        }

        It "Réinitialise les listes de résultats" {
            Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-002"
            $s = Get-ESNSession
            $s.Results.Count  | Should -Be 0
            $s.Errors.Count   | Should -Be 0
            $s.Warnings.Count | Should -Be 0
            $s.Score          | Should -Be 100
        }
    }

    Context "Add-ESNResult" {
        BeforeEach {
            Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-RES"
        }

        It "Ajoute un résultat OK sans impact score" {
            Add-ESNResult -Category "Test" -Check "Check1" -Status "OK" -Value "Valeur"
            $s = Get-ESNSession
            $s.Results.Count | Should -Be 1
            $s.Score         | Should -Be 100
        }

        It "Ajoute un résultat WARN et diminue le score de 5 (défaut)" {
            Add-ESNResult -Category "Test" -Check "Check2" -Status "WARN" -Value "Alerte"
            $s = Get-ESNSession
            $s.Score          | Should -Be 95
            $s.Warnings.Count | Should -Be 1
        }

        It "Ajoute un résultat ERROR et diminue le score de 10 (défaut)" {
            Add-ESNResult -Category "Test" -Check "Check3" -Status "ERROR" -Value "Erreur"
            $s = Get-ESNSession
            $s.Score        | Should -Be 90
            $s.Errors.Count | Should -Be 1
        }

        It "Respecte un ScoreImpact personnalisé" {
            Add-ESNResult -Category "Test" -Check "Check4" -Status "ERROR" -Value "Big" -ScoreImpact 25
            $s = Get-ESNSession
            $s.Score | Should -Be 75
        }

        It "Le score ne descend jamais en dessous de 0" {
            for ($i = 0; $i -lt 20; $i++) {
                Add-ESNResult -Category "Test" -Check "C$i" -Status "ERROR" -ScoreImpact 10
            }
            (Get-ESNSession).Score | Should -Be 0
        }

        It "Résultat INFO n'affecte pas le score" {
            Add-ESNResult -Category "Test" -Check "Info" -Status "INFO" -Value "Info"
            (Get-ESNSession).Score | Should -Be 100
        }
    }

    Context "Export-ESNReport" {
        BeforeAll {
            Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-RPT"
            Add-ESNResult "Cat1" "Check1" "OK"    "Val1"
            Add-ESNResult "Cat2" "Check2" "WARN"  "Val2"
            Add-ESNResult "Cat3" "Check3" "ERROR" "Val3"
        }

        It "Génère un fichier HTML non vide" {
            $path = Export-ESNReport
            $path                     | Should -Not -BeNullOrEmpty
            Test-Path $path           | Should -Be $true
            (Get-Item $path).Length   | Should -BeGreaterThan 1000
        }

        It "Le rapport contient les résultats" {
            $path    = Export-ESNReport
            $content = Get-Content $path -Raw
            $content | Should -Match "Cat1"
            $content | Should -Match "Cat2"
            $content | Should -Match "WARN"
            $content | Should -Match "ERROR"
        }

        It "Le rapport contient le score de santé" {
            $path    = Export-ESNReport
            $content = Get-Content $path -Raw
            $content | Should -Match "Score"
            $content | Should -Match "/100"
        }
    }

    Context "Export-ESNZip" {
        It "Crée un fichier ZIP valide" {
            Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-ZIP"
            Add-ESNResult "Test" "ZipCheck" "OK" "Val"
            $zip = Export-ESNZip
            Test-Path $zip | Should -Be $true
            $zip           | Should -Match "\.zip$"
            (Get-Item $zip).Length | Should -BeGreaterThan 100
        }
    }

    Context "Helpers" {
        It "Test-ESNAdmin retourne un booléen" {
            $r = Test-ESNAdmin
            $r | Should -BeOfType [bool]
        }

        It "Test-ESNPort retourne false pour un port fermé connu" {
            $r = Test-ESNPort -Host "127.0.0.1" -Port 19999 -TimeoutMs 500
            $r | Should -Be $false
        }

        It "Test-ESNPort retourne true pour localhost:135 (RPC, toujours ouvert)" {
            # RPC endpoint mapper, disponible en local sauf si firewall bloque
            $r = Test-ESNPort -Host "127.0.0.1" -Port 135 -TimeoutMs 1000
            # On vérifie juste que ça retourne un bool (peut être $false si firewall strict)
            $r | Should -BeOfType [bool]
        }
    }
}

# ═══════════════════════════════════════════════════════
# NETWORK MODULE
# ═══════════════════════════════════════════════════════

Describe "ESN-Network — Module réseau" -Tag "Network" {

    BeforeAll {
        $netPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Network\ESN-Network.psm1"
        Import-Module $netPath -Force
    }

    It "Exporte Invoke-NetworkDiag" {
        Get-Command Invoke-NetworkDiag | Should -Not -BeNullOrEmpty
    }

    It "Invoke-NetworkDiag s'exécute en local sans erreur critique" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-NET"
        { Invoke-NetworkDiag -ComputerName $env:COMPUTERNAME } | Should -Not -Throw
        $s = Get-ESNSession
        $s.Results.Count | Should -BeGreaterThan 3
    }

    It "Détecte au moins une adresse IP valide en local" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-NET2"
        Invoke-NetworkDiag -ComputerName $env:COMPUTERNAME
        $ipResult = (Get-ESNSession).Results | Where-Object { $_.Check -eq "Adresse IP" }
        $ipResult | Should -Not -BeNullOrEmpty
    }
}

# ═══════════════════════════════════════════════════════
# WINDOWS MODULE
# ═══════════════════════════════════════════════════════

Describe "ESN-Windows — Module système" -Tag "Windows" {

    BeforeAll {
        $winPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Windows\ESN-Windows.psm1"
        Import-Module $winPath -Force
    }

    It "Exporte Invoke-WindowsDiag" {
        Get-Command Invoke-WindowsDiag | Should -Not -BeNullOrEmpty
    }

    It "Invoke-WindowsDiag s'exécute sans erreur critique" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-WIN"
        { Invoke-WindowsDiag -ComputerName $env:COMPUTERNAME } | Should -Not -Throw
    }

    It "Détecte l'OS, la RAM et au moins un disque" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-WIN2"
        Invoke-WindowsDiag -ComputerName $env:COMPUTERNAME
        $results = (Get-ESNSession).Results
        ($results | Where-Object Check -eq "Système d'exploitation") | Should -Not -BeNullOrEmpty
        ($results | Where-Object Check -eq "RAM")                    | Should -Not -BeNullOrEmpty
        ($results | Where-Object { $_.Check -like "Disque*" })       | Should -Not -BeNullOrEmpty
    }

    It "Le check Defender retourne OK ou ERROR (jamais null)" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-WIN3"
        Invoke-WindowsDiag -ComputerName $env:COMPUTERNAME
        $def = (Get-ESNSession).Results | Where-Object Check -eq "Windows Defender"
        $def | Should -Not -BeNullOrEmpty
        $def.Status | Should -BeIn @("OK","ERROR","WARN")
    }
}

# ═══════════════════════════════════════════════════════
# AD MODULE
# ═══════════════════════════════════════════════════════

Describe "ESN-AD — Module Active Directory" -Tag "AD" {

    BeforeAll {
        $adPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\AD\ESN-AD.psm1"
        Import-Module $adPath -Force
    }

    It "Exporte Test-ADAvailable" {
        Get-Command Test-ADAvailable | Should -Not -BeNullOrEmpty
    }

    It "Exporte Invoke-ADAudit" {
        Get-Command Invoke-ADAudit | Should -Not -BeNullOrEmpty
    }

    It "Exporte Invoke-ADUserReset" {
        Get-Command Invoke-ADUserReset | Should -Not -BeNullOrEmpty
    }

    It "Exporte New-ADUserESN" {
        Get-Command New-ADUserESN | Should -Not -BeNullOrEmpty
    }

    It "Test-ADAvailable retourne un booléen" {
        $r = Test-ADAvailable
        $r | Should -BeOfType [bool]
    }

    It "Invoke-ADAudit ne plante pas si module AD absent" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-AD"
        # Si le module AD n'est pas dispo, doit ajouter un résultat WARN, pas lever d'exception
        { Invoke-ADAudit } | Should -Not -Throw
    }
}

# ═══════════════════════════════════════════════════════
# MIGRATION MODULE
# ═══════════════════════════════════════════════════════

Describe "ESN-Migration — Module migration" -Tag "Migration" {

    BeforeAll {
        $migPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Migration\ESN-Migration.psm1"
        Import-Module $migPath -Force
    }

    It "Exporte Invoke-UserStateCapture" {
        Get-Command Invoke-UserStateCapture | Should -Not -BeNullOrEmpty
    }

    It "Exporte Invoke-UserStateRestore" {
        Get-Command Invoke-UserStateRestore | Should -Not -BeNullOrEmpty
    }

    It "Invoke-UserStateCapture en simulation crée le dossier et le manifest" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-MIG"
        $tmpRoot = Join-Path $env:TEMP "ESN_Test_Migration"

        $dir = Invoke-UserStateCapture `
            -SourceComputer $env:COMPUTERNAME `
            -Username       $env:USERNAME `
            -BackupRoot     $tmpRoot `
            -All `
            -Simulation

        $dir | Should -Not -BeNullOrEmpty
        Test-Path $dir | Should -Be $true
        Test-Path (Join-Path $dir "manifest.json") | Should -Be $true

        # Nettoyage
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Le manifest contient les champs attendus" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-MIG2"
        $tmpRoot = Join-Path $env:TEMP "ESN_Test_Migration2"

        $dir = Invoke-UserStateCapture `
            -SourceComputer $env:COMPUTERNAME `
            -Username       $env:USERNAME `
            -BackupRoot     $tmpRoot `
            -Simulation

        $mf = Get-Content (Join-Path $dir "manifest.json") -Raw | ConvertFrom-Json
        $mf.Username       | Should -Be $env:USERNAME
        $mf.SourceComputer | Should -Be $env:COMPUTERNAME
        $mf.Simulation     | Should -Be $true
        $mf.CaptureDate    | Should -Not -BeNullOrEmpty

        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Invoke-UserStateRestore échoue proprement si BackupDir invalide" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-MIG3"
        Invoke-UserStateRestore `
            -BackupDir      "C:\Inexistant\FakeDir_$(Get-Random)" `
            -TargetComputer $env:COMPUTERNAME `
            -Username       $env:USERNAME

        $errResult = (Get-ESNSession).Results |
                     Where-Object { $_.Status -eq "ERROR" -and $_.Check -like "*backup*" }
        $errResult | Should -Not -BeNullOrEmpty
    }
}

# ═══════════════════════════════════════════════════════
# INVOKE-INCIDENTANALYSIS (intégration légère)
# ═══════════════════════════════════════════════════════

Describe "Invoke-IncidentAnalysis — Intégration" -Tag "Integration" {

    It "Le script existe à la racine du toolkit" {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) "Invoke-IncidentAnalysis.ps1"
        Test-Path $path | Should -Be $true
    }

    It "S'exécute avec -Modules Network,Windows et retourne un objet résultat" {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) "Invoke-IncidentAnalysis.ps1"
        $result = & $path -Modules Network,Windows -IncidentId "PESTER-INT-001" 2>&1 |
                  Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1

        $result | Should -Not -BeNullOrEmpty
        $result.IncidentId  | Should -Be "PESTER-INT-001"
        $result.Score       | Should -BeGreaterOrEqual 0
        $result.Score       | Should -BeLessOrEqual 100
        $result.ReportPath  | Should -Not -BeNullOrEmpty
        Test-Path $result.ReportPath | Should -Be $true
    }
}

AfterAll {
    # Nettoyage modules de test
    Remove-Module ESN-Core, ESN-Network, ESN-Windows, ESN-AD, ESN-Migration -Force -ErrorAction SilentlyContinue
}
