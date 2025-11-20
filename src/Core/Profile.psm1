# src/Core/Profile.psm1
# Orchestration des exports / imports de profil (Wifi, imprimantes, RDP, navigateurs, etc.)

function Export-MWProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        [bool]$IncludeWifi           = $true,
        [bool]$IncludePrinters       = $true,
        [bool]$IncludeNetworkDrives  = $true,
        [bool]$IncludeRdp            = $true,
        [bool]$IncludeBrowsers       = $true,
        [bool]$IncludeOutlook        = $true,
        [bool]$IncludeWallpaper      = $true,
        [bool]$IncludeDesktopLayout  = $true,
        [bool]$IncludeTaskbarStart   = $true
        # Plus tard : OneDrive, etc.
    )

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }

        # Petit fichier d’info sur l’export
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
            Write-MWLogWarning "Export-MWProfile : impossible d’écrire ProfileInfo.json : $($_.Exception.Message)"
        }

        Write-MWLogInfo "=== Début Export-MWProfile vers '$DestinationFolder' ==="

        if ($IncludeWifi) {
            try {
                Export-MWWifiProfiles -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Wifi : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Wifi : export ignoré (IncludeWifi = \$false)."
        }

        if ($IncludePrinters) {
            try {
                Export-MWPrinters -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export imprimantes : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Imprimantes : export ignoré (IncludePrinters = \$false)."
        }

        if ($IncludeNetworkDrives) {
            try {
                Export-MWNetworkDrives -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export lecteurs réseau : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Lecteurs réseau : export ignoré (IncludeNetworkDrives = \$false)."
        }

        if ($IncludeRdp) {
            try {
                Export-MWRdpConnections -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export RDP : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "RDP : export ignoré (IncludeRdp = \$false)."
        }

        if ($IncludeBrowsers) {
            try {
                Export-MWBrowsers -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export navigateurs : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Navigateurs : export ignoré (IncludeBrowsers = \$false)."
        }

        if ($IncludeOutlook) {
            try {
                Export-MWOutlookData -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Outlook : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Outlook : export ignoré (IncludeOutlook = \$false)."
        }

        if ($IncludeWallpaper) {
            try {
                Export-MWWallpaper -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export fond d’écran : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Fond d’écran : export ignoré (IncludeWallpaper = \$false)."
        }

        if ($IncludeDesktopLayout) {
            try {
                Save-MWDesktopLayout -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export layout bureau : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Layout bureau : export ignoré (IncludeDesktopLayout = \$false)."
        }

        if ($IncludeTaskbarStart) {
            try {
                Export-MWTaskbarAndStart -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : export ignoré (IncludeTaskbarStart = \$false)."
        }

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

        [bool]$IncludeWifi           = $true,
        [bool]$IncludePrinters       = $true,
        [bool]$IncludeNetworkDrives  = $true,
        [bool]$IncludeRdp            = $true,
        [bool]$IncludeBrowsers       = $true,
        [bool]$IncludeOutlook        = $true,
        [bool]$IncludeWallpaper      = $true,
        [bool]$IncludeDesktopLayout  = $true,
        [bool]$IncludeTaskbarStart   = $true
    )

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            throw "Dossier source introuvable : $SourceFolder"
        }

        Write-MWLogInfo "=== Début Import-MWProfile depuis '$SourceFolder' ==="

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

        if ($IncludeBrowsers) {
            try {
                Import-MWBrowsers -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import navigateurs : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Navigateurs : import ignoré (IncludeBrowsers = \$false)."
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

        if ($IncludeWallpaper) {
            try {
                Import-MWWallpaper -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import fond d’écran : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Fond d’écran : import ignoré (IncludeWallpaper = \$false)."
        }

        if ($IncludeDesktopLayout) {
            try {
                Restore-MWDesktopLayout -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import layout bureau : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Layout bureau : import ignoré (IncludeDesktopLayout = \$false)."
        }

        if ($IncludeTaskbarStart) {
            try {
                Import-MWTaskbarAndStart -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : import ignoré (IncludeTaskbarStart = \$false)."
        }

        Write-MWLogInfo "=== Fin Import-MWProfile ==="
    } catch {
        Write-MWLogError "Import-MWProfile (global) : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWProfile, Import-MWProfile


function Import-MWProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe un profil utilisateur complet depuis un dossier d’export MigrationWizard.
        .DESCRIPTION
            Fait l’inverse de Export-MWProfile en réutilisant tous les modules :
            - Wi-Fi
            - Imprimantes
            - Lecteurs réseau
            - RDP
            - Navigateurs
            - Outlook
            - Fond d’écran
            - Layout du bureau
            (StartLayout / TaskbarStart pourra être ajouté plus tard).
    #>

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            throw ("Dossier source introuvable : {0}" -f $SourceFolder)
        }

        Write-MWLogInfo ("Import du profil depuis '{0}'" -f $SourceFolder)

        # 1) Réseau / périphériques
        Import-MWWifiProfiles    -SourceFolder $SourceFolder
        Import-MWPrinters        -SourceFolder $SourceFolder
        Import-MWNetworkDrives   -SourceFolder $SourceFolder

        # 2) RDP
        Import-MWRdpConnections  -SourceFolder $SourceFolder

        # 3) AppData / navigateurs / Outlook
        Import-MWBrowsers        -SourceFolder $SourceFolder
        Import-MWOutlookData     -SourceFolder $SourceFolder

        # 4) Affichage : fond d’écran + layout bureau
        Import-MWWallpaper       -SourceFolder $SourceFolder
        Restore-MWDesktopLayout  -SourceFolder $SourceFolder

        # (Plus tard on pourra ajouter ici Import-MWStartLayout si tu veux gérer le menu Démarrer)

        Write-MWLogInfo "Import du profil terminé."
    } catch {
        Write-MWLogError ("Import-MWProfile : {0}" -f $_.Exception.Message)
        throw
    }
}

