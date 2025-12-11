# ==============================================================================
# MigrationWizard.UI.psm1 (VERSION REFACTORISÉE)
# Gestion de l'interface WPF - VERSION RÉDUITE
# ==============================================================================
# Ce fichier a été réduit de 1407 → ~450 lignes grâce au refactoring modulaire
# Les fonctions sont maintenant dans des modules dédiés
# ==============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Charger le base64 du logo (sauf en mode portable ou deja charge)
if (-not $script:IsPortableMode -and $PSScriptRoot) {
    $logoPath = Join-Path $PSScriptRoot '..\Assets\MW.Logo.Base64.ps1'
    if (Test-Path -LiteralPath $logoPath -ErrorAction SilentlyContinue) {
        . $logoPath
    }
}

# Variables de scope script
$script:Window = $null
$script:IsExport = $true
$script:PasswordExports = @{}

# Contrôles UI (cache)
$script:UI = @{}

function Test-OutlookInstalled {
    try {
        $outlookPath = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-WiFiAvailable {
    # FIX: Toujours retourner $true car l'export WiFi fonctionne maintenant depuis ProgramData
    # même sans adaptateur WiFi actif (lit les profils XML système)
    return $true

    # Ancienne logique qui masquait le WiFi si pas d'adaptateur:
    # try {
    #     $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -like '*802.11*' -or $_.InterfaceDescription -like '*Wi-Fi*' -or $_.InterfaceDescription -like '*Wireless*' }
    #     return ($adapters.Count -gt 0)
    # }
    # catch {
    #     return $false
    # }
}

function Get-MWLogoImageSource {
    <#
    .SYNOPSIS
    Retourne un BitmapImage à partir du base64 du logo
    #>
    try {
        if (-not $MWLogoBase64) {
            Write-MWLogWarning "MWLogoBase64 vide ou non chargé"
            return $null
        }

        $bytes = [Convert]::FromBase64String($MWLogoBase64)
        $ms    = New-Object System.IO.MemoryStream(,$bytes)

        $image = New-Object System.Windows.Media.Imaging.BitmapImage
        $image.BeginInit()
        $image.StreamSource = $ms
        $image.CacheOption  = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.EndInit()
        $image.Freeze()  # pour éviter les problèmes de thread WPF

        return $image
    }
    catch {
        Write-MWLogError "Erreur création image logo : $($_.Exception.Message)"
        return $null
    }
}

function Get-MWNyanCatImageSource {
    <#
    .SYNOPSIS
    Retourne un BitmapImage pour le GIF Nyan Cat (depuis base64 ou fichier)
    #>
    try {
        # Priorité 1: Base64 embarqué (mode portable)
        if ($script:NyanCatBase64 -and -not [string]::IsNullOrWhiteSpace($script:NyanCatBase64)) {
            Write-MWLogInfo "Chargement Nyan Cat depuis base64 embarqué"
            $bytes = [Convert]::FromBase64String($script:NyanCatBase64)
            $ms = New-Object System.IO.MemoryStream(,$bytes)

            $image = New-Object System.Windows.Media.Imaging.BitmapImage
            $image.BeginInit()
            $image.StreamSource = $ms
            $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $image.EndInit()
            $image.Freeze()

            return $image
        }

        # Priorité 2: Fichier externe (mode développement)
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            # CORRECTION: Utiliser JPG au lieu de GIF (WPF ne supporte pas les GIF animés)
            $imgPath = Join-Path $PSScriptRoot "..\..\Tools\nyan-cat-gif-1.jpg"
            $imgPath = [System.IO.Path]::GetFullPath($imgPath)

            if (Test-Path -LiteralPath $imgPath -ErrorAction SilentlyContinue) {
                Write-MWLogInfo "Chargement Nyan Cat depuis fichier: $imgPath"
                $image = New-Object System.Windows.Media.Imaging.BitmapImage
                $image.BeginInit()
                $image.UriSource = New-Object System.Uri($imgPath, [System.UriKind]::Absolute)
                $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $image.EndInit()
                $image.Freeze()

                return $image
            }
        }

        Write-MWLogWarning "Nyan Cat image introuvable (ni base64, ni fichier)"
        return $null
    }
    catch {
        Write-MWLogError "Erreur chargement Nyan Cat GIF : $($_.Exception.Message)"
        return $null
    }
}

function Hide-ConditionalControls {
    <#
    .SYNOPSIS
    Masque les contrôles si fonctionnalité non disponible
    #>
    if (-not (Test-OutlookInstalled)) {
        if ($script:UI.ContainsKey('CbAppOutlook') -and $script:UI.CbAppOutlook) {
            $script:UI.CbAppOutlook.Visibility = 'Collapsed'
        }
    }
    
    if (-not (Test-WiFiAvailable)) {
        if ($script:UI.ContainsKey('CbWifi') -and $script:UI.CbWifi) {
            $script:UI.CbWifi.Visibility = 'Collapsed'
        }
    }
}

function Prevent-SystemSleep {
    try {
        $code = @'
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
        # Constantes pour SetThreadExecutionState (en décimal pour éviter overflow)
        $ES_CONTINUOUS = [uint32]2147483648
        $ES_SYSTEM_REQUIRED = [uint32]1
        $ES_AWAYMODE_REQUIRED = [uint32]64

        if (-not ([System.Management.Automation.PSTypeName]'MWPowerHelper').Type) {
            Add-Type -MemberDefinition $code -Namespace 'MigrationWizard' -Name 'PowerHelper'
        }

        [MigrationWizard.PowerHelper]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_AWAYMODE_REQUIRED) | Out-Null
        Write-MWLogInfo "Prévention mise en veille activée"
    }
    catch {
        Write-MWLogWarning "Impossible d'empêcher mise en veille : $($_.Exception.Message)"
    }
}

