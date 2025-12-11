# ==============================================================================
# SummaryBuilder.psm1
# Module de construction de la page résumé
# ==============================================================================

function Build-SummaryText {
    <#
    .SYNOPSIS
    Construit le texte du résumé
    .PARAMETER IsExport
    Mode Export ou Import
    .PARAMETER UIControls
    Hashtable des contrôles UI
    .PARAMETER TreeFolders
    TreeView des dossiers
    .PARAMETER TreeAppData
    TreeView AppData
    .OUTPUTS
    Texte formaté du résumé
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [bool]$IsExport,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$UIControls,
        
        [Parameter(Mandatory=$false)]
        $TreeFolders,
        
        [Parameter(Mandatory=$false)]
        $TreeAppData
    )
    
    $lines = [System.Collections.Generic.List[string]]::new()
    
    # En-tête
    if ($IsExport) {
        $lines.Add("═══ RÉSUMÉ DE L'EXPORT ═══")
        $lines.Add("")
        $lines.Add("📁 Destination : $($UIControls.TbExportDest.Text)")
    }
    else {
        $lines.Add("═══ RÉSUMÉ DE L'IMPORT ═══")
        $lines.Add("")
        $lines.Add("📁 Source : $($UIControls.TbImportSrc.Text)")
    }
    
    $lines.Add("")
    $lines.Add("─── Dossiers utilisateur ───")
    
    # Dossiers sélectionnés
    if ($TreeFolders) {
        $selectedFolders = Get-SelectedFoldersFromTree -TreeView $TreeFolders
        
        if ($selectedFolders.Count -gt 0) {
            foreach ($folder in $selectedFolders) {
                $folderName = Split-Path $folder -Leaf
                $lines.Add("  ✓ $folderName")
            }
        }
        else {
            $lines.Add("  (aucun dossier sélectionné)")
        }
    }
    
    # AppData
    if ($TreeAppData) {
        $appDataSelection = Get-AppDataSelectionFromTree -TreeView $TreeAppData
        
        if ($appDataSelection.Local -or $appDataSelection.Roaming) {
            $lines.Add("")
            $lines.Add("─── AppData ───")
            
            if ($appDataSelection.Local) {
                $lines.Add("  ✓ AppData\Local")
            }
            if ($appDataSelection.Roaming) {
                $lines.Add("  ✓ AppData\Roaming")
            }
        }
    }
    
    # Fonctionnalités Windows
    $windowsFeatures = @()
    
    if ($UIControls.ContainsKey('CbWifi') -and $UIControls.CbWifi.Visibility -eq 'Visible' -and $UIControls.CbWifi.IsChecked) {
        $windowsFeatures += "Wi-Fi"
    }
    if ($UIControls.ContainsKey('CbPrinters') -and $UIControls.CbPrinters.Visibility -eq 'Visible' -and $UIControls.CbPrinters.IsChecked) {
        $windowsFeatures += "Imprimantes"
    }
    if ($UIControls.ContainsKey('CbPrinterDrivers') -and $UIControls.CbPrinterDrivers.Visibility -eq 'Visible' -and $UIControls.CbPrinterDrivers.IsChecked) {
        $windowsFeatures += "Pilotes d'imprimantes"
    }
    if ($UIControls.ContainsKey('CbNetDrives') -and $UIControls.CbNetDrives.Visibility -eq 'Visible' -and $UIControls.CbNetDrives.IsChecked) {
        $windowsFeatures += "Lecteurs réseau"
    }
    if ($UIControls.ContainsKey('CbRDP') -and $UIControls.CbRDP.Visibility -eq 'Visible' -and $UIControls.CbRDP.IsChecked) {
        $windowsFeatures += "Connexions RDP"
    }
    if ($UIControls.ContainsKey('CbWallpaper') -and $UIControls.CbWallpaper.Visibility -eq 'Visible' -and $UIControls.CbWallpaper.IsChecked) {
        $windowsFeatures += "Fond d'écran"
    }
    if ($UIControls.ContainsKey('CbDesktopPos') -and $UIControls.CbDesktopPos.Visibility -eq 'Visible' -and $UIControls.CbDesktopPos.IsChecked) {
        $windowsFeatures += "Positions icônes"
    }
    if ($UIControls.ContainsKey('CbTaskbar') -and $UIControls.CbTaskbar.Visibility -eq 'Visible' -and $UIControls.CbTaskbar.IsChecked) {
        $windowsFeatures += "Barre des tâches"
    }
    if ($UIControls.ContainsKey('CbStartMenu') -and $UIControls.CbStartMenu.Visibility -eq 'Visible' -and $UIControls.CbStartMenu.IsChecked) {
        $windowsFeatures += "Menu Démarrer"
    }
    if ($UIControls.ContainsKey('CbQuickAccess') -and $UIControls.CbQuickAccess.Visibility -eq 'Visible' -and $UIControls.CbQuickAccess.IsChecked) {
        $windowsFeatures += "Accès rapide"
    }
    
    if ($windowsFeatures.Count -gt 0) {
        $lines.Add("")
        $lines.Add("─── Fonctionnalités Windows ───")
        foreach ($feature in $windowsFeatures) {
            $lines.Add("  ✓ $feature")
        }
    }
    
    # Navigateurs & Email
    $browsers = @()
    
    if ($UIControls.ContainsKey('CbAppChrome') -and $UIControls.CbAppChrome.Visibility -eq 'Visible' -and $UIControls.CbAppChrome.IsChecked) {
        $browsers += "Chrome"
    }
    if ($UIControls.ContainsKey('CbAppEdge') -and $UIControls.CbAppEdge.Visibility -eq 'Visible' -and $UIControls.CbAppEdge.IsChecked) {
        $browsers += "Edge"
    }
    if ($UIControls.ContainsKey('CbAppFirefox') -and $UIControls.CbAppFirefox.Visibility -eq 'Visible' -and $UIControls.CbAppFirefox.IsChecked) {
        $browsers += "Firefox"
    }
    if ($UIControls.ContainsKey('CbAppOutlook') -and $UIControls.CbAppOutlook.Visibility -eq 'Visible' -and $UIControls.CbAppOutlook.IsChecked) {
        $browsers += "Outlook"
    }
    
    if ($browsers.Count -gt 0) {
        $lines.Add("")
        $lines.Add("─── Navigateurs & Email ───")
        foreach ($browser in $browsers) {
            $lines.Add("  ✓ $browser AppData")
        }
    }
    
    # Options
    $options = @()
    
    if ($UIControls.ContainsKey('CbShowCached') -and $UIControls.CbShowCached.IsChecked) {
        $options += "Afficher dossiers cachés"
    }
    if ($UIControls.ContainsKey('CbSkipCopy') -and $UIControls.CbSkipCopy.IsChecked) {
        $options += "Ne pas copier de fichiers"
    }
    if ($UIControls.ContainsKey('CbFilterBig') -and $UIControls.CbFilterBig.IsChecked) {
        $options += "Exclure ISO/VM/archives"
    }
    
    if ($options.Count -gt 0) {
        $lines.Add("")
        $lines.Add("─── Options ───")
        foreach ($option in $options) {
            $lines.Add("  ✓ $option")
        }
    }
    
    return ($lines -join "`r`n")
}

