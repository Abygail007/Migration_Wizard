# src/Features/WallpaperDesktop.psm1

function Set-MWWallpaperSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    try {
        if (-not (Test-Path -LiteralPath $ImagePath)) {
            throw "Image introuvable : $ImagePath"
        }

        # 1) Copie l’image dans un dossier stable (évite les chemins temporaires)
        $root = 'C:\MigrationWizard\Wallpaper'
        try {
            New-Item -ItemType Directory -Force -Path $root | Out-Null
        } catch {
            Write-MWLogWarning "Set-MWWallpaperSafe : impossible de créer le dossier '$root' : $($_.Exception.Message)"
        }

        $dst = Join-Path $root (Split-Path $ImagePath -Leaf)
        Copy-Item -LiteralPath $ImagePath -Destination $dst -Force
        $ImagePath = $dst

        Write-MWLogInfo "Fond d’écran : image copiée → $ImagePath"

        $ok = $false

        # 2) Tentative via l’API DesktopWallpaper (Windows 8+)
        try {
            $dw = New-Object -ComObject DesktopWallpaper
            if ($dw) {
                $dw.SetWallpaper('', $ImagePath) | Out-Null
                Write-MWLogInfo "Fond d’écran appliqué via DesktopWallpaper."
                $ok = $true
            }
        } catch {
            Write-MWLogWarning "DesktopWallpaper KO : $($_.Exception.Message)"
        }

        # 3) Fallback via SystemParametersInfo (Win32)
        if (-not $ok) {
            try {
                $sig = @'
using System;
using System.Runtime.InteropServices;
public class MW_WP {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
                if (-not ([Type]::GetType('MW_WP'))) {
                    Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue
                }

                # 20 = SPI_SETDESKWALLPAPER, 1|2 = mise à jour + sauvegarde dans le profil utilisateur
                [void][MW_WP]::SystemParametersInfo(20, 0, $ImagePath, 1 -bor 2)
                Write-MWLogInfo "Fond d’écran appliqué via SystemParametersInfo."
                $ok = $true
            } catch {
                Write-MWLogWarning "SPI KO : $($_.Exception.Message)"
            }
        }

        # 4) Fallback via verbe shell (si dispo)
        if (-not $ok) {
            try {
                $shell = New-Object -ComObject Shell.Application
                $shell.ShellExecute($ImagePath, $null, $null, 'setdesktopwallpaper', 1) | Out-Null
                Write-MWLogInfo "Fond d’écran appliqué via verbe Shell.Application."
                $ok = $true
            } catch {
                Write-MWLogWarning "Verbe shell KO : $($_.Exception.Message)"
            }
        }

        if (-not $ok) {
            Write-MWLogError "Impossible d’appliquer le fond d’écran (toutes les méthodes ont échoué)."
        }
    } catch {
        Write-MWLogError "Set-MWWallpaperSafe : $($_.Exception.Message)"
    }
}

function Export-MWWallpaper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    try {
        $wp = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        if (-not $wp -or -not (Test-Path -LiteralPath $wp)) {
            Write-MWLogInfo "Fond d’écran : chemin introuvable — export ignoré."
            return
        }

        $wdir = Join-Path $DestinationFolder 'Wallpaper'
        if (-not (Test-Path -LiteralPath $wdir)) {
            New-Item -ItemType Directory -Force -Path $wdir | Out-Null
        }

        $dst = Join-Path $wdir (Split-Path $wp -Leaf)
        Copy-Item -LiteralPath $wp -Destination $dst -Force

        $fileName = [IO.Path]::GetFileName($dst)
        $fileName | Set-Content -Path (Join-Path $wdir 'wallpaper.txt') -Encoding UTF8

        Write-MWLogInfo "Fond d’écran exporté vers '$dst'."
    } catch {
        Write-MWLogError "Export fond d’écran : $($_.Exception.Message)"
        throw
    }
}

function Import-MWWallpaper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    try {
        $wdir = Join-Path $SourceFolder 'Wallpaper'
        if (-not (Test-Path -LiteralPath $wdir -PathType Container)) {
            Write-MWLogWarning "Import fond d’écran : dossier 'Wallpaper' introuvable → aucun fond appliqué."
            return
        }

        $txt = Join-Path $wdir 'wallpaper.txt'
        $img = $null

        if (Test-Path -LiteralPath $txt) {
            try {
                $fileName = (Get-Content -LiteralPath $txt -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                if ($fileName) {
                    $candidate = Join-Path $wdir $fileName
                    if (Test-Path -LiteralPath $candidate) {
                        $img = $candidate
                    }
                }
            } catch {
                Write-MWLogWarning "Import fond d’écran : lecture de wallpaper.txt KO : $($_.Exception.Message)"
            }
        }

        if (-not $img) {
            $cand = Get-ChildItem -LiteralPath $wdir -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cand) {
                $img = $cand.FullName
            }
        }

        if ($img) {
            Write-MWLogInfo "Import fond d’écran : application de '$img'."
            Set-MWWallpaperSafe -ImagePath $img
        } else {
            Write-MWLogWarning "Import fond d’écran : aucune image trouvée dans '$wdir'."
        }
    } catch {
        Write-MWLogError "Import fond d’écran : $($_.Exception.Message)"
        throw
    }
}