function Allow-SystemSleep {
    try {
        $ES_CONTINUOUS = [uint32]2147483648
        [MigrationWizard.PowerHelper]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
        Write-MWLogInfo "Prévention mise en veille désactivée"
    }
    catch {
        Write-MWLogWarning "Impossible de restaurer mise en veille : $($_.Exception.Message)"
    }
}

function Fill-ClientsList {
    <#
    .SYNOPSIS
    Remplit la ListBox lstClients avec les clients détectés
    #>
    [CmdletBinding()]
    param()

    Write-MWLogInfo "Remplissage de la liste des clients..."

    # Vider la liste
    $script:UI.lstClients.Items.Clear()

    # Scanner les dossiers clients dans le dossier d'exécution de l'EXE
    $defaultPath = Get-DefaultExportPath

    Write-MWLogInfo "Scan des clients dans : $defaultPath"

    # Le dossier existe toujours (c'est le dossier où l'EXE est lancé)
    # Pas besoin de le créer

    # Scanner les clients
    try {
        $clients = Scan-ClientFolders -BasePath $defaultPath

        if ($clients -and $clients.Count -gt 0) {
            Write-MWLogInfo "$($clients.Count) client(s) détecté(s)"

            foreach ($client in $clients) {
                $script:UI.lstClients.Items.Add($client) | Out-Null
            }

            # Sélectionner le premier par défaut
            if ($script:UI.lstClients.Items.Count -gt 0) {
                $script:UI.lstClients.SelectedIndex = 0
            }
        }
        else {
            Write-MWLogInfo "Aucun client détecté dans $defaultPath"

            # Ajouter un message dans la liste
            $noClientMessage = [PSCustomObject]@{
                FolderPath = ""
                FolderName = ""
                ComputerName = ""
                UserName = ""
                Date = [DateTime]::MinValue
                DisplayInfo = "❌ Aucun export détecté - Utilisez 'Parcourir manuellement' ci-dessous"
                Manifest = $null
            }
            $script:UI.lstClients.Items.Add($noClientMessage) | Out-Null
        }
    }
    catch {
        Write-MWLogError "Erreur scan clients : $($_.Exception.Message)"
    }
}

function Start-MWMigrationWizardUI {
    <#
    .SYNOPSIS
    Point d'entrée principal de l'interface WPF
    #>
    [CmdletBinding()]
    param()
    
    Write-MWLogInfo "=== Démarrage MigrationWizard UI ==="
    
    # Charger le XAML (supporte mode portable avec XAML embarqué)
    try {
        if ($script:EmbeddedXAML) {
            # MODE PORTABLE: XAML embarqué dans le script
            Write-MWLogInfo "Chargement XAML embarqué (mode portable)"
            [xml]$xaml = $script:EmbeddedXAML
        }
        else {
            # MODE DÉVELOPPEMENT: XAML depuis fichier externe
            $xamlPath = Join-Path $PSScriptRoot 'MigrationWizard.xaml'
            
            if (-not (Test-Path $xamlPath)) {
                Write-MWLogError "Fichier XAML introuvable : $xamlPath"
                [System.Windows.MessageBox]::Show("Fichier XAML introuvable", "Erreur", 'OK', 'Error')
                return
            }
            
            Write-MWLogInfo "Chargement XAML depuis fichier: $xamlPath"
            [xml]$xaml = Get-Content $xamlPath -Raw -Encoding UTF8
        }
        
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $script:Window = [Windows.Markup.XamlReader]::Load($reader)
        $Global:MWWindow = $script:Window  # Référence globale pour les autres modules

        Write-MWLogInfo "XAML chargé avec succès"
    }
    catch {
        Write-MWLogError "Erreur chargement XAML : $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Erreur chargement interface : $($_.Exception.Message)", "Erreur", 'OK', 'Error')
        return
    }
    
    # Initialiser les contrôles et handlers
    Initialize-UIControls
    Initialize-UIHandlers
    Initialize-UIData
    
    # Afficher page 1
    Show-UIPage -PageNumber 1 -Window $script:Window
    
    # Afficher fenêtre
    $script:Window.ShowDialog() | Out-Null
    
    Write-MWLogInfo "=== Fin MigrationWizard UI ==="
}

