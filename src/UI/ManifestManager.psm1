# ==============================================================================
# ManifestManager.psm1
# Module de gestion des manifests d'export/import
# ==============================================================================

function Read-ExportManifest {
    <#
    .SYNOPSIS
    Lit le manifest d'export depuis un dossier
    .PARAMETER ImportFolder
    Chemin du dossier contenant l'export
    .OUTPUTS
    Objet manifest ou $null si non trouvé/invalide
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImportFolder
    )
    
    $manifestPath = Join-Path $ImportFolder "ExportManifest.json"
    
    if (-not (Test-Path $manifestPath)) {
        Write-MWLogWarning "ExportManifest.json introuvable - Mode import classique"
        return $null
    }
    
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-MWLogInfo "Manifest d'export lu avec succès"
        return $manifest
    }
    catch {
        Write-MWLogError "Erreur lecture manifest : $($_.Exception.Message)"
        return $null
    }
}

function Create-ExportManifest {
    <#
    .SYNOPSIS
    Crée le manifest d'export avec toutes les options exportées
    .PARAMETER DestinationFolder
    Dossier où créer le manifest
    .PARAMETER ExportedItems
    Hashtable des options exportées
    .OUTPUTS
    Chemin du manifest créé ou $null si erreur
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$ExportedItems
    )
    
    try {
        # Récupérer la liste des applications installées avec RZGet
        $apps = @()
        try {
            $cmd = Get-Command -Name Get-MWApplicationsForExport -ErrorAction SilentlyContinue
            if ($null -ne $cmd) {
                $apps = Get-MWApplicationsForExport
                Write-MWLogInfo "Applications détectées pour export : $($apps.Count)"
            }
            else {
                Write-MWLogWarning "Get-MWApplicationsForExport non disponible, section Applications vide."
            }
        }
        catch {
            Write-MWLogWarning "Erreur récupération applications : $($_.Exception.Message)"
        }

        $manifest = [pscustomobject]@{
            ExportMetadata = @{
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                Domain       = $env:USERDOMAIN
                Date         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                OsVersion    = [System.Environment]::OSVersion.VersionString
            }
            ExportedItems = $ExportedItems
            Applications  = $apps
        }

        $manifestPath = Join-Path $DestinationFolder 'ExportManifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8

        Write-MWLogInfo "Manifest d'export créé : $manifestPath ($($apps.Count) applications)"
        return $manifestPath
    }
    catch {
        Write-MWLogWarning "Impossible de créer ExportManifest.json : $($_.Exception.Message)"
        return $null
    }
}

