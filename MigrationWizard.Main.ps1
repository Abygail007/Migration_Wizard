# MigrationWizard.Main.ps1
# Point d'entrée principal du nouveau MigrationWizard (CLI + UI)

[CmdletBinding()]
param(
    # Si ExportPath est fourni => on fait un EXPORT en mode CLI
    [string]$ExportPath,

    # Si ImportPath est fourni => on fait un IMPORT en mode CLI
    [string]$ImportPath,

    # Options d'inclusion, alignées sur Export-MWProfile / Import-MWProfile
    [bool]$IncludeUserData           = $true,
    [bool]$IncludeWifi               = $true,
    [bool]$IncludePrinters           = $true,
    [bool]$IncludeNetworkDrives      = $true,
    [bool]$IncludeRdp                = $true,
    [bool]$IncludeChrome             = $false,
    [bool]$IncludeEdge               = $false,
    [bool]$IncludeFirefox            = $false,
    [bool]$IncludeOutlook            = $true,
    [bool]$IncludeWallpaper          = $true,
    [bool]$IncludeDesktopLayout      = $true,
    [bool]$IncludeTaskbarStart       = $true,
    [bool]$IncludeQuickAccess        = $true,
    [bool]$UseDataFoldersManifest    = $false,
    [bool]$IncrementalMode           = $false
)

# ===== ÉLÉVATION ADMIN AUTOMATIQUE =====
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️ Élévation des droits administrateur requise..." -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        $arguments += " -$($param.Key)"
        if ($param.Value -is [string]) {
            $arguments += " `"$($param.Value)`""
        }
        elseif ($param.Value -is [bool]) {
            $arguments += " `$$($param.Value)"
        }
        else {
            $arguments += " $($param.Value)"
        }
    }
    
    try {
        Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
        exit
    }
    catch {
        Write-Host "❌ Impossible d'élever les droits" -ForegroundColor Red
        Read-Host "Appuyez sur Entrée pour quitter"
        exit 1
    }
}

Write-Host "✅ Exécution en mode Administrateur" -ForegroundColor Green
# ===== FIN ÉLÉVATION ADMIN =====

# ===== DÉTECTION DU DOSSIER RACINE (SCRIPT .PS1 OU .EXE) =====
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Cas classique : on lance le .ps1 directement
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    # Cas compilé : on lance un .exe
    $exePath = [Environment]::GetCommandLineArgs()[0]
    $ScriptRoot = Split-Path -Parent $exePath

    if (-not $ScriptRoot -or $ScriptRoot -eq '') {
        $ScriptRoot = (Get-Location).Path
    }
}

$Global:MWRootPath = $ScriptRoot

# On se place dans le dossier racine du projet
Set-Location $ScriptRoot

# ===== INITIALISATION DU MODULE DE LOGS MIGRATIONWIZARD =====
$modulesPath = Join-Path $ScriptRoot 'src\Modules'
Import-Module (Join-Path $modulesPath 'MW.Logging.psm1') -Force -DisableNameChecking

Initialize-MWLogging
Write-MWLogInfo -Message 'Démarrage de MigrationWizard.Main.ps1.'

# Chemins de base
$srcPath      = Join-Path $ScriptRoot 'src'
$corePath     = Join-Path $srcPath 'Core'
$featuresPath = Join-Path $srcPath 'Features'
$uiPath       = Join-Path $srcPath 'UI'

# Import des modules Core
Import-Module (Join-Path $corePath 'Bootstrap.psm1')   -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'FileCopy.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'DataFolders.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'OneDrive.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'Profile.psm1')     -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'Export.psm1')      -Force -ErrorAction Stop
Import-Module (Join-Path $corePath 'Applications.psm1') -Force -ErrorAction Stop


# Import des Features
Import-Module (Join-Path $featuresPath 'UserData.psm1')         -Force
Import-Module (Join-Path $featuresPath 'Wifi.psm1')             -Force
Import-Module (Join-Path $featuresPath 'Printers.psm1')         -Force
Import-Module (Join-Path $featuresPath 'TaskbarStart.psm1')     -Force
Import-Module (Join-Path $featuresPath 'WallpaperDesktop.psm1') -Force
Import-Module (Join-Path $featuresPath 'QuickAccess.psm1')      -Force
Import-Module (Join-Path $featuresPath 'NetworkDrives.psm1')    -Force
Import-Module (Join-Path $featuresPath 'RDP.psm1')              -Force
Import-Module (Join-Path $featuresPath 'Browsers.psm1')         -Force
Import-Module (Join-Path $featuresPath 'BrowserDetection.psm1') -Force
Import-Module (Join-Path $featuresPath 'Outlook.psm1')          -Force