function Initialize-UIControls {
    <#
    .SYNOPSIS
    Charge tous les contrôles UI dans $script:UI
    #>
    Write-MWLogInfo "Initialisation des contrôles UI..."
    
    # Boutons navigation
    $script:UI.btnPrev = $script:Window.FindName('btnPrev')
    $script:UI.btnNext = $script:Window.FindName('btnNext')
    $script:UI.btnRun = $script:Window.FindName('btnRun')
    
    # RadioButtons mode
    $script:UI.RbExport = $script:Window.FindName('rbExport')
    $script:UI.RbImport = $script:Window.FindName('rbImport')
    
    # TextBoxes chemins
    $script:UI.TbExportDest = $script:Window.FindName('tbExportDest')
    $script:UI.TbClientName = $script:Window.FindName('tbClientName')
    $script:UI.TbImportSrc  = $script:Window.FindName('tbImportSrc')
    
    # Boutons parcourir
    $script:UI.BtnBrowseExport = $script:Window.FindName('btnPickExport')
    $script:UI.BtnBrowseImport = $script:Window.FindName('btnPickImport')
    
    # TreeViews
    $script:UI.TreeFolders = $script:Window.FindName('treeFolders')
    $script:UI.TreeAppData = $script:Window.FindName('treeAppData')
    
    # ListBox clients (page 21)
    $script:UI.lstClients = $script:Window.FindName('lstClients')
    $script:UI.btnBrowseClient = $script:Window.FindName('btnBrowseClient')
    
    # Checkboxes fonctionnalités
    $script:UI.CbWifi           = $script:Window.FindName('cbWifi')
    $script:UI.CbPrinters       = $script:Window.FindName('cbPrinters')
    $script:UI.CbPrinterDrivers = $script:Window.FindName('cbPrinterDrivers')
    $script:UI.CbNetDrives      = $script:Window.FindName('cbNetDrives')
    $script:UI.CbRDP            = $script:Window.FindName('cbRDP')
    $script:UI.CbWallpaper      = $script:Window.FindName('cbWallpaper')
    $script:UI.CbDesktopPos     = $script:Window.FindName('cbDesktopPos')
    $script:UI.CbTaskbar        = $script:Window.FindName('cbTaskbar')
    $script:UI.CbStartMenu      = $script:Window.FindName('cbStartMenu')
    $script:UI.CbQuickAccess    = $script:Window.FindName('cbQuickAccess')
    
    # Checkboxes navigateurs
    $script:UI.CbAppChrome  = $script:Window.FindName('cbAppChrome')
    $script:UI.CbAppEdge    = $script:Window.FindName('cbAppEdge')
    $script:UI.CbAppFirefox = $script:Window.FindName('cbAppFirefox')
    $script:UI.CbAppOutlook = $script:Window.FindName('cbAppOutlook')
    
    # Checkboxes options
    $script:UI.CbShowCached = $script:Window.FindName('cbShowHidden')   # "Afficher dossiers cachés"
    $script:UI.CbInstallApplications = $script:Window.FindName('cbInstallApplications')
    $script:UI.CbSkipCopy   = $script:Window.FindName('cbSkipCopy')
    $script:UI.CbFilterBig  = $script:Window.FindName('cbFilterBig')
    
    # Page passwords (mots de passe navigateurs)
    $script:UI.gridPwTiles = $script:Window.FindName('gridPwTiles')
    $script:UI.stackPwInstructions = $script:Window.FindName('stackPwInstructions')
    $script:UI.lblPwTitle = $script:Window.FindName('lblPwTitle')
    
    # Page applications (pageApps)
    $script:UI.lstAppsToInstall = $script:Window.FindName('lstAppsToInstall')
    $script:UI.lblAppsStatus = $script:Window.FindName('lblAppsStatus')
    $script:UI.lblAppsCount = $script:Window.FindName('lblAppsCount')
    $script:UI.btnAppsSelectAll = $script:Window.FindName('btnAppsSelectAll')
    $script:UI.btnAppsSelectNone = $script:Window.FindName('btnAppsSelectNone')
    
    # Page résumé
    $script:UI.TxtSummary   = $script:Window.FindName('txtSummary')
    
    # Page exécution
    $script:UI.ProgressBar  = $script:Window.FindName('progressBar')
    $script:UI.TxtProgress  = $script:Window.FindName('lblProgress')
    $script:UI.CbPlaySound  = $script:Window.FindName('cbPlaySound')
    $script:UI.ImgNyanCat   = $script:Window.FindName('imgNyanCat')

    # Page terminée
    $script:UI.TxtResult    = $script:Window.FindName('txtResult')  # n'existe pas (restera $null pour l'instant)
    $script:UI.BtnOpenLog   = $script:Window.FindName('hlLog')      # Hyperlink qui ouvre le log
    $script:UI.LblLogPath   = $script:Window.FindName('lblLogPath')
    $script:UI.BtnClose     = $script:Window.FindName('btnClose')

    # Grand logo de fond uniquement
    $script:UI.ImgLogoBg    = $script:Window.FindName('imgLogoBg')
    
    # Masquer contrôles indisponibles
    Hide-ConditionalControls
    
    Write-MWLogInfo "Contrôles UI initialisés"
}