function Get-SelectedFoldersFromTree {
    <#
    .SYNOPSIS
    Récupère les dossiers cochés dans un TreeView
    .PARAMETER TreeView
    TreeView à analyser
    .OUTPUTS
    Liste des chemins
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView
    )
    
    $script:selectedFolders = @()

    function Get-CheckedItems {
        param($Items)

        foreach ($item in $Items) {
            if ($item -is [System.Windows.Controls.TreeViewItem]) {
                $chk = $item.Header
                # CORRECTION: Accepter $true ET $null (indéterminé), mais PAS $false
                if ($chk -is [System.Windows.Controls.CheckBox] -and $chk.IsChecked -ne $false) {
                    # Si coché complètement ($true), ajouter ce dossier
                    if ($chk.IsChecked -eq $true -and $chk.Tag -and $chk.Tag.Path) {
                        $script:selectedFolders += $chk.Tag.Path
                        Write-MWLogInfo "Dossier sélectionné détecté: $($chk.Tag.Path)"
                    }
                }

                # TOUJOURS parcourir les enfants pour trouver les items cochés
                if ($item.Items.Count -gt 0) {
                    Get-CheckedItems -Items $item.Items
                }
            }
        }
    }

    Get-CheckedItems -Items $TreeView.Items

    Write-MWLogInfo "Get-SelectedFoldersFromTree: $($script:selectedFolders.Count) dossier(s) sélectionné(s)"
    return $script:selectedFolders
}

function Get-AppDataSelectionFromTree {
    <#
    .SYNOPSIS
    Récupère la sélection AppData depuis le TreeView
    .PARAMETER TreeView
    TreeView AppData
    .OUTPUTS
    Hashtable avec Local et Roaming
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView
    )
    
    $result = @{
        Local = $false
        Roaming = $false
    }
    
    foreach ($item in $TreeView.Items) {
        if ($item -is [System.Windows.Controls.TreeViewItem]) {
            $chk = $item.Header
            if ($chk -is [System.Windows.Controls.CheckBox]) {
                $label = $chk.Content
                if ($label -like '*Local*') {
                    $result.Local = [bool]$chk.IsChecked
                }
                elseif ($label -like '*Roaming*') {
                    $result.Roaming = [bool]$chk.IsChecked
                }
            }
        }
    }
    
    return $result
}

