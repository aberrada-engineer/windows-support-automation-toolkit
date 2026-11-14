#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-CentralDashboard v3.0 - Lanceur du Tableau de Bord Web Exécutif (Single Pane of Glass).
    Ouvre l'interface web centrale pour la supervision multi-clients et les comités de direction.
#>

[CmdletBinding()]
param(
    [switch]$OpenBrowser = $true
)

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent
$DashboardPath = Join-Path $ScriptDir "WebDashboard\index.html"

Import-Module "$ScriptDir\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
# Synchronisation vers le dossier WebDashboard actif si nécessaire
$targetDir = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "WebDashboard" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/WebDashboard" }
if (-not (Test-Path $targetDir)) { New-Item $targetDir -ItemType Directory -Force | Out-Null }
$targetFile = Join-Path $targetDir "index.html"
Copy-Item $DashboardPath $targetFile -Force -ErrorAction SilentlyContinue

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🖥️  OUVERTURE DU TABLEAU DE BORD ESN-CENTRAL WEB DASHBOARD" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " Emplacement : $targetFile" -ForegroundColor Green

if ($OpenBrowser) {
    Start-Process $targetFile
}