function Initialize-UIHandlers {
    <#
    .SYNOPSIS
    Connecte tous les événements
    #>
    Write-MWLogInfo "Initialisation des handlers..."
    
    # Boutons navigation
    $script:UI.btnNext.Add_Click({
        Handle-NextClick
    })
    
    $script:UI.btnPrev.Add_Click({
        Handle-PreviousClick
    })
    
    $script:UI.btnRun.Add_Click({
        Handle-RunClick
    })
    
    # RadioButtons mode
    $script:UI.RbExport.Add_Checked({
        $script:IsExport = $true
        Reset-ImportVisibility -UIControls $script:UI
        Write-MWLogInfo "Mode EXPORT sélectionné"
    })
    
    $script:UI.RbImport.Add_Checked({
        $script:IsExport = $false
        Write-MWLogInfo "Mode IMPORT sélectionné"
    })
    
    # Boutons parcourir
    $script:UI.BtnBrowseExport.Add_Click({
        $path = Select-FolderDialog -Title "Sélectionner dossier d'export"
        if ($path) {
            $script:UI.TbExportDest.Text = $path
        }
    })
    
    $script:UI.BtnBrowseImport.Add_Click({
        $path = Select-FolderDialog -Title "Sélectionner dossier d'import"
        if ($path -and (Validate-ImportPath -Path $path)) {
            $script:UI.TbImportSrc.Text = $path
        }
    })
    
    # Bouton parcourir client (page 21)
    if ($script:UI.btnBrowseClient) {
        $script:UI.btnBrowseClient.Add_Click({
            $path = Select-FolderDialog -Title "Sélectionner dossier client"
            if ($path -and (Validate-ImportPath -Path $path)) {
                $script:UI.TbImportSrc.Text = $path
                Navigate-Next -Window $script:Window -IsExport $script:IsExport
            }
        })
    }
    
    # Bouton ouvrir log
    if ($script:UI.BtnOpenLog) {
        $script:UI.BtnOpenLog.Add_Click({
            $logPath = Get-MWLogPath
            if (Test-Path $logPath) {
                Start-Process notepad.exe -ArgumentList $logPath
            }
        })
    }
    
    # Bouton fermer
    if ($script:UI.BtnClose) {
        $script:UI.BtnClose.Add_Click({
            $script:Window.Close()
        })
    }
    
    # Boutons page Applications (pageApps)
    if ($script:UI.btnAppsSelectAll) {
        $script:UI.btnAppsSelectAll.Add_Click({
            Select-AllApplications -SelectAll $true
        })
    }
    
    if ($script:UI.btnAppsSelectNone) {
        $script:UI.btnAppsSelectNone.Add_Click({
            Select-AllApplications -SelectAll $false
        })
    }
    
    Write-MWLogInfo "Handlers initialisés"
}

function Initialize-UIData {
    <#
    .SYNOPSIS
    Remplit les données initiales
    #>
    Write-MWLogInfo "Initialisation des données UI..."
    
    # Chemin export par défaut
    $defaultExport = Get-DefaultExportPath
    if ($script:UI.TbExportDest) {
        $script:UI.TbExportDest.Text = $defaultExport
    }
    
    # Construire les arbres en mode Export
    if ($script:UI.TreeFolders) {
        Build-FoldersTree -TreeView $script:UI.TreeFolders -IsExport $true
    }
    
    if ($script:UI.TreeAppData) {
        Build-AppDataTree -TreeView $script:UI.TreeAppData
    }

    # Appliquer le logo de fond
    if ($script:UI.ImgLogoBg) {
        $logoImage = Get-MWLogoImageSource
        if ($logoImage) {
            $script:UI.ImgLogoBg.Source = $logoImage
        }
    }

    # Charger le GIF Nyan Cat pour l'animation
    if ($script:UI.ImgNyanCat) {
        $nyanImage = Get-MWNyanCatImageSource
        if ($nyanImage) {
            $script:UI.ImgNyanCat.Source = $nyanImage
            Write-MWLogInfo "Animation Nyan Cat chargée"
        }
    }

    # Initialiser les tuiles de navigateurs pour l'export de mots de passe
    Initialize-BrowserPasswordTiles
    
    Write-MWLogInfo "Données UI initialisées"
}

