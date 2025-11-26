# MigrationWizard.Main.ps1
# Point d'entrée principal du nouveau MigrationWizard (CLI + UI)

[CmdletBinding()]
param(
    # Si ExportPath est fourni => on fait un EXPORT en mode CLI
    [string]$ExportPath,

    # Si ImportPath est fourni => on fait un IMPORT en mode CLI
    [string]$ImportPath,

    # Options d’inclusion, alignées sur Export-MWProfile / Import-MWProfile
    [bool]$IncludeUserData           = $true,
    [bool]$IncludeWifi               = $true,
    [bool]$IncludePrinters           = $true,
    [bool]$IncludeNetworkDrives      = $true,
    [bool]$IncludeRdp                = $true,
    [bool]$IncludeBrowsers           = $true,
    [bool]$IncludeOutlook            = $true,
    [bool]$IncludeWallpaper          = $true,
    [bool]$IncludeDesktopLayout      = $true,
    [bool]$IncludeTaskbarStart       = $true,
    [bool]$UseDataFoldersManifest    = $false
)

# Initialisation du module de logs MigrationWizard
$modulesPath = Join-Path $PSScriptRoot 'src\Modules'
Import-Module (Join-Path $modulesPath 'MW.Logging.psm1') -Force -DisableNameChecking

Initialize-MWLogging
Write-MWLog -Message 'Démarrage de MigrationWizard.Main.ps1.' -Level 'INFO'

# Assure que le script tourne depuis son propre dossier
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

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


# Import des Features
Import-Module (Join-Path $featuresPath 'UserData.psm1')         -Force
Import-Module (Join-Path $featuresPath 'Wifi.psm1')             -Force
Import-Module (Join-Path $featuresPath 'Printers.psm1')         -Force
Import-Module (Join-Path $featuresPath 'TaskbarStart.psm1')     -Force
Import-Module (Join-Path $featuresPath 'WallpaperDesktop.psm1') -Force
Import-Module (Join-Path $featuresPath 'NetworkDrives.psm1')    -Force
Import-Module (Join-Path $featuresPath 'RDP.psm1')              -Force
Import-Module (Join-Path $featuresPath 'Browsers.psm1')         -Force
Import-Module (Join-Path $featuresPath 'Outlook.psm1')          -Force

# Import de la couche UI
Import-Module (Join-Path $uiPath 'MigrationWizard.UI.psm1') -Force

# Construction des paramètres communs d'export/import de profil
$profileParams = @{
    IncludeUserData           = $IncludeUserData
    IncludeWifi               = $IncludeWifi
    IncludePrinters           = $IncludePrinters
    IncludeNetworkDrives      = $IncludeNetworkDrives
    IncludeRdp                = $IncludeRdp
    IncludeBrowsers           = $IncludeBrowsers
    IncludeOutlook            = $IncludeOutlook
    IncludeWallpaper          = $IncludeWallpaper
    IncludeDesktopLayout      = $IncludeDesktopLayout
    IncludeTaskbarStart       = $IncludeTaskbarStart
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
        -IncludeBrowsers         $IncludeBrowsers `
        -IncludeOutlook          $IncludeOutlook `
        -IncludeWallpaper        $IncludeWallpaper `
        -IncludeDesktopLayout    $IncludeDesktopLayout `
        -IncludeTaskbarStart     $IncludeTaskbarStart `
        -UseDataFoldersManifest  $UseDataFoldersManifest
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
        -IncludeBrowsers         $IncludeBrowsers `
        -IncludeOutlook          $IncludeOutlook `
        -IncludeWallpaper        $IncludeWallpaper `
        -IncludeDesktopLayout    $IncludeDesktopLayout `
        -IncludeTaskbarStart     $IncludeTaskbarStart `
        -UseDataFoldersManifest  $UseDataFoldersManifest
}
else {
    # Mode UI : aucun chemin passé => on lance la WPF
    Start-MigrationWizard
}
