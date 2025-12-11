# src/Core/Profile.psm1
# Orchestration des exports / imports de profil (Wifi, imprimantes, RDP, navigateurs, etc.)

function Export-MWProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        [bool]$IncludeUserData           = $true,
        [string[]]$SelectedFolders       = @(),
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
        # Plus tard : OneDrive, etc.
    )

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }

        # Petit fichier d'info sur l'export
        try {
            $info = [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                Domain       = $env:USERDOMAIN
                Date         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                OsVersion    = [System.Environment]::OSVersion.VersionString
            }

            $info | ConvertTo-Json | Set-Content -Path (Join-Path $DestinationFolder 'ProfileInfo.json') -Encoding UTF8
        } catch {
            Write-MWLogWarning "Export-MWProfile : impossible d'écrire ProfileInfo.json : $($_.Exception.Message)"
        }

        Write-MWLogInfo "=== Début Export-MWProfile vers '$DestinationFolder' ==="

        # Fonction helper pour mettre à jour l'UI si disponible
        $updateUI = {
            param([string]$Msg, [int]$Pct)
            if (Get-Command -Name Update-ProgressUI -ErrorAction SilentlyContinue) {
                Update-ProgressUI -Message $Msg -Percent $Pct
            }
        }

        & $updateUI "Démarrage de l'export..." 0

        # Données utilisateur (Documents, Bureau, etc.)
        if ($IncludeUserData -or ($SelectedFolders -and $SelectedFolders.Count -gt 0)) {
            & $updateUI "Analyse des fichiers à copier..." 1
            try {
                if ($UseDataFoldersManifest) {
                    # Dossier racine des données utilisateur dans l'export
                    $profileDestRoot = Join-Path $DestinationFolder 'Profile'

                    # Emplacement du manifest DataFolders pour cet export
                    $manifestPath = Join-Path $DestinationFolder 'DataFolders.manifest.json'

                    Write-MWLogInfo ("Export-MWProfile : mode avancé DataFolders activé. Manifest = '{0}', DestinationRoot = '{1}'" -f $manifestPath, $profileDestRoot)

                    # Mode interactif : Out-GridView pour choisir les dossiers, puis export réel
                    Show-MWDataFoldersExportPlan -ManifestPath $manifestPath -DestinationRoot $profileDestRoot
                }
                else {
                    # Comportement historique : export brut des dossiers "classiques"
                    Export-MWUserData -DestinationFolder $DestinationFolder -SelectedFolders $SelectedFolders -IncrementalMode $IncrementalMode
                }
            } catch {
                Write-MWLogError "Export données utilisateur : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Données utilisateur : export ignoré (aucun dossier sélectionné)."
        }

        if ($IncludeWifi) {
            & $updateUI "Export des profils Wi-Fi..." 15
            try {
                Export-MWWifiProfiles -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Wifi : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Wifi : export ignoré (IncludeWifi = \$false)."
        }

        if ($IncludePrinters) {
            & $updateUI "Export des imprimantes..." 25
            try {
                Export-MWPrinters -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export imprimantes : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Imprimantes : export ignoré (IncludePrinters = \$false)."
        }

        if ($IncludeNetworkDrives) {
            & $updateUI "Export des lecteurs réseau..." 35
            try {
                Export-MWNetworkDrives -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export lecteurs réseau : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Lecteurs réseau : export ignoré (IncludeNetworkDrives = \$false)."
        }

        if ($IncludeRdp) {
            & $updateUI "Export des connexions RDP..." 40
            try {
                Export-MWRdpConnections -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export RDP : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "RDP : export ignoré (IncludeRdp = \$false)."
        }

        if ($IncludeChrome -or $IncludeEdge -or $IncludeFirefox) {
            & $updateUI "Export des navigateurs..." 50
            try {
                # Construire la liste des navigateurs à exporter
                $browsersToExport = @()
                if ($IncludeChrome) { $browsersToExport += 'Chrome' }
                if ($IncludeEdge) { $browsersToExport += 'Edge' }
                if ($IncludeFirefox) { $browsersToExport += 'Firefox' }

                Export-MWBrowsers -DestinationFolder $DestinationFolder -BrowsersToExport $browsersToExport
            } catch {
                Write-MWLogError "Export navigateurs : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Navigateurs : export ignoré (aucun navigateur coché)."
        }

        if ($IncludeOutlook) {
            & $updateUI "Export Outlook..." 60
            try {
                Export-MWOutlookData -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Outlook : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Outlook : export ignoré (IncludeOutlook = \$false)."
        }

        if ($IncludeWallpaper -or $IncludeDesktopLayout) {
            & $updateUI "Export fond d'écran et bureau..." 70
            try {
                Export-WallpaperDesktop -OutRoot $DestinationFolder -IncludeWallpaper $IncludeWallpaper -IncludeDesktopLayout $IncludeDesktopLayout
            } catch {
                Write-MWLogError "Export fond d'écran/desktop : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Fond d'écran/desktop : export ignoré."
        }

        if ($IncludeTaskbarStart) {
            & $updateUI "Export barre des tâches..." 80
            try {
                Export-TaskbarStart -OutRoot $DestinationFolder
            } catch {
                Write-MWLogError "Export Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : export ignoré (IncludeTaskbarStart = \$false)."
        }

        if ($IncludeQuickAccess) {
            & $updateUI "Export accès rapides..." 85
            try {
                Export-MWQuickAccess -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Quick Access : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Quick Access : export ignoré (IncludeQuickAccess = \$false)."
        }

        # ========================================
        # CRÉATION DU MANIFEST D'EXPORT
        # ========================================
        & $updateUI "Création du manifest..." 90
        try {
            Write-MWLogInfo "Création du manifest d'export..."
            
            $exportedItems = @{
                UserData       = $IncludeUserData
                SelectedFolders = $SelectedFolders  # AJOUT: Liste des dossiers exportés
                Wifi           = $IncludeWifi
                Printers       = $IncludePrinters
                NetworkDrives  = $IncludeNetworkDrives
                Rdp            = $IncludeRdp
                Chrome         = $IncludeChrome
                Edge           = $IncludeEdge
                Firefox        = $IncludeFirefox
                Outlook        = $IncludeOutlook
                Wallpaper      = $IncludeWallpaper
                DesktopLayout  = $IncludeDesktopLayout
                TaskbarStart   = $IncludeTaskbarStart
                QuickAccess    = $IncludeQuickAccess
            }
            
            $manifestPath = Create-ExportManifest -DestinationFolder $DestinationFolder -ExportedItems $exportedItems
            
            if ($manifestPath) {
                Write-MWLogInfo "Manifest créé avec succès : $manifestPath"
            }
        }
        catch {
            Write-MWLogWarning "Erreur création manifest : $($_.Exception.Message)"
            # Non bloquant, on continue
        }
        # ========================================

        & $updateUI "Export terminé !" 100
        Write-MWLogInfo "=== Fin Export-MWProfile ==="
    } catch {
        Write-MWLogError "Export-MWProfile (global) : $($_.Exception.Message)"
        throw
    }
}


function Import-MWProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,

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
        [bool]$UseDataFoldersManifest    = $false
    )

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            throw "Dossier source introuvable : $SourceFolder"
        }

        Write-MWLogInfo "=== Début Import-MWProfile depuis '$SourceFolder' ==="

        if ($IncludeUserData) {
            try {
                if ($UseDataFoldersManifest) {
                    # Manifest DataFolders produit lors de l'export
                    $manifestPath      = Join-Path $SourceFolder 'DataFolders.manifest.json'
                    # Les données exportées sont sous "Profile" (voir Export-MWProfile)
                    $profileSourceRoot = Join-Path $SourceFolder 'Profile'

                    Write-MWLogInfo (
                        "Import-MWProfile : mode avancé DataFolders activé. Manifest = '{0}', SourceRoot = '{1}'" -f `
                        $manifestPath, $profileSourceRoot
                    )

                    # Mode interactif : vue des dossiers (source -> cible) puis import réel
                    Show-MWDataFoldersImportPlan -ManifestPath $manifestPath -SourceRoot $profileSourceRoot
                }
                else {
                    # Comportement historique
                    Import-MWUserData -SourceFolder $SourceFolder
                }

                # Réparer les raccourcis après import (remplacer ancien username par nouveau)
                try {
                    $manifestPath = Join-Path $SourceFolder 'ExportManifest.json'
                    if (Test-Path $manifestPath) {
                        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                        $oldUserName = $manifest.ExportMetadata.UserName
                        if ($oldUserName -and $oldUserName -ne $env:USERNAME) {
                            Repair-MWShortcuts -OldUserName $oldUserName -NewUserName $env:USERNAME
                        }
                    }
                } catch {
                    Write-MWLogWarning "Impossible de réparer les raccourcis : $($_.Exception.Message)"
                }
            } catch {
                Write-MWLogError "Import données utilisateur : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Données utilisateur : import ignoré (IncludeUserData = `$false)."
        }

        if ($IncludeWifi) {
            try {
                Import-MWWifiProfiles -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import Wifi : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Wifi : import ignoré (IncludeWifi = \$false)."
        }

        if ($IncludePrinters) {
            try {
                Import-MWPrinters -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import imprimantes : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Imprimantes : import ignoré (IncludePrinters = \$false)."
        }

        if ($IncludeNetworkDrives) {
            try {
                Import-MWNetworkDrives -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import lecteurs réseau : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Lecteurs réseau : import ignoré (IncludeNetworkDrives = \$false)."
        }

        if ($IncludeRdp) {
            try {
                Import-MWRdpConnections -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import RDP : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "RDP : import ignoré (IncludeRdp = \$false)."
        }

        if ($IncludeChrome -or $IncludeEdge -or $IncludeFirefox) {
            try {
                # Construire la liste des navigateurs à importer
                $browsersToImport = @()
                if ($IncludeChrome) { $browsersToImport += 'Chrome' }
                if ($IncludeEdge) { $browsersToImport += 'Edge' }
                if ($IncludeFirefox) { $browsersToImport += 'Firefox' }

                Import-MWBrowsers -SourceFolder $SourceFolder -BrowsersToImport $browsersToImport
            } catch {
                Write-MWLogError "Import navigateurs : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Navigateurs : import ignoré (aucun navigateur coché)."
        }

        if ($IncludeOutlook) {
            try {
                Import-MWOutlookData -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import Outlook : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Outlook : import ignoré (IncludeOutlook = \$false)."
        }

        if ($IncludeWallpaper -or $IncludeDesktopLayout) {
            try {
                Import-WallpaperDesktop -InRoot $SourceFolder -IncludeWallpaper $IncludeWallpaper -IncludeDesktopLayout $IncludeDesktopLayout
            } catch {
                Write-MWLogError "Import fond d'écran/desktop : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Fond d'écran/desktop : import ignoré."
        }

        if ($IncludeTaskbarStart) {
            try {
                Import-TaskbarStart -InRoot $SourceFolder
            } catch {
                Write-MWLogError "Import Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : import ignoré (IncludeTaskbarStart = \$false)."
        }

        if ($IncludeQuickAccess) {
            try {
                Import-MWQuickAccess -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import Quick Access : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Quick Access : import ignoré (IncludeQuickAccess = \$false)."
        }

        Write-MWLogInfo "=== Fin Import-MWProfile ==="
    } catch {
        Write-MWLogError "Import-MWProfile (global) : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWProfile, Import-MWProfile