function Apply-ImportManifest {
    <#
    .SYNOPSIS
    Applique le manifest : masque les options non exportées, coche celles exportées
    .PARAMETER Manifest
    Objet manifest lu depuis Read-ExportManifest
    .PARAMETER UIControls
    Hashtable des contrôles UI à modifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [object]$Manifest,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$UIControls
    )
    
    if (-not $Manifest) {
        Write-MWLogInfo "Pas de manifest - Affichage de toutes les options"
        return
    }
    
    $exported = $Manifest.ExportedItems
    
    # Fonctionnalités Windows
    if ($UIControls.ContainsKey('CbWifi')) {
        if (-not $exported.Wifi) {
            $UIControls.CbWifi.Visibility = 'Collapsed'
        } else {
            $UIControls.CbWifi.Visibility = 'Visible'
            $UIControls.CbWifi.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbPrinters')) {
        if (-not $exported.Printers) {
            $UIControls.CbPrinters.Visibility = 'Collapsed'
            if ($UIControls.ContainsKey('CbPrinterDrivers')) {
                $UIControls.CbPrinterDrivers.Visibility = 'Collapsed'
            }
        } else {
            $UIControls.CbPrinters.Visibility = 'Visible'
            $UIControls.CbPrinters.IsChecked = $true
            if ($UIControls.ContainsKey('CbPrinterDrivers')) {
                $UIControls.CbPrinterDrivers.Visibility = 'Visible'
            }
        }
    }
    
    if ($UIControls.ContainsKey('CbNetDrives')) {
        if (-not $exported.NetworkDrives) {
            $UIControls.CbNetDrives.Visibility = 'Collapsed'
        } else {
            $UIControls.CbNetDrives.Visibility = 'Visible'
            $UIControls.CbNetDrives.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbRDP')) {
        if (-not $exported.Rdp) {
            $UIControls.CbRDP.Visibility = 'Collapsed'
        } else {
            $UIControls.CbRDP.Visibility = 'Visible'
            $UIControls.CbRDP.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbWallpaper')) {
        if (-not $exported.Wallpaper) {
            $UIControls.CbWallpaper.Visibility = 'Collapsed'
        } else {
            $UIControls.CbWallpaper.Visibility = 'Visible'
            $UIControls.CbWallpaper.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbDesktopPos')) {
        if (-not $exported.DesktopLayout) {
            $UIControls.CbDesktopPos.Visibility = 'Collapsed'
        } else {
            $UIControls.CbDesktopPos.Visibility = 'Visible'
            $UIControls.CbDesktopPos.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbTaskbar')) {
        if (-not $exported.TaskbarStart) {
            $UIControls.CbTaskbar.Visibility = 'Collapsed'
            if ($UIControls.ContainsKey('CbStartMenu')) {
                $UIControls.CbStartMenu.Visibility = 'Collapsed'
            }
        } else {
            $UIControls.CbTaskbar.Visibility = 'Visible'
            $UIControls.CbTaskbar.IsChecked = $true
            if ($UIControls.ContainsKey('CbStartMenu')) {
                $UIControls.CbStartMenu.Visibility = 'Visible'
                $UIControls.CbStartMenu.IsChecked = $true
            }
        }
    }
    
    if ($UIControls.ContainsKey('CbQuickAccess')) {
        if (-not $exported.QuickAccess) {
            $UIControls.CbQuickAccess.Visibility = 'Collapsed'
        } else {
            $UIControls.CbQuickAccess.Visibility = 'Visible'
            $UIControls.CbQuickAccess.IsChecked = $true
        }
    }
    
    # Navigateurs
    if ($UIControls.ContainsKey('CbAppChrome')) {
        if (-not $exported.Chrome) {
            $UIControls.CbAppChrome.Visibility = 'Collapsed'
        } else {
            $UIControls.CbAppChrome.Visibility = 'Visible'
            $UIControls.CbAppChrome.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbAppEdge')) {
        if (-not $exported.Edge) {
            $UIControls.CbAppEdge.Visibility = 'Collapsed'
        } else {
            $UIControls.CbAppEdge.Visibility = 'Visible'
            $UIControls.CbAppEdge.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbAppFirefox')) {
        if (-not $exported.Firefox) {
            $UIControls.CbAppFirefox.Visibility = 'Collapsed'
        } else {
            $UIControls.CbAppFirefox.Visibility = 'Visible'
            $UIControls.CbAppFirefox.IsChecked = $true
        }
    }
    
    if ($UIControls.ContainsKey('CbAppOutlook')) {
        if (-not $exported.Outlook) {
            $UIControls.CbAppOutlook.Visibility = 'Collapsed'
        } else {
            $UIControls.CbAppOutlook.Visibility = 'Visible'
            $UIControls.CbAppOutlook.IsChecked = $true
        }
    }

    # FIX: Reconstruire le TreeView des dossiers pour n'afficher QUE les dossiers exportés
    if ($UIControls.ContainsKey('TreeFolders')) {
        $importFolder = if ($Manifest.ExportFolder) { $Manifest.ExportFolder } else { $null }

        # Si pas de chemin dans le manifest, essayer de le récupérer du TextBox
        if (-not $importFolder -and $UIControls.ContainsKey('TbImportSrc')) {
            $importFolder = $UIControls.TbImportSrc.Text
        }

        if ($importFolder -and (Test-Path $importFolder)) {
            Write-MWLogInfo "Reconstruction de l'arbre des dossiers pour Import depuis : $importFolder"
            Build-FoldersTree -TreeView $UIControls.TreeFolders -IsExport $false -ImportFolder $importFolder
        }
    }

    Write-MWLogInfo "Manifest appliqué - Options masquées/cochées selon export"
}

function Reset-ImportVisibility {
    <#
    .SYNOPSIS
    Réinitialise la visibilité de toutes les options (mode Export)
    .PARAMETER UIControls
    Hashtable des contrôles UI à réinitialiser
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UIControls
    )
    
    # Rendre tout visible
    $controlNames = @(
        'CbWifi', 'CbPrinters', 'CbPrinterDrivers', 'CbNetDrives',
        'CbRDP', 'CbWallpaper', 'CbDesktopPos', 'CbTaskbar',
        'CbStartMenu', 'CbQuickAccess', 'CbAppChrome', 'CbAppEdge',
        'CbAppFirefox', 'CbAppOutlook'
    )
    
    foreach ($name in $controlNames) {
        if ($UIControls.ContainsKey($name)) {
            $UIControls[$name].Visibility = 'Visible'
        }
    }
    
    Write-MWLogInfo "Visibilité réinitialisée pour mode Export"
}

# Export des fonctions
Export-ModuleMember -Function @(
    'Read-ExportManifest',
    'Create-ExportManifest',
    'Apply-ImportManifest',
    'Reset-ImportVisibility'
)
