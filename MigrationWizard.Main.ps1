# Initialisation du module de logs MigrationWizard
$modulesPath = Join-Path $PSScriptRoot 'src\Modules'
Import-Module (Join-Path $modulesPath 'MW.Logging.psm1') -Force -DisableNameChecking

Initialize-MWLogging
Write-MWLog -Message 'Démarrage de MigrationWizard.Main.ps1.' -Level 'INFO'

# MigrationWizard.Main.ps1
# Point d'entrÃ©e principal du nouveau MigrationWizard

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
Import-Module (Join-Path $corePath 'Logging.psm1')     -Force -ErrorAction Stop
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

# Initialisation de l'environnement
Initialize-MWEnvironment

# Initialisation du logging
Initialize-MWLogging

# Lancement de l'application
Start-MigrationWizard