function Get-SelectedOptions {
    <#
    .SYNOPSIS
    Récupère toutes les options sélectionnées pour l'export/import
    .PARAMETER UIControls
    Hashtable des contrôles
    .PARAMETER TreeFolders
    TreeView dossiers
    .PARAMETER TreeAppData
    TreeView AppData
    .OUTPUTS
    Hashtable des options sélectionnées
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UIControls,
        
        [Parameter(Mandatory=$false)]
        $TreeFolders,
        
        [Parameter(Mandatory=$false)]
        $TreeAppData
    )
    
    $options = @{
        Folders = @()
        AppDataLocal = $false
        AppDataRoaming = $false
        Wifi = $false
        Printers = $false
        PrinterDrivers = $false
        NetworkDrives = $false
        Rdp = $false
        Wallpaper = $false
        DesktopLayout = $false
        Taskbar = $false
        StartMenu = $false
        QuickAccess = $false
        Chrome = $false
        Edge = $false
        Firefox = $false
        Outlook = $false
        SkipCopy = $false
        FilterBig = $false
    }
    
    # Dossiers
    if ($TreeFolders) {
        $options.Folders = Get-SelectedFoldersFromTree -TreeView $TreeFolders
    }
    
    # AppData
    if ($TreeAppData) {
        $appData = Get-AppDataSelectionFromTree -TreeView $TreeAppData
        $options.AppDataLocal = $appData.Local
        $options.AppDataRoaming = $appData.Roaming
    }
    
    # Checkboxes
    if ($UIControls.ContainsKey('CbWifi')) { $options.Wifi = [bool]$UIControls.CbWifi.IsChecked }
    if ($UIControls.ContainsKey('CbPrinters')) { $options.Printers = [bool]$UIControls.CbPrinters.IsChecked }
    if ($UIControls.ContainsKey('CbPrinterDrivers')) { $options.PrinterDrivers = [bool]$UIControls.CbPrinterDrivers.IsChecked }
    if ($UIControls.ContainsKey('CbNetDrives')) { $options.NetworkDrives = [bool]$UIControls.CbNetDrives.IsChecked }
    if ($UIControls.ContainsKey('CbRDP')) { $options.Rdp = [bool]$UIControls.CbRDP.IsChecked }
    if ($UIControls.ContainsKey('CbWallpaper')) { $options.Wallpaper = [bool]$UIControls.CbWallpaper.IsChecked }
    if ($UIControls.ContainsKey('CbDesktopPos')) { $options.DesktopLayout = [bool]$UIControls.CbDesktopPos.IsChecked }
    if ($UIControls.ContainsKey('CbTaskbar')) { $options.Taskbar = [bool]$UIControls.CbTaskbar.IsChecked }
    if ($UIControls.ContainsKey('CbStartMenu')) { $options.StartMenu = [bool]$UIControls.CbStartMenu.IsChecked }
    if ($UIControls.ContainsKey('CbQuickAccess')) { $options.QuickAccess = [bool]$UIControls.CbQuickAccess.IsChecked }
    if ($UIControls.ContainsKey('CbAppChrome')) { $options.Chrome = [bool]$UIControls.CbAppChrome.IsChecked }
    if ($UIControls.ContainsKey('CbAppEdge')) { $options.Edge = [bool]$UIControls.CbAppEdge.IsChecked }
    if ($UIControls.ContainsKey('CbAppFirefox')) { $options.Firefox = [bool]$UIControls.CbAppFirefox.IsChecked }
    if ($UIControls.ContainsKey('CbAppOutlook')) { $options.Outlook = [bool]$UIControls.CbAppOutlook.IsChecked }
    if ($UIControls.ContainsKey('CbInstallApplications')) { $options.InstallApplications = [bool]$UIControls.CbInstallApplications.IsChecked }
    if ($UIControls.ContainsKey('CbSkipCopy')) { $options.SkipCopy = [bool]$UIControls.CbSkipCopy.IsChecked }
    if ($UIControls.ContainsKey('CbFilterBig')) { $options.FilterBig = [bool]$UIControls.CbFilterBig.IsChecked }
    
    return $options
}

# Export des fonctions
Export-ModuleMember -Function @(
    'Build-SummaryText',
    'Get-SelectedFoldersFromTree',
    'Get-AppDataSelectionFromTree',
    'Get-SelectedOptions'
)
