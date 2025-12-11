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
        # FIX: Logique simplifiée inspirée de l'ancien script fonctionnel
        # Lire registry et essayer de copier le fichier, c'est tout

        # 1. Control Panel\Desktop (emplacement principal)
        $wp = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper

        # 2. Si vide, essayer TranscodedImageCache dans AppData
        if (-not $wp -or [string]::IsNullOrWhiteSpace($wp)) {
            $appDataPath = Join-Path $env:APPDATA "Microsoft\Windows\Themes\TranscodedWallpaper"
            if (Test-Path $appDataPath) {
                $wp = $appDataPath
                Write-MWLogInfo "Fond d'écran : utilisation TranscodedWallpaper depuis AppData"
            }
        }

        # 3. Si toujours vide, essayer SystemParametersInfo
        if (-not $wp -or [string]::IsNullOrWhiteSpace($wp)) {
            Write-MWLogInfo "Fond d'écran registry vide, tentative API SystemParametersInfo..."

            try {
                $sig = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WPInfo {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, StringBuilder lpvParam, int fuWinIni);
}
'@
                if (-not ([type]::GetType('WPInfo'))) {
                    Add-Type $sig -ErrorAction Stop
                }

                $sb = New-Object System.Text.StringBuilder 260
                $result = [WPInfo]::SystemParametersInfo(0x0073, $sb.Capacity, $sb, 0)

                if ($result) {
                    $apiWp = $sb.ToString()
                    if ($apiWp -and -not [string]::IsNullOrWhiteSpace($apiWp)) {
                        $wp = $apiWp
                        Write-MWLogInfo "Fond d'écran récupéré via API : '$wp'"
                    }
                }
            } catch {
                Write-MWLogWarning "SystemParametersInfo échoué : $($_.Exception.Message)"
            }
        }

        if (-not $wp -or [string]::IsNullOrWhiteSpace($wp)) {
            Write-MWLogWarning "Fond d'écran : impossible de détecter le chemin - export ignoré"
            return
        }

        Write-MWLogInfo "Fond d'écran détecté : '$wp'"

        # DIAGNOSTIC: Vérifier si le fichier existe VRAIMENT
        $wpExists = Test-Path -LiteralPath $wp -ErrorAction SilentlyContinue
        Write-MWLogInfo "DIAGNOSTIC Wallpaper - Test-Path result: $wpExists"
        if ($wpExists) {
            $wpItem = Get-Item -LiteralPath $wp -ErrorAction SilentlyContinue
            if ($wpItem) {
                Write-MWLogInfo "DIAGNOSTIC Wallpaper - Taille fichier: $($wpItem.Length) octets"
                Write-MWLogInfo "DIAGNOSTIC Wallpaper - Type: $($wpItem.GetType().Name)"
            }
        }

        # FIX: Tenter de copier même si Test-Path échoue (fichiers systèmes spéciaux)
        $wdir = Join-Path $OutRoot 'Wallpaper'
        New-Item -ItemType Directory -Force -Path $wdir | Out-Null
        Write-MWLogInfo "DIAGNOSTIC Wallpaper - Dossier destination créé: $wdir"

        $fileName = [System.IO.Path]::GetFileName($wp)
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $fileName = "TranscodedWallpaper.jpg"
        }
        Write-MWLogInfo "DIAGNOSTIC Wallpaper - Nom fichier destination: $fileName"

        $dst = Join-Path $wdir $fileName
        Write-MWLogInfo "DIAGNOSTIC Wallpaper - Chemin complet destination: $dst"

        # Essayer la copie directement sans vérifier l'existence au préalable
        try {
            Write-MWLogInfo "DIAGNOSTIC Wallpaper - Début copie..."
            Copy-Item -LiteralPath $wp -Destination $dst -Force -ErrorAction Stop
            Write-MWLogInfo "DIAGNOSTIC Wallpaper - Copie réussie!"

            "$fileName" | Set-Content -Path (Join-Path $wdir 'wallpaper.txt') -Encoding UTF8
            Write-MWLogInfo "DIAGNOSTIC Wallpaper - wallpaper.txt créé"

            # Vérifier que le fichier destination existe
            if (Test-Path -LiteralPath $dst) {
                $dstSize = (Get-Item -LiteralPath $dst).Length
                Write-MWLogInfo "DIAGNOSTIC Wallpaper - Fichier copié vérifié: $dstSize octets"
            }

            Write-MWLogInfo "Fond d'écran copié → $dst"
        } catch {
            Write-MWLogError "DIAGNOSTIC Wallpaper - ERREUR copie: $($_.Exception.GetType().Name)"
            Write-MWLogError "DIAGNOSTIC Wallpaper - Message: $($_.Exception.Message)"
            Write-MWLogError "DIAGNOSTIC Wallpaper - StackTrace: $($_.Exception.StackTrace)"
            Write-MWLogWarning "Fond d'écran : copie échouée depuis '$wp' : $($_.Exception.Message)"
            return
        }
    }
    catch {
        Write-MWLogError "Export fond d'écran : $($_.Exception.Message)"
    }
}

