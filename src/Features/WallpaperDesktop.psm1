# WallpaperDesktop.psm1
# Gestion de l'export/import du fond d'écran et des positions d'icônes sur le bureau

function Export-WallpaperDesktop {
    <#
    .SYNOPSIS
    Exporte le fond d'écran et les positions d'icônes du bureau
    
    .PARAMETER OutRoot
    Dossier racine de destination pour l'export
    
    .PARAMETER IncludeWallpaper
    Exporter le fond d'écran
    
    .PARAMETER IncludeDesktopLayout
    Exporter les positions d'icônes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutRoot,
        
        [bool]$IncludeWallpaper = $true,
        [bool]$IncludeDesktopLayout = $true
    )
    
    try {
        if ($IncludeWallpaper) {
            Export-WallpaperSimple -OutRoot $OutRoot
        }
        
        if ($IncludeDesktopLayout) {
            Save-DesktopLayout -OutDir $OutRoot
        }
        
        Write-MWLogInfo "Export Wallpaper/Desktop terminé"
    }
    catch {
        Write-MWLogError "Export Wallpaper/Desktop : $($_.Exception.Message)"
    }
}

function Import-WallpaperDesktop {
    <#
    .SYNOPSIS
    Importe le fond d'écran et les positions d'icônes du bureau
    
    .PARAMETER InRoot
    Dossier racine source pour l'import
    
    .PARAMETER IncludeWallpaper
    Importer le fond d'écran
    
    .PARAMETER IncludeDesktopLayout
    Importer les positions d'icônes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InRoot,
        
        [bool]$IncludeWallpaper = $true,
        [bool]$IncludeDesktopLayout = $true
    )
    
    try {
        if ($IncludeWallpaper) {
            Import-WallpaperSimple -InRoot $InRoot
        }
        
        if ($IncludeDesktopLayout) {
            Restore-DesktopLayout -InDir $InRoot
        }
        
        Write-MWLogInfo "Import Wallpaper/Desktop terminé"
    }
    catch {
        Write-MWLogError "Import Wallpaper/Desktop : $($_.Exception.Message)"
    }
}

# ========== Fonctions internes - Wallpaper ==========

function Export-WallpaperSimple {
    param([string]$OutRoot)
    
    try {
        $wp = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        if (-not $wp -or -not (Test-Path $wp)) {
            Write-MWLogWarn "Fond d'écran : chemin introuvable - export ignoré"
            return
        }
        
        $wdir = Join-Path $OutRoot 'Wallpaper'
        New-Item -ItemType Directory -Force -Path $wdir | Out-Null
        $dst = Join-Path $wdir (Split-Path $wp -Leaf)
        Copy-Item -LiteralPath $wp -Destination $dst -Force
        
        "$([IO.Path]::GetFileName($dst))" | Set-Content -Path (Join-Path $wdir 'wallpaper.txt') -Encoding UTF8
        Write-MWLogInfo "Fond d'écran copié → $dst"
    }
    catch {
        Write-MWLogError "Export fond d'écran : $($_.Exception.Message)"
    }
}

function Import-WallpaperSimple {
    param([string]$InRoot)
    
    try {
        $wpDir = Join-Path $InRoot 'Wallpaper'
        if (-not (Test-Path $wpDir)) {
            Write-MWLogWarn "Fond d'écran absent - rien à restaurer"
            return
        }
        
        $txt = Join-Path $wpDir 'wallpaper.txt'
        $fileName = $null
        if (Test-Path $txt) {
            $fileName = (Get-Content $txt -Raw).Trim()
        }
        
        $img = $null
        if ($fileName) {
            $img = Join-Path $wpDir $fileName
        }
        else {
            $cand = Get-ChildItem $wpDir -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cand) {
                $img = $cand.FullName
            }
        }
        
        if ($img -and (Test-Path $img)) {
            Set-WallpaperSafe -ImagePath $img
        }
        else {
            Write-MWLogWarn "Fond d'écran : aucune image trouvée"
        }
    }
    catch {
        Write-MWLogError "Import fond d'écran : $($_.Exception.Message)"
    }
}