function Initialize-BrowserPasswordTiles {
    <#
    .SYNOPSIS
    Détecte les navigateurs installés et crée les tuiles cliquables avec vraies icônes
    #>
    if (-not $script:UI.ContainsKey('gridPwTiles')) {
        return
    }
    
    Write-MWLogInfo "Initialisation des tuiles de navigateurs..."
    
    $script:UI.gridPwTiles.Children.Clear()
    $script:UI.stackPwInstructions.Children.Clear()
    
    # Titre des instructions
    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = "💡 Comment exporter les mots de passe :"
    $titleBlock.FontWeight = 'Bold'
    $titleBlock.Margin = '0,0,0,12'
    $titleBlock.FontSize = 14
    $script:UI.stackPwInstructions.Children.Add($titleBlock) | Out-Null
    
    # Utiliser le module BrowserDetection pour détecter tous les navigateurs
    try {
        $browsersDetected = Get-MWInstalledBrowsers
        
        if (-not $browsersDetected -or $browsersDetected.Count -eq 0) {
            # Aucun navigateur détecté
            $noBtn = New-Object System.Windows.Controls.TextBlock
            $noBtn.Text = "❌ Aucun navigateur détecté"
            $noBtn.FontSize = 16
            $noBtn.Foreground = '#ffa500'
            $noBtn.HorizontalAlignment = 'Center'
            $noBtn.Margin = '0,20,0,20'
            $script:UI.gridPwTiles.Children.Add($noBtn) | Out-Null
            
            $instrBlock = New-Object System.Windows.Controls.TextBlock
            $instrBlock.Text = "Aucun navigateur n'a été détecté sur ce système."
            $instrBlock.TextWrapping = 'Wrap'
            $instrBlock.Margin = '0,8,0,0'
            $script:UI.stackPwInstructions.Children.Add($instrBlock) | Out-Null
            
            Write-MWLogInfo "Aucun navigateur détecté"
            return
        }
        
        Write-MWLogInfo "$($browsersDetected.Count) navigateur(s) détecté(s)"
        
        # Créer les tuiles pour chaque navigateur
        foreach ($browser in $browsersDetected) {
            $tile = New-Object System.Windows.Controls.Button
            $tile.Width = 180
            $tile.Height = 120
            $tile.Margin = '8'
            $tile.Background = '#263147'
            $tile.BorderBrush = '#3b4d6b'
            $tile.BorderThickness = '2'
            $tile.Cursor = 'Hand'
            
            $stack = New-Object System.Windows.Controls.StackPanel
            $stack.VerticalAlignment = 'Center'
            $stack.HorizontalAlignment = 'Center'
            
            # Extraire la vraie icône du navigateur
            $iconImage = Get-MWBrowserIcon -BrowserPath $browser.Path
            
            if ($iconImage) {
                # Utiliser la vraie icône
                $imgControl = New-Object System.Windows.Controls.Image
                $imgControl.Source = $iconImage
                $imgControl.Width = 48
                $imgControl.Height = 48
                $imgControl.HorizontalAlignment = 'Center'
                $imgControl.Margin = '0,0,0,8'
                $stack.Children.Add($imgControl) | Out-Null
            }
            else {
                # Fallback : utiliser un bloc de texte générique
                $iconBlock = New-Object System.Windows.Controls.TextBlock
                $iconBlock.Text = "🌐"
                $iconBlock.FontSize = 48
                $iconBlock.HorizontalAlignment = 'Center'
                $iconBlock.Margin = '0,0,0,8'
                $stack.Children.Add($iconBlock) | Out-Null
            }
            
            $nameBlock = New-Object System.Windows.Controls.TextBlock
            $nameBlock.Text = $browser.DisplayName
            $nameBlock.FontSize = 13
            $nameBlock.FontWeight = 'Bold'
            $nameBlock.Foreground = '#e8eefc'
            $nameBlock.HorizontalAlignment = 'Center'
            $nameBlock.TextWrapping = 'Wrap'
            $nameBlock.MaxWidth = 170
            
            $stack.Children.Add($nameBlock) | Out-Null
            $tile.Content = $stack
            
            # Événement clic : lancer le navigateur
            $browserPath = $browser.Path
            $tile.Add_Click({
                try {
                    Write-MWLogInfo "Lancement du navigateur : $browserPath"
                    Start-Process $browserPath
                }
                catch {
                    Write-MWLogError "Erreur lancement navigateur : $($_.Exception.Message)"
                    [System.Windows.MessageBox]::Show("Impossible de lancer le navigateur : $($_.Exception.Message)", "Erreur", 'OK', 'Error')
                }
            }.GetNewClosure())
            
            $script:UI.gridPwTiles.Children.Add($tile) | Out-Null
            
            # Ajouter les instructions adaptées au navigateur
            if ($browser.Instructions) {
                $instrBlock = New-Object System.Windows.Controls.TextBlock
                $instrBlock.Text = "`n=== $($browser.DisplayName) ===`n$($browser.Instructions)"
                $instrBlock.TextWrapping = 'Wrap'
                $instrBlock.Margin = '0,8,0,16'
                $instrBlock.FontSize = 12
                $script:UI.stackPwInstructions.Children.Add($instrBlock) | Out-Null
            }
        }
        
        Write-MWLogInfo "Tuiles de navigateurs initialisées avec succès"
        
    }
    catch {
        Write-MWLogError "Erreur lors de l'initialisation des tuiles navigateurs : $($_.Exception.Message)"
        
        # Afficher un message d'erreur dans l'UI
        $errorBlock = New-Object System.Windows.Controls.TextBlock
        $errorBlock.Text = "⚠️ Erreur lors de la détection des navigateurs"
        $errorBlock.FontSize = 16
        $errorBlock.Foreground = '#ff4444'
        $errorBlock.HorizontalAlignment = 'Center'
        $errorBlock.Margin = '0,20,0,20'
        $script:UI.gridPwTiles.Children.Add($errorBlock) | Out-Null
    }
}

function Initialize-ApplicationsPage {
    <#
    .SYNOPSIS
    Initialise la page Applications avec la liste des logiciels manquants à réinstaller
    #>
    if (-not $script:UI.lstAppsToInstall) {
        Write-MWLogWarning "lstAppsToInstall non trouvé"
        return
    }
    
    Write-MWLogInfo "Analyse des applications manquantes..."
    
    $script:UI.lblAppsStatus.Text = "Analyse en cours..."
    $script:UI.lstAppsToInstall.Items.Clear()
    
    try {
        # Récupérer le dossier source
        $importFolder = $script:UI.TbImportSrc.Text
        
        if (-not $importFolder -or -not (Test-Path $importFolder)) {
            $script:UI.lblAppsStatus.Text = "❌ Dossier d'import non valide"
            return
        }

        # Charger le manifest d'export
        $manifestPath = Join-Path $importFolder "ExportManifest.json"
        if (-not (Test-Path $manifestPath)) {
            $script:UI.lblAppsStatus.Text = "❌ Fichier ExportManifest.json introuvable"
            $script:UI.lblAppsCount.Text = "0 application à installer"
            return
        }

        $snapshot = Import-MWExportSnapshot -Path $manifestPath

        if (-not $snapshot.Applications -or $snapshot.Applications.Count -eq 0) {
            $script:UI.lblAppsStatus.Text = "✅ Aucune application dans l'export"
            $script:UI.lblAppsCount.Text = "0 application à installer"
            return
        }

        # Chercher les applications manquantes
        $missingApps = Get-MWMissingApplicationsFromExport -ExportedApplications $snapshot.Applications
        
        if (-not $missingApps -or $missingApps.Count -eq 0) {
            $script:UI.lblAppsStatus.Text = "✅ Toutes les applications sont déjà installées"
            $script:UI.lblAppsCount.Text = "0 application à installer"
            return
        }
        
        $script:UI.lblAppsStatus.Text = "Applications manquantes détectées :"
        $script:UI.lblAppsCount.Text = "$($missingApps.Count) application(s) à installer"
        
        foreach ($app in $missingApps) {
            $item = [PSCustomObject]@{
                DisplayName = $app.DisplayName
                Publisher = if ($app.Publisher) { $app.Publisher } else { "Éditeur inconnu" }
                Source = if ($app.WingetId) { "winget" } elseif ($app.RuckZuckId) { "RuckZuck" } else { "Manuel" }
                SourceColor = if ($app.WingetId) { "#0078D4" } elseif ($app.RuckZuckId) { "#107C10" } else { "#666666" }
                Selected = $true
                WingetId = $app.WingetId
                RuckZuckId = $app.RuckZuckId
            }
            $script:UI.lstAppsToInstall.Items.Add($item) | Out-Null
        }
        
        Write-MWLogInfo "$($missingApps.Count) application(s) manquante(s) détectée(s)"
        
    }
    catch {
        Write-MWLogError "Erreur analyse applications : $($_.Exception.Message)"
        $script:UI.lblAppsStatus.Text = "⚠️ Erreur lors de l'analyse"
    }
}