function Import-WallpaperSimple {
    param([string]$InRoot)

    try {
        Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Début import depuis: $InRoot"

        $wpDir = Join-Path $InRoot 'Wallpaper'
        Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Dossier Wallpaper: $wpDir"

        if (-not (Test-Path $wpDir)) {
            Write-MWLogWarning "DIAGNOSTIC Wallpaper Import - Dossier Wallpaper INTROUVABLE"
            Write-MWLogWarning "Fond d'écran absent - rien à restaurer"
            return
        }
        Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Dossier Wallpaper existe"

        # Lister les fichiers dans le dossier
        $files = Get-ChildItem -Path $wpDir -File -ErrorAction SilentlyContinue
        Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Fichiers trouvés: $($files.Count)"
        foreach ($f in $files) {
            Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Fichier: $($f.Name) ($($f.Length) octets)"
        }

        $txt = Join-Path $wpDir 'wallpaper.txt'
        Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Vérif wallpaper.txt: $txt"

        $fileName = $null
        if (Test-Path $txt) {
            $fileName = (Get-Content $txt -Raw).Trim()
            Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - wallpaper.txt contenu: '$fileName'"
        } else {
            Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - wallpaper.txt ABSENT"
        }

        $img = $null
        if ($fileName) {
            $img = Join-Path $wpDir $fileName
            Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Image depuis txt: $img"
        }
        else {
            $cand = Get-ChildItem $wpDir -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cand) {
                $img = $cand.FullName
                Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Image premier fichier: $img"
            } else {
                Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Aucun fichier trouvé dans le dossier"
            }
        }

        if ($img) {
            $imgExists = Test-Path -LiteralPath $img
            Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Image existe: $imgExists (path: $img)"

            if ($imgExists) {
                $imgSize = (Get-Item -LiteralPath $img).Length
                Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Taille image: $imgSize octets"
                Write-MWLogInfo "DIAGNOSTIC Wallpaper Import - Appel Set-WallpaperSafe..."
                Set-WallpaperSafe -ImagePath $img
            } else {
                Write-MWLogWarning "DIAGNOSTIC Wallpaper Import - Image path calculé mais fichier INTROUVABLE"
            }
        }
        else {
            Write-MWLogWarning "DIAGNOSTIC Wallpaper Import - Aucune image détectée (img = null)"
            Write-MWLogWarning "Fond d'écran : aucune image trouvée"
        }
    }
    catch {
        Write-MWLogError "DIAGNOSTIC Wallpaper Import - Exception: $($_.Exception.GetType().Name)"
        Write-MWLogError "DIAGNOSTIC Wallpaper Import - Message: $($_.Exception.Message)"
        Write-MWLogError "Import fond d'écran : $($_.Exception.Message)"
    }
}