function Set-WallpaperSafe {
    param([Parameter(Mandatory)][string]$ImagePath)
    
    try {
        if (-not (Test-Path -LiteralPath $ImagePath)) {
            throw "Image introuvable: $ImagePath"
        }
        
        # 1) Copie sous C:\Logicia\Wallpaper
        $root = 'C:\Logicia\Wallpaper'
        try {
            New-Item -ItemType Directory -Force -Path $root | Out-Null
        }
        catch {}
        
        $dst = Join-Path $root (Split-Path $ImagePath -Leaf)
        Copy-Item -LiteralPath $ImagePath -Destination $dst -Force
        $ImagePath = $dst
        Write-MWLogInfo "Fond d'écran : image copiée → $ImagePath"
        
        # 2) Tentative API DesktopWallpaper (Win8+)
        $ok = $false
        try {
            $dw = New-Object -ComObject DesktopWallpaper
            if ($dw) {
                $dw.SetWallpaper('', $ImagePath) | Out-Null
                $ok = $true
                Write-MWLogInfo "Fond d'écran appliqué via DesktopWallpaper"
            }
        }
        catch {
            Write-MWLogWarn "DesktopWallpaper KO : $($_.Exception.Message)"
        }
        
        # 3) Fallback : SPI + refresh Explorer
        if (-not $ok) {
            try {
                $sig = @'
using System;
using System.Runtime.InteropServices;
public class WP {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
                if (-not ([type]::GetType('WP'))) {
                    Add-Type $sig -ErrorAction SilentlyContinue
                }
                [void][WP]::SystemParametersInfo(20, 0, $ImagePath, 1 -bor 2)
                Write-MWLogInfo "Fond d'écran appliqué via SystemParametersInfo"
                $ok = $true
            }
            catch {
                Write-MWLogWarn "SPI KO : $($_.Exception.Message)"
            }
        }
        
        # 4) Fallback verbe shell (optionnel)
        if (-not $ok) {
            try {
                $shell = New-Object -ComObject Shell.Application
                $shell.ShellExecute($ImagePath, $null, $null, 'setdesktopwallpaper', 1) | Out-Null
                Write-MWLogInfo "Fond d'écran appliqué via verbe shell"
                $ok = $true
            }
            catch {}
        }
        
        if (-not $ok) {
            throw "Impossible d'appliquer le fond d'écran (toutes méthodes ont échoué)"
        }
    }
    catch {
        Write-MWLogError "Set-WallpaperSafe : $($_.Exception.Message)"
    }
}

# ========== Fonctions internes - Desktop Layout ==========

function Save-DesktopLayout {
    param([string]$OutDir)
    
    try {
        if (-not (Test-Path -LiteralPath $OutDir)) {
            New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
        }
        
        # Garantir System.Drawing/Windows.Forms avant d'utiliser Graphics/Screen (PS 5.1)
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        }
        catch {}
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        }
        catch {}
        
        $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        try {
            [pscustomobject]@{
                Width  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
                Height = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
                DpiX   = [int]$g.DpiX
                DpiY   = [int]$g.DpiY
            } | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir 'screen.json') -Encoding UTF8
        }
        finally {
            $g.Dispose()
        }
        
        # Mettre les exports dans .\Registry pour correspondre à l'import
        $regOut = Join-Path $OutDir 'Registry'
        New-Item -ItemType Directory -Force -Path $regOut | Out-Null
        
        Export-RegIfHasValues `
            -PsPath  "HKCU:\Software\Microsoft\Windows\Shell\Bags" `
            -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags" `
            -DestFile (Join-Path $regOut 'bags.reg')
        
        Export-RegIfHasValues `
            -PsPath  "HKCU:\Software\Microsoft\Windows\Shell\BagMRU" `
            -RawPath "HKCU\Software\Microsoft\Windows\Shell\BagMRU" `
            -DestFile (Join-Path $regOut 'bagmru.reg')
        
        Export-RegIfHasValues `
            -PsPath  "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" `
            -RawPath "HKCU\Software\Microsoft\Windows\Shell\Bags\1\Desktop" `
            -DestFile (Join-Path $regOut 'desktopbag.reg')
        
        Export-RegIfHasValues `
            -PsPath  "HKCU:\Software\Microsoft\Windows\Shell\Streams\Desktop" `
            -RawPath "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop" `
            -DestFile (Join-Path $regOut 'streamsdesk.reg')
        
        Export-RegIfHasValues `
            -PsPath  "HKCU:\Control Panel\Desktop\WindowMetrics" `
            -RawPath "HKCU\Control Panel\Desktop\WindowMetrics" `
            -DestFile (Join-Path $regOut 'windowmetrics.reg')
        
        # Marqueur de compat
        try {
            '1' | Set-Content -Path (Join-Path $regOut 'UserDesktop.marker') -Encoding ASCII
        }
        catch {}
        
        # Liste fichiers bureau
        $pub = 'C:\Users\Public\Desktop'
        $usr = Join-Path $env:USERPROFILE 'Desktop'
        Get-ChildItem -LiteralPath $pub, $usr -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object FullName, Name, PSIsContainer |
            Export-Csv -NoTypeInformation -Encoding UTF8 -UseCulture -Path (Join-Path $OutDir 'desktop_files.csv')
        
        Write-MWLogInfo "Desktop Layout exporté"
    }
    catch {
        Write-MWLogError "Save-DesktopLayout : $($_.Exception.Message)"
    }
}

