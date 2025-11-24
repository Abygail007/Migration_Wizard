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
        [bool]$IncludeTaskbarStart   = $true,
        [bool]$IncludeUserData       = $true
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

            $profileInfoPath = Join-Path $DestinationFolder 'ProfileInfo.json'
            $info | ConvertTo-Json | Set-Content -Path $profileInfoPath -Encoding UTF8
        } catch {
            Write-MWLogWarning ("Export-MWProfile : impossible d'ecrire ProfileInfo.json : {0}" -f $_.Exception.Message)
        }

        Write-MWLogInfo ("=== Debut Export-MWProfile vers '{0}' ===" -f $DestinationFolder)

        if ($IncludeWifi) {
            try {
                Export-MWWifiProfiles -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export Wifi : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Wifi : export ignore (IncludeWifi = $false).'
        }

        if ($IncludePrinters) {
            try {
                Export-MWPrinters -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export imprimantes : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Imprimantes : export ignore (IncludePrinters = $false).'
        }

        if ($IncludeNetworkDrives) {
            try {
                Export-MWNetworkDrives -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export lecteurs reseau : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Lecteurs reseau : export ignore (IncludeNetworkDrives = $false).'
        }

        if ($IncludeRdp) {
            try {
                Export-MWRdpConnections -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export RDP : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'RDP : export ignore (IncludeRdp = $false).'
        }

        if ($IncludeBrowsers) {
            try {
                Export-MWBrowsers -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export navigateurs : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Navigateurs : export ignore (IncludeBrowsers = $false).'
        }

        if ($IncludeOutlook) {
            try {
                Export-MWOutlookData -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export Outlook : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Outlook : export ignore (IncludeOutlook = $false).'
        }

        if ($IncludeWallpaper) {
            try {
                Export-MWWallpaper -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export fond ecran : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Fond ecran : export ignore (IncludeWallpaper = $false).'
        }

        if ($IncludeDesktopLayout) {
            try {
                Save-MWDesktopLayout -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError ("Export layout bureau : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Layout bureau : export ignore (IncludeDesktopLayout = $false).'
        }

        if ($IncludeTaskbarStart) {
            try {
                Export-MWTaskbarStart -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : export ignoré (IncludeTaskbarStart = `$false)."
        }

        if ($IncludeUserData) {
            try {
                Export-MWDataFolders -DestinationFolder $DestinationFolder
            } catch {
                Write-MWLogError "Export données utilisateur : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Données utilisateur : export ignoré (IncludeUserData = `$false)."
        }

        Write-MWLogInfo "=== Fin Export-MWProfile ==="

    } catch {
        Write-MWLogError ("Export-MWProfile (global) : {0}" -f $_.Exception.Message)
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
        [bool]$IncludeTaskbarStart   = $true,
        [bool]$IncludeUserData       = $true

    )

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            throw ("Dossier source introuvable : {0}" -f $SourceFolder)
        }

        Write-MWLogInfo ("=== Debut Import-MWProfile depuis '{0}' ===" -f $SourceFolder)

        if ($IncludeWifi) {
            try {
                Import-MWWifiProfiles -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import Wifi : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Wifi : import ignore (IncludeWifi = $false).'
        }

        if ($IncludePrinters) {
            try {
                Import-MWPrinters -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import imprimantes : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Imprimantes : import ignore (IncludePrinters = $false).'
        }

        if ($IncludeNetworkDrives) {
            try {
                Import-MWNetworkDrives -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import lecteurs reseau : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Lecteurs reseau : import ignore (IncludeNetworkDrives = $false).'
        }

        if ($IncludeRdp) {
            try {
                Import-MWRdpConnections -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import RDP : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'RDP : import ignore (IncludeRdp = $false).'
        }

        if ($IncludeBrowsers) {
            try {
                Import-MWBrowsers -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import navigateurs : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Navigateurs : import ignore (IncludeBrowsers = $false).'
        }

        if ($IncludeOutlook) {
            try {
                Import-MWOutlookData -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import Outlook : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Outlook : import ignore (IncludeOutlook = $false).'
        }

        if ($IncludeWallpaper) {
            try {
                Import-MWWallpaper -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import fond ecran : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Fond ecran : import ignore (IncludeWallpaper = $false).'
        }

        if ($IncludeDesktopLayout) {
            try {
                Restore-MWDesktopLayout -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError ("Import layout bureau : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogInfo 'Layout bureau : import ignore (IncludeDesktopLayout = $false).'
        }

        if ($IncludeTaskbarStart) {
            try {
                Import-MWTaskbarStart -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import Taskbar/Start : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Taskbar/Start : import ignoré (IncludeTaskbarStart = `$false)."
        }

        if ($IncludeUserData) {
            try {
                Import-MWDataFolders -SourceFolder $SourceFolder
            } catch {
                Write-MWLogError "Import données utilisateur : $($_.Exception.Message)"
            }
        } else {
            Write-MWLogInfo "Données utilisateur : import ignoré (IncludeUserData = `$false)."
        }

        Write-MWLogInfo "=== Fin Import-MWProfile ==="

    } catch {
        Write-MWLogError ("Import-MWProfile (global) : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWProfile, Import-MWProfile