function Set-WallpaperSafe {
    param([Parameter(Mandatory)][string]$ImagePath)

    try {
        Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - ImagePath reçu: $ImagePath"

        if (-not (Test-Path -LiteralPath $ImagePath)) {
            Write-MWLogError "DIAGNOSTIC Set-WallpaperSafe - Image INTROUVABLE à ce chemin!"
            throw "Image introuvable: $ImagePath"
        }
        Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Image existe"

        # 1) Copie sous C:\Logicia\Wallpaper
        $root = 'C:\Logicia\Wallpaper'
        Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Création dossier Logicia: $root"
        try {
            New-Item -ItemType Directory -Force -Path $root | Out-Null
        }
        catch {
            Write-MWLogWarning "DIAGNOSTIC Set-WallpaperSafe - Création dossier échouée: $($_.Exception.Message)"
        }

        $dst = Join-Path $root (Split-Path $ImagePath -Leaf)
        Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Copie vers: $dst"
        Copy-Item -LiteralPath $ImagePath -Destination $dst -Force
        $ImagePath = $dst
        Write-MWLogInfo "Fond d'écran : image copiée → $ImagePath"

        # 2) Tentative API DesktopWallpaper (Win8+)
        $ok = $false
        Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Tentative 1: DesktopWallpaper COM"
        try {
            $dw = New-Object -ComObject DesktopWallpaper
            if ($dw) {
                Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - COM object créé, appel SetWallpaper..."
                $dw.SetWallpaper('', $ImagePath) | Out-Null
                $ok = $true
                Write-MWLogInfo "Fond d'écran appliqué via DesktopWallpaper"
                Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - DesktopWallpaper SUCCÈS"
            } else {
                Write-MWLogWarning "DIAGNOSTIC Set-WallpaperSafe - COM object null"
            }
        }
        catch {
            Write-MWLogWarning "DIAGNOSTIC Set-WallpaperSafe - DesktopWallpaper Exception: $($_.Exception.Message)"
            Write-MWLogWarning "DesktopWallpaper KO : $($_.Exception.Message)"
        }

        # 3) Fallback : SPI + refresh Explorer
        if (-not $ok) {
            Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Tentative 2: SystemParametersInfo"
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
                    Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Add-Type WP class"
                    Add-Type $sig -ErrorAction SilentlyContinue
                }
                Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - Appel SystemParametersInfo(20, 0, '$ImagePath', 3)"
                $spiResult = [WP]::SystemParametersInfo(20, 0, $ImagePath, 1 -bor 2)
                Write-MWLogInfo "DIAGNOSTIC Set-WallpaperSafe - SystemParametersInfo retour: $spiResult"
                Write-MWLogInfo "Fond d'écran appliqué via SystemParametersInfo"
                $ok = $true
            }
            catch {
                Write-MWLogWarning "SPI KO : $($_.Exception.Message)"
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

        # NOUVELLE APPROCHE: Capturer les positions via COM Shell.Application
        Write-MWLogInfo "Capture des positions d'icônes du bureau..."

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        } catch {}

        # Sauvegarder résolution écran pour référence
        try {
            $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
            [pscustomobject]@{
                Width  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
                Height = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
                DpiX   = [int]$g.DpiX
                DpiY   = [int]$g.DpiY
            } | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir 'screen.json') -Encoding UTF8
            $g.Dispose()
        } catch {}

        # Nouvelle méthode: Sauvegarder liste des icônes et leurs noms
        # Windows ne permet pas facilement de lire les positions via API,
        # donc on sauvegarde juste la liste des fichiers du bureau
        $desktopItems = @()

        $userDesktop = [Environment]::GetFolderPath('Desktop')
        $publicDesktop = 'C:\Users\Public\Desktop'

        foreach ($desktopPath in @($userDesktop, $publicDesktop)) {
            if (Test-Path $desktopPath) {
                Get-ChildItem -LiteralPath $desktopPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $desktopItems += [PSCustomObject]@{
                        Name = $_.Name
                        FullName = $_.FullName
                        IsFolder = $_.PSIsContainer
                        Source = if ($desktopPath -eq $publicDesktop) { 'Public' } else { 'User' }
                    }
                }
            }
        }

        $desktopItems | Export-Clixml -Path (Join-Path $OutDir 'desktop_icons.xml') -Encoding UTF8
        Write-MWLogInfo "Desktop: $($desktopItems.Count) icône(s) référencée(s)"

        # IMPORTANT: Ne plus utiliser les exports registry qui ne fonctionnent pas bien
        # À la place, on force juste un refresh du bureau à l'import

        Write-MWLogInfo "Desktop Layout exporté (nouvelle méthode simplifiée)"
    }
    catch {
        Write-MWLogError "Save-DesktopLayout : $($_.Exception.Message)"
    }
}