# ========================================
# NOUVEAUX MODULES REFACTORING V4
# ========================================

# Module de sélection de clients pour import
Import-Module (Join-Path $featuresPath 'ClientSelector.psm1') -Force -ErrorAction Stop -WarningAction SilentlyContinue

# Modules UI refactorisés
Import-Module (Join-Path $uiPath 'ManifestManager.psm1') -Force -DisableNameChecking -ErrorAction Stop
Import-Module (Join-Path $uiPath 'TreeBuilder.psm1') -Force -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module (Join-Path $uiPath 'UINavigation.psm1') -Force -DisableNameChecking -ErrorAction Stop
Import-Module (Join-Path $uiPath 'UIValidation.psm1') -Force -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module (Join-Path $uiPath 'SummaryBuilder.psm1') -Force -DisableNameChecking -ErrorAction Stop

Write-MWLogInfo "Tous les modules charges avec succes"
# ========================================

# Import de la couche UI principale (réduite)
Import-Module (Join-Path $uiPath 'MigrationWizard.UI.psm1') -Force

# Construction des paramètres communs d'export/import de profil
$profileParams = @{
    IncludeUserData           = $IncludeUserData
    IncludeWifi               = $IncludeWifi
    IncludePrinters           = $IncludePrinters
    IncludeNetworkDrives      = $IncludeNetworkDrives
    IncludeRdp                = $IncludeRdp
    IncludeChrome             = $IncludeChrome
    IncludeEdge               = $IncludeEdge
    IncludeFirefox            = $IncludeFirefox
    IncludeOutlook            = $IncludeOutlook
    IncludeWallpaper          = $IncludeWallpaper
    IncludeDesktopLayout      = $IncludeDesktopLayout
    IncludeTaskbarStart       = $IncludeTaskbarStart
    IncludeQuickAccess        = $IncludeQuickAccess
    UseDataFoldersManifest    = $UseDataFoldersManifest
}

# Initialisation de l'environnement (paths, dossiers, etc.)
Initialize-MWEnvironment

if ($PSBoundParameters.ContainsKey('ExportPath')) {
    Write-MWLog -Message ("Main : exécution en mode CLI EXPORT vers '{0}'." -f $ExportPath) -Level 'INFO'

    Export-MWProfile `
        -DestinationFolder       $ExportPath `
        -IncludeUserData         $IncludeUserData `
        -IncludeWifi             $IncludeWifi `
        -IncludePrinters         $IncludePrinters `
        -IncludeNetworkDrives    $IncludeNetworkDrives `
        -IncludeRdp              $IncludeRdp `
        -IncludeChrome           $IncludeChrome `
        -IncludeEdge             $IncludeEdge `
        -IncludeFirefox          $IncludeFirefox `
        -IncludeOutlook          $IncludeOutlook `
        -IncludeWallpaper        $IncludeWallpaper `
        -IncludeDesktopLayout    $IncludeDesktopLayout `
        -IncludeTaskbarStart     $IncludeTaskbarStart `
        -IncludeQuickAccess      $IncludeQuickAccess `
        -UseDataFoldersManifest  $UseDataFoldersManifest `
        -IncrementalMode         $IncrementalMode
}
elseif ($PSBoundParameters.ContainsKey('ImportPath')) {
    Write-MWLog -Message ("Main : exécution en mode CLI IMPORT depuis '{0}'." -f $ImportPath) -Level 'INFO'

    Import-MWProfile `
        -SourceFolder            $ImportPath `
        -IncludeUserData         $IncludeUserData `
        -IncludeWifi             $IncludeWifi `
        -IncludePrinters         $IncludePrinters `
        -IncludeNetworkDrives    $IncludeNetworkDrives `
        -IncludeRdp              $IncludeRdp `
        -IncludeChrome           $IncludeChrome `
        -IncludeEdge             $IncludeEdge `
        -IncludeFirefox          $IncludeFirefox `
        -IncludeOutlook          $IncludeOutlook `
        -IncludeWallpaper        $IncludeWallpaper `
        -IncludeDesktopLayout    $IncludeDesktopLayout `
        -IncludeTaskbarStart     $IncludeTaskbarStart `
        -IncludeQuickAccess      $IncludeQuickAccess `
        -UseDataFoldersManifest  $UseDataFoldersManifest
}
else {
    # Mode UI : aucun chemin passé => on lance la WPF
    Start-MWMigrationWizardUI
}