function Restore-DesktopLayout {
    param([Parameter(Mandatory)][string]$InDir)
    
    try {
        # 1) Désactiver l'auto-arrange le temps de la pose
        try {
            New-Item -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" -Force | Out-Null
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop" `
                -Name "FFlags" -Value 0x43000000 -PropertyType DWord -Force | Out-Null
        }
        catch {}
        
        # 2) Arrêter Explorer avant import
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        
        # 3) Importer toutes les branches liées au layout
        $regDir = Join-Path $InDir 'Registry'
        
        # Nettoyage prudent des caches d'Explorer
        try {
            reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Bags" /f 2>$null | Out-Null
            reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\BagMRU" /f 2>$null | Out-Null
            reg.exe delete "HKCU\Software\Microsoft\Windows\Shell\Streams\Desktop" /f 2>$null | Out-Null
        }
        catch {}
        
        foreach ($f in 'bags.reg', 'bagmru.reg', 'desktopbag.reg', 'streamsdesk.reg', 'windowmetrics.reg') {
            $p = Join-Path $regDir $f
            if (Test-Path $p) {
                & reg.exe import "$p" 2>$null | Out-Null
            }
        }
        
        # 4) Redémarrer proprement Explorer
        try {
            Start-Process explorer.exe
            Start-Sleep -Seconds 2
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
                Start-Process explorer.exe
            }
        }
        catch {}
        
        Write-MWLogInfo "Desktop Layout restauré"
    }
    catch {
        Write-MWLogError "Restore-DesktopLayout : $($_.Exception.Message)"
    }
}

function Export-RegIfHasValues {
    param(
        [Parameter(Mandatory)][string]$PsPath,
        [Parameter(Mandatory)][string]$RawPath,
        [Parameter(Mandatory)][string]$DestFile
    )
    
    try {
        if (Test-Path $PsPath) {
            $props = Get-ItemProperty -Path $PsPath -ErrorAction SilentlyContinue
            if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
                & reg.exe export $RawPath $DestFile /y 2>$null | Out-Null
                Write-MWLogInfo "Reg export → $DestFile"
            }
            else {
                Write-MWLogWarn "Reg présent mais vide → $RawPath (export ignoré)"
            }
        }
        else {
            Write-MWLogWarn "Reg absent → $RawPath (export ignoré)"
        }
    }
    catch {
        Write-MWLogError "Reg export $RawPath : $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Export-WallpaperDesktop, Import-WallpaperDesktop