function Save-MWDesktopLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Force -Path $DestinationFolder | Out-Null
        }

        # 1) Info écran (résolution / DPI)
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null
        } catch {}
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        try {
            $screenInfo = [pscustomobject]@{
                Width  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
                Height = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
                DpiX   = [int]$g.DpiX
                DpiY   = [int]$g.DpiY
            }

            $screenInfo |
                ConvertTo-Json |
                Set-Content -Path (Join-Path $DestinationFolder 'screen.json') -Encoding UTF8

            Write-MWLogInfo "Layout bureau : screen.json enregistré."
        } finally {
            $g.Dispose()
        }

        # 2) Exports Reg pour Bags / BagMRU / Desktop / WindowMetrics
        $regOut = Join-Path $DestinationFolder 'Registry'
        New-Item -ItemType Directory -Force -Path $regOut | Out-Null

        function Export-MWRegIfHasValues {
            param(
                [Parameter(Mandatory = $true)][string]$PsPath,
                [Parameter(Mandatory = $true)][string]$RawPath,
                [Parameter(Mandatory = $true)][string]$DestFile
            )
            try {
                if (Test-Path -LiteralPath $PsPath) {
                    $props = Get-ItemProperty -Path $PsPath -ErrorAction SilentlyContinue
                    if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
                        & reg.exe export $RawPath $DestFile /y 2>$null | Out-Null
                        Write-MWLogInfo ("Reg export → {0}" -f $DestFile)
                    } else {
                        Write-MWLogInfo ("Reg présent mais vide → {0} (export ignoré)" -f $RawPath)
                    }
                } else {
                    Write-MWLogInfo ("Reg absent → {0} (export ignoré)" -f $RawPath)
                }
            } catch {
                Write-MWLogWarning ("Reg export {0} : {1}" -f $RawPath, $_.Exception.Message)
            }
        }

        Export-MWRegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Bags"               -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags"               -DestFile (Join-Path $regOut 'bags.reg')
        Export-MWRegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\BagMRU"             -RawPath "HKCU\Software\Microsoft\Windows\Shell\BagMRU"             -DestFile (Join-Path $regOut 'bagmru.reg')
        Export-MWRegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop"     -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags\1\Desktop"     -DestFile (Join-Path $regOut 'desktopbag.reg')
        Export-MWRegIfHasValues -PsPath "HKCU:\Software\Microsoft\Windows\Shell\Streams\Desktop"    -RawPath "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop"    -DestFile (Join-Path $regOut 'streamsdesk.reg')
        Export-MWRegIfHasValues -PsPath "HKCU:\Control Panel\Desktop\WindowMetrics"                 -RawPath "HKCU\Control Panel\Desktop\WindowMetrics"                 -DestFile (Join-Path $regOut 'windowmetrics.reg')

        Write-MWLogInfo "Layout bureau : exports Registry terminés."
    } catch {
        Write-MWLogError "Save-MWDesktopLayout : $($_.Exception.Message)"
        throw
    }
}

function Restore-MWDesktopLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    try {
        $regDir = Join-Path $SourceFolder 'Registry'
        if (-not (Test-Path -LiteralPath $regDir -PathType Container)) {
            Write-MWLogWarning "Restore-MWDesktopLayout : dossier Registry introuvable → aucun layout restauré."
            return
        }

        # 1) Forcer AlignToGrid ON, AutoArrange OFF
        try {
            $desktopKey = "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop"
            New-Item -Path $desktopKey -Force | Out-Null
            New-ItemProperty -Path $desktopKey -Name "FFlags" -Value 0x43000000 -PropertyType DWord -Force | Out-Null
        } catch {
            Write-MWLogWarning "Restore-MWDesktopLayout : impossible de régler FFlags : $($_.Exception.Message)"
        }

        # 2) Arrêter Explorer pour éviter les caches
        try {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Wait-Process -Name explorer -Timeout 3 -ErrorAction SilentlyContinue
        } catch {
            Write-MWLogWarning "Restore-MWDesktopLayout : arrêt d’Explorer KO : $($_.Exception.Message)"
        }

        # 3) Nettoyer les clés avant import (limite les merges bizarres)
        try {
            & reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Bags" /f            | Out-Null
            & reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\BagMRU" /f          | Out-Null
            & reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop" /f | Out-Null
        } catch {
            Write-MWLogWarning "Restore-MWDesktopLayout : suppression des clés existantes KO : $($_.Exception.Message)"
        }

        # 4) Importer les fichiers .reg
        foreach ($f in 'bags.reg','bagmru.reg','desktopbag.reg','streamsdesk.reg','windowmetrics.reg') {
            $p = Join-Path $regDir $f
            if (Test-Path -LiteralPath $p) {
                try {
                    & reg.exe import "$p" 2>$null | Out-Null
                    Write-MWLogInfo "Layout bureau : import de '$f' OK."
                } catch {
                    Write-MWLogWarning "Layout bureau : import de '$f' KO : $($_.Exception.Message)"
                }
            }
        }

        # 5) Relancer Explorer
        try {
            Start-Process explorer.exe
            Start-Sleep -Seconds 2
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
                Start-Process explorer.exe
            }
        } catch {
            Write-MWLogWarning "Restore-MWDesktopLayout : relance d’Explorer KO : $($_.Exception.Message)"
        }
    } catch {
        Write-MWLogError "Restore-MWDesktopLayout : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function `
    Set-MWWallpaperSafe, `
    Export-MWWallpaper, Import-MWWallpaper, `
    Save-MWDesktopLayout, Restore-MWDesktopLayout