function Restore-DesktopLayout {
    param([Parameter(Mandatory)][string]$InDir)

    try {
        # NOUVELLE APPROCHE SIMPLIFIÉE:
        # Au lieu d'essayer de restaurer les positions exactes (ce qui ne fonctionne pas bien),
        # on vérifie juste que les fichiers/raccourcis du bureau sont toujours présents
        # et on force un refresh propre du bureau

        $iconsFile = Join-Path $InDir 'desktop_icons.xml'

        if (Test-Path $iconsFile) {
            try {
                $desktopItems = Import-Clixml -Path $iconsFile
                Write-MWLogInfo "Desktop: $($desktopItems.Count) icône(s) de référence chargée(s)"

                # Vérifier que les icônes existent toujours
                $missing = @()
                foreach ($item in $desktopItems) {
                    if (-not (Test-Path $item.FullName -ErrorAction SilentlyContinue)) {
                        $missing += $item.Name
                    }
                }

                if ($missing.Count -gt 0) {
                    Write-MWLogWarning "Desktop: $($missing.Count) icône(s) manquante(s): $($missing -join ', ')"
                } else {
                    Write-MWLogInfo "Desktop: Toutes les icônes sont présentes"
                }
            } catch {
                Write-MWLogWarning "Impossible de charger desktop_icons.xml : $($_.Exception.Message)"
            }
        }

        # Forcer un refresh du bureau via COM
        try {
            Write-MWLogInfo "Actualisation du bureau..."

            # Méthode 1: Envoyer message F5 au bureau
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Desktop {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public const uint WM_COMMAND = 0x0111;
    public const uint MIN_ALL = 419;
    public const uint MIN_ALL_UNDO = 416;
}
"@ -ErrorAction SilentlyContinue

            $shell = [Desktop]::FindWindow("Shell_TrayWnd", $null)
            if ($shell -ne [IntPtr]::Zero) {
                # Minimiser tout puis restaurer pour forcer le refresh
                [Desktop]::SendMessage($shell, [Desktop]::WM_COMMAND, [Desktop]::MIN_ALL, [IntPtr]::Zero) | Out-Null
                Start-Sleep -Milliseconds 200
                [Desktop]::SendMessage($shell, [Desktop]::WM_COMMAND, [Desktop]::MIN_ALL_UNDO, [IntPtr]::Zero) | Out-Null
            }

            # Méthode 2: Redémarrer Explorer (plus agressif mais efficace)
            Write-MWLogInfo "Redémarrage d'Explorer pour actualiser le bureau..."
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Start-Process explorer.exe
            Start-Sleep -Seconds 1

            Write-MWLogInfo "Bureau actualisé"
        } catch {
            Write-MWLogWarning "Actualisation du bureau échouée : $($_.Exception.Message)"
        }

        Write-MWLogInfo "Desktop Layout restauré (nouvelle méthode)"
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
            if ($props) {
                # Compter seulement les vraies propriétés de registre (exclure PSPath, PSParentPath, etc.)
                $realProps = $props.PSObject.Properties | Where-Object {
                    $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider)$'
                }

                if ($realProps -and ($realProps | Measure-Object).Count -gt 0) {
                    & reg.exe export $RawPath $DestFile /y 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-MWLogInfo "Reg export → $DestFile"
                    } else {
                        Write-MWLogWarning "Reg export échoué (code $LASTEXITCODE) → $RawPath"
                    }
                }
                else {
                    Write-MWLogWarning "Reg présent mais vide → $RawPath (export ignoré)"
                }
            }
            else {
                Write-MWLogWarning "Reg inaccessible → $RawPath"
            }
        }
        else {
            Write-MWLogWarning "Reg absent → $RawPath (export ignoré)"
        }
    }
    catch {
        Write-MWLogError "Reg export $RawPath : $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Export-WallpaperDesktop, Import-WallpaperDesktop