function Select-AllApplications {
    <#
    .SYNOPSIS
    Sélectionne ou désélectionne toutes les applications
    #>
    param([bool]$SelectAll)
    
    if (-not $script:UI.lstAppsToInstall) { return }
    
    foreach ($item in $script:UI.lstAppsToInstall.Items) {
        $item.Selected = $SelectAll
    }
    
    # Forcer le rafraîchissement
    $script:UI.lstAppsToInstall.Items.Refresh()
}

function Update-PasswordPageTitle {
    <#
    .SYNOPSIS
    Met à jour le titre de la page mots de passe selon le mode
    #>
    if (-not $script:UI.lblPwTitle) { return }
    
    if ($script:IsExport) {
        $script:UI.lblPwTitle.Text = "🔒 Export des mots de passe navigateurs"
    }
    else {
        $script:UI.lblPwTitle.Text = "🔓 Import des mots de passe navigateurs"
    }
}

function Update-ProgressUI {
    <#
    .SYNOPSIS
    Met à jour l'UI de progression
    #>
    param(
        [string]$Message,
        [int]$Percent = -1
    )

    if ($script:UI.TxtProgress -and $Message) {
        # lblProgress est un Label, donc utilise Content et non Text
        $script:UI.TxtProgress.Content = $Message
    }

    if ($script:UI.ProgressBar -and $Percent -ge 0) {
        $script:UI.ProgressBar.Value = $Percent
    }

    # Forcer le rafraîchissement UI (WPF)
    if ($script:Window) {
        $script:Window.Dispatcher.Invoke([action]{}, 'Background')
    }
}

function Invoke-MWCompletionSound {
    <#
    .SYNOPSIS
    Joue une mélodie de victoire à la fin de la migration (si l'option est cochée)
    #>
    try {
        # FIX: Utiliser [Console]::Beep() pour une vraie mélodie personnalisée
        # Mélodie de victoire style "Tadaaaa!" (notes: Mi-Sol-Do-Mi-Sol)

        [Console]::Beep(659, 200)   # Mi (E5)
        Start-Sleep -Milliseconds 50
        [Console]::Beep(784, 200)   # Sol (G5)
        Start-Sleep -Milliseconds 50
        [Console]::Beep(1047, 200)  # Do (C6)
        Start-Sleep -Milliseconds 50
        [Console]::Beep(1319, 400)  # Mi (E6)
        Start-Sleep -Milliseconds 100
        [Console]::Beep(1047, 600)  # Do (C6) - note finale prolongée
    }
    catch {
        Write-MWLogWarning "Impossible de jouer le son de fin : $($_.Exception.Message)"

        # Fallback: utiliser les sons système si Console.Beep échoue
        try {
            [System.Media.SystemSounds]::Asterisk.Play()
        } catch {
            # Silencieux si même le fallback échoue
        }
    }
}

function Handle-NextClick {
    <#
    .SYNOPSIS
    Gère le clic sur Suivant
    #>
    $currentPage = Get-CurrentPage
    
    Write-MWLogInfo "Navigation Suivant depuis page $currentPage"
    
    # ========================================
    # PAGE 1 → PAGE 21 (Import) ou PAGE 2 (Export)
    # ========================================
    if ($currentPage -eq 1) {
        if (-not $script:IsExport) {
            # Mode Import : Remplir la liste des clients avant d'afficher page21
            Fill-ClientsList
        }
    }
    
    # ========================================
    # PAGE 2 → Prépar résumé + Titre passwords (pas de validation ici)
    # ========================================
    if ($currentPage -eq 2) {
        # Préparer résumé (construction rapide, pas de scan de fichiers)
        $summaryText = Build-SummaryText -IsExport $script:IsExport -UIControls $script:UI -TreeFolders $script:UI.TreeFolders -TreeAppData $script:UI.TreeAppData
        $script:UI.TxtSummary.Text = $summaryText

        # Mettre à jour le titre de la page passwords
        Update-PasswordPageTitle
    }
    
    # ========================================
    # PAGE 21 → Validation client sélectionné + Init Apps
    # ========================================
    if ($currentPage -eq 21) {
        # Page sélection client
        if ($script:UI.lstClients.SelectedItem) {
            $client = $script:UI.lstClients.SelectedItem

            # Vérifier que le client sélectionné est valide (pas le message d'erreur)
            if ($client.FolderPath -and (Test-Path $client.FolderPath)) {
                $script:UI.TbImportSrc.Text = $client.FolderPath
                Write-MWLogInfo "Client sélectionné : $($client.FolderName)"

                # Initialiser la page Applications (analyse des apps manquantes)
                Initialize-ApplicationsPage
            }
            else {
                # Aucun client valide sélectionné (message d'erreur ou invalide)
                [System.Windows.MessageBox]::Show("Veuillez parcourir manuellement pour sélectionner un dossier d'export.", "Aucun export détecté", 'OK', 'Warning')
                return
            }
        }
        else {
            [System.Windows.MessageBox]::Show("Veuillez sélectionner un client ou parcourir manuellement.", "Aucune sélection", 'OK', 'Warning')
            return
        }
    }
    
    # ========================================
    # PAGE 22 (Apps) → Appliquer manifest pour page 2
    # ========================================
    if ($currentPage -eq 22) {
        $path = $script:UI.TbImportSrc.Text
        if ($path -and (Test-Path $path)) {
            # Lire et appliquer manifest pour les options
            $manifest = Read-ExportManifest -ImportFolder $path
            Apply-ImportManifest -Manifest $manifest -UIControls $script:UI
        }
    }
    
    # Navigation
    Navigate-Next -Window $script:Window -IsExport $script:IsExport
}

function Handle-PreviousClick {
    <#
    .SYNOPSIS
    Gère le clic sur Précédent
    #>
    Navigate-Previous -Window $script:Window -IsExport $script:IsExport
}

function Handle-RunClick {
    <#
    .SYNOPSIS
    Lance l'export ou import
    #>
    Write-MWLogInfo "=== Lancement migration ==="

    # Passer à la page d'exécution
    Show-UIPage -PageNumber 4 -Window $script:Window

    # Empêcher mise en veille
    Prevent-SystemSleep
    
    # Récupérer options sélectionnées
    $options = Get-SelectedOptions -UIControls $script:UI -TreeFolders $script:UI.TreeFolders -TreeAppData $script:UI.TreeAppData
    
    try {
        if ($script:IsExport) {
            Write-MWLogInfo "Démarrage EXPORT..."

            # Construire le chemin final : dossier de base + nom du client + nom PC
            $basePath = $script:UI.TbExportDest.Text
            $clientName = $script:UI.TbClientName.Text

            if ([string]::IsNullOrWhiteSpace($clientName)) {
                $clientName = "Client_$(Get-Date -Format 'yyyy-MM-dd')"
            }

            # Ajouter le nom du PC dans un sous-dossier
            $pcName = $env:COMPUTERNAME
            $clientPath = Join-Path $basePath $clientName
            $finalPath = Join-Path $clientPath $pcName

            Write-MWLogInfo "Structure hiérarchique : $basePath\$clientName\$pcName"
            Write-MWLogInfo "Chemin final d'export : $finalPath"

            # Créer le dossier client si nécessaire
            if (-not (Test-Path $clientPath)) {
                New-Item -ItemType Directory -Path $clientPath -Force | Out-Null
                Write-MWLogInfo "Dossier client créé : $clientPath"
            }

            # Détecter si export existe déjà (même PC)
            $incrementalMode = $false
            $pathAlreadyValidated = $false

            if (Test-Path $finalPath) {
                $manifestPath = Join-Path $finalPath "ExportManifest.json"
                if (Test-Path $manifestPath) {
                    try {
                        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                        $previousPC = $manifest.ExportMetadata.ComputerName

                        # Même PC détecté
                        if ($previousPC -eq $env:COMPUTERNAME) {
                            Write-MWLogInfo "Export existant détecté sur le même PC : $previousPC"

                            # Proposer mode incrémental
                            $result = [System.Windows.MessageBox]::Show(
                                "Un export existe déjà pour ce PC.`n`n" +
                                "✅ Mise à jour (recommandé) : Copie uniquement les fichiers modifiés = SUPER RAPIDE`n" +
                                "❌ Export complet : Réexporte tout (écrase l'existant)`n`n" +
                                "Voulez-vous faire une MISE À JOUR incrémentale ?",
                                "Export existant détecté",
                                [System.Windows.MessageBoxButton]::YesNoCancel,
                                [System.Windows.MessageBoxImage]::Question
                            )

                            if ($result -eq [System.Windows.MessageBoxResult]::Cancel) {
                                Write-MWLogWarning "Export annulé par l'utilisateur"
                                Allow-SystemSleep
                                return
                            }
                            elseif ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                                $incrementalMode = $true
                                $pathAlreadyValidated = $true  # Pas besoin de revalider
                                Write-MWLogInfo "Mode MISE À JOUR INCRÉMENTALE activé"
                            }
                            else {
                                $pathAlreadyValidated = $true  # Pas besoin de revalider
                                Write-MWLogInfo "Mode EXPORT COMPLET choisi"
                            }
                        }
                    }
                    catch {
                        Write-MWLogWarning "Erreur lecture manifest existant : $($_.Exception.Message)"
                    }
                }
            }

            # Valider le chemin final (uniquement si pas déjà validé)
            if (-not $pathAlreadyValidated -and -not (Validate-ExportPath -Path $finalPath -ShowError $true)) {
                Write-MWLogWarning "Export annulé par l'utilisateur"
                Allow-SystemSleep
                return
            }

            # Déterminer si on exporte des dossiers utilisateur
            $includeUserData = ($options.Folders -and $options.Folders.Count -gt 0)

            $params = @{
                DestinationFolder    = $finalPath
                IncludeUserData      = $includeUserData
                SelectedFolders      = $options.Folders
                IncludeWifi          = $options.Wifi
                IncludePrinters      = $options.Printers
                IncludeNetworkDrives = $options.NetworkDrives
                IncludeRdp           = $options.Rdp
                IncludeChrome        = $options.Chrome
                IncludeEdge          = $options.Edge
                IncludeFirefox       = $options.Firefox
                IncludeOutlook       = $options.Outlook
                IncludeWallpaper     = $options.Wallpaper
                IncludeDesktopLayout = $options.DesktopLayout
                IncludeTaskbarStart  = $options.Taskbar
                IncludeQuickAccess   = $options.QuickAccess
                IncrementalMode      = $incrementalMode
            }

            Export-MWProfile @params

            if ($script:UI.TxtResult) {
                $script:UI.TxtResult.Text = "✅ Export terminé avec succès !`n`nDossier : $finalPath"
            }
        }
        else {
            Write-MWLogInfo "Démarrage IMPORT..."
            
            # ========================================
            # ÉTAPE 1 : Installer les applications sélectionnées
            # ========================================
            if ($options.InstallApplications -and $script:UI.lstAppsToInstall -and $script:UI.lstAppsToInstall.Items.Count -gt 0) {
                $appsToInstall = $script:UI.lstAppsToInstall.Items | Where-Object { $_.Selected }
                if ($appsToInstall.Count -gt 0) {
                    Write-MWLogInfo "Installation de $($appsToInstall.Count) application(s)..."
                    Update-ProgressUI -Message "Installation des applications..." -Percent 5
                    
                    foreach ($app in $appsToInstall) {
                        try {
                            Write-MWLogInfo "Installation : $($app.DisplayName)"
                            Update-ProgressUI -Message "Installation : $($app.DisplayName)" -Percent 10
                            
                            if ($app.WingetId) {
                                # Installer via winget
                                $result = winget install --id $app.WingetId --silent --accept-source-agreements --accept-package-agreements 2>&1
                                Write-MWLogInfo "winget: $result"
                            }
                            elseif ($app.RuckZuckId) {
                                # Installer via RuckZuck
                                $rzPath = Get-MWRuckZuckPath
                                if ($rzPath -and (Test-Path $rzPath)) {
                                    & $rzPath install "$($app.RuckZuckId)" | Out-Null
                                }
                            }
                        }
                        catch {
                            Write-MWLogWarning "Échec installation $($app.DisplayName): $($_.Exception.Message)"
                        }
                    }
                }
            }
            else {
                if (-not $options.InstallApplications) {
                    Write-MWLogInfo "Installation d'applications désactivée par l'utilisateur"
                }
            }

            # ========================================
            # ÉTAPE 2 : Restaurer les données
            # ========================================
            Write-MWLogInfo "Restauration des données..."
            Update-ProgressUI -Message "Restauration des données..." -Percent 30
            
$params = @{
                SourceFolder         = $script:UI.TbImportSrc.Text
                IncludeUserData      = $true
                IncludeWifi          = $options.Wifi
                IncludePrinters      = $options.Printers
                IncludeNetworkDrives = $options.NetworkDrives
                IncludeRdp           = $options.Rdp
                IncludeChrome        = $options.Chrome
                IncludeEdge          = $options.Edge
                IncludeFirefox       = $options.Firefox
                IncludeOutlook       = $options.Outlook
                IncludeWallpaper     = $options.Wallpaper
                IncludeDesktopLayout = $options.DesktopLayout
                IncludeTaskbarStart  = $options.Taskbar
                IncludeQuickAccess   = $options.QuickAccess
            }
            
            Import-MWProfile @params
            
            if ($script:UI.TxtResult) {
                $script:UI.TxtResult.Text = "✅ Import terminé avec succès !"
            }
        }
        
        Write-MWLogInfo "Migration terminée avec succès"
    }
    catch {
        Write-MWLogError "Erreur migration : $($_.Exception.Message)"
        if ($script:UI.TxtResult) {
            $script:UI.TxtResult.Text = "❌ Erreur durant la migration :`n`n$($_.Exception.Message)"
        }
    }
    finally {
        Allow-SystemSleep

        # Jouer le son de fin si l'option est cochée
        if ($script:UI.CbPlaySound -and $script:UI.CbPlaySound.IsChecked) {
            Invoke-MWCompletionSound
        }

        # Afficher le chemin du log si le label existe
        $logPath = Get-MWLogPath
        if ($script:UI.LblLogPath -and $logPath) {
            $props = $script:UI.LblLogPath.PSObject.Properties
            if ($props.Match('Text').Count -gt 0) {
                $script:UI.LblLogPath.Text = $logPath
            }
            elseif ($props.Match('Content').Count -gt 0) {
                $script:UI.LblLogPath.Content = $logPath
            }
        }

        # CORRECTION: Pour Import, afficher d'abord page passwords, puis page terminée
        if (-not $script:IsExport) {
            Show-UIPage -PageNumber 20 -Window $script:Window -IsExport $script:IsExport
        } else {
            Show-UIPage -PageNumber 5 -Window $script:Window
        }
    }

}
# Export de la fonction principale
Export-ModuleMember -Function Start-MWMigrationWizardUI
