# src/Features/BrowserDetection.psm1
# Module de détection des navigateurs installés pour l'UI

function Get-MWInstalledBrowsers {
    <#
    .SYNOPSIS
    Détecte tous les navigateurs installés sur le système
    
    .DESCRIPTION
    Scanne les emplacements standards pour détecter :
    - Chrome (Stable, Beta, Dev, Canary)
    - Edge (Stable, Beta, Dev, Canary)
    - Firefox (Stable, Developer Edition, Nightly)
    - Opera (Stable, GX)
    - Brave
    - Vivaldi
    - Tor Browser
    - Waterfax
    - LibreWolf
    
    .OUTPUTS
    Array d'objets avec : Name, DisplayName, Path, Icon, AppDataPath, Instructions
    #>
    
    $browsers = @()
    
    # ==================== CHROME ====================
    
    # Chrome Stable
    $chromePath = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
        $browsers += @{
            Name = 'Chrome'
            DisplayName = 'Google Chrome'
            Path = $chromePath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
            Instructions = @"
1. Ouvrez Chrome (cliquez sur la tuile ci-dessus)
2. Tapez chrome://settings/passwords dans la barre d'adresse
3. Cliquez sur l'icône ⋮ (trois points) à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Confirmez avec votre mot de passe Windows si demandé
6. Enregistrez le fichier CSV dans un emplacement sûr
"@
        }
    }
    
    # Chrome Beta
    $chromeBetaPath = "${env:ProgramFiles}\Google\Chrome Beta\Application\chrome.exe"
    if (Test-Path $chromeBetaPath) {
        $browsers += @{
            Name = 'ChromeBeta'
            DisplayName = 'Google Chrome Beta'
            Path = $chromeBetaPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'
            Instructions = @"
1. Ouvrez Chrome Beta (cliquez sur la tuile ci-dessus)
2. Tapez chrome://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # Chrome Dev
    $chromeDevPath = "${env:ProgramFiles}\Google\Chrome Dev\Application\chrome.exe"
    if (Test-Path $chromeDevPath) {
        $browsers += @{
            Name = 'ChromeDev'
            DisplayName = 'Google Chrome Dev'
            Path = $chromeDevPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Dev\User Data'
            Instructions = @"
1. Ouvrez Chrome Dev (cliquez sur la tuile ci-dessus)
2. Tapez chrome://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # Chrome Canary
    $chromeCanaryPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\Application\chrome.exe'
    if (Test-Path $chromeCanaryPath) {
        $browsers += @{
            Name = 'ChromeCanary'
            DisplayName = 'Google Chrome Canary'
            Path = $chromeCanaryPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\User Data'
            Instructions = @"
1. Ouvrez Chrome Canary (cliquez sur la tuile ci-dessus)
2. Tapez chrome://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== EDGE ====================
    
    # Edge Stable
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgePath)) {
        $edgePath = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    }
    if (Test-Path $edgePath) {
        $browsers += @{
            Name = 'Edge'
            DisplayName = 'Microsoft Edge'
            Path = $edgePath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
            Instructions = @"
1. Ouvrez Edge (cliquez sur la tuile ci-dessus)
2. Tapez edge://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ (trois points) à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Confirmez avec votre mot de passe Windows
6. Enregistrez le fichier CSV dans un emplacement sûr
"@
        }
    }
    
    # Edge Beta
    $edgeBetaPath = "${env:ProgramFiles(x86)}\Microsoft\Edge Beta\Application\msedge.exe"
    if (-not (Test-Path $edgeBetaPath)) {
        $edgeBetaPath = "${env:ProgramFiles}\Microsoft\Edge Beta\Application\msedge.exe"
    }
    if (Test-Path $edgeBetaPath) {
        $browsers += @{
            Name = 'EdgeBeta'
            DisplayName = 'Microsoft Edge Beta'
            Path = $edgeBetaPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Beta\User Data'
            Instructions = @"
1. Ouvrez Edge Beta (cliquez sur la tuile ci-dessus)
2. Tapez edge://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # Edge Dev
    $edgeDevPath = "${env:ProgramFiles(x86)}\Microsoft\Edge Dev\Application\msedge.exe"
    if (-not (Test-Path $edgeDevPath)) {
        $edgeDevPath = "${env:ProgramFiles}\Microsoft\Edge Dev\Application\msedge.exe"
    }
    if (Test-Path $edgeDevPath) {
        $browsers += @{
            Name = 'EdgeDev'
            DisplayName = 'Microsoft Edge Dev'
            Path = $edgeDevPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Dev\User Data'
            Instructions = @"
1. Ouvrez Edge Dev (cliquez sur la tuile ci-dessus)
2. Tapez edge://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # Edge Canary
    $edgeCanaryPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge SxS\Application\msedge.exe'
    if (Test-Path $edgeCanaryPath) {
        $browsers += @{
            Name = 'EdgeCanary'
            DisplayName = 'Microsoft Edge Canary'
            Path = $edgeCanaryPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge SxS\User Data'
            Instructions = @"
1. Ouvrez Edge Canary (cliquez sur la tuile ci-dessus)
2. Tapez edge://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== FIREFOX ====================
    
    # Firefox Stable
    $firefoxPath = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe"
    if (Test-Path $firefoxPath) {
        $browsers += @{
            Name = 'Firefox'
            DisplayName = 'Mozilla Firefox'
            Path = $firefoxPath
            AppDataPath = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
            Instructions = @"
1. Ouvrez Firefox (cliquez sur la tuile ci-dessus)
2. Cliquez sur le menu ☰ (trois lignes) en haut à droite
3. Allez dans Paramètres → Vie privée et sécurité
4. Dans la section "Identifiants et mots de passe", cliquez sur "Identifiants enregistrés"
5. Cliquez sur ⋮ (trois points) puis "Exporter les identifiants"
6. Confirmez et enregistrez le fichier CSV
"@
        }
    }
    
    # Firefox Developer Edition
    $firefoxDevPath = "${env:ProgramFiles}\Firefox Developer Edition\firefox.exe"
    if (Test-Path $firefoxDevPath) {
        $browsers += @{
            Name = 'FirefoxDev'
            DisplayName = 'Firefox Developer Edition'
            Path = $firefoxDevPath
            AppDataPath = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
            Instructions = @"
1. Ouvrez Firefox Developer Edition (cliquez sur la tuile ci-dessus)
2. Menu ☰ → Paramètres → Vie privée et sécurité
3. "Identifiants et mots de passe" → "Identifiants enregistrés"
4. Cliquez sur ⋮ → "Exporter les identifiants"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # Firefox Nightly
    $firefoxNightlyPath = "${env:ProgramFiles}\Firefox Nightly\firefox.exe"
    if (Test-Path $firefoxNightlyPath) {
        $browsers += @{
            Name = 'FirefoxNightly'
            DisplayName = 'Firefox Nightly'
            Path = $firefoxNightlyPath
            AppDataPath = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
            Instructions = @"
1. Ouvrez Firefox Nightly (cliquez sur la tuile ci-dessus)
2. Menu ☰ → Paramètres → Vie privée et sécurité
3. "Identifiants et mots de passe" → "Identifiants enregistrés"
4. Cliquez sur ⋮ → "Exporter les identifiants"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== OPERA ====================
    
    # Opera Stable
    $operaPath = Join-Path $env:LOCALAPPDATA 'Programs\Opera\opera.exe'
    if (Test-Path $operaPath) {
        $browsers += @{
            Name = 'Opera'
            DisplayName = 'Opera'
            Path = $operaPath
            AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera Stable'
            Instructions = @"
1. Ouvrez Opera (cliquez sur la tuile ci-dessus)
2. Tapez opera://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # Opera GX
    $operaGXPath = Join-Path $env:LOCALAPPDATA 'Programs\Opera GX\opera.exe'
    if (Test-Path $operaGXPath) {
        $browsers += @{
            Name = 'OperaGX'
            DisplayName = 'Opera GX'
            Path = $operaGXPath
            AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera GX Stable'
            Instructions = @"
1. Ouvrez Opera GX (cliquez sur la tuile ci-dessus)
2. Tapez opera://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ → "Exporter les mots de passe"
4. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== BRAVE ====================
    
    $bravePath = "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
    if (Test-Path $bravePath) {
        $browsers += @{
            Name = 'Brave'
            DisplayName = 'Brave'
            Path = $bravePath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
            Instructions = @"
1. Ouvrez Brave (cliquez sur la tuile ci-dessus)
2. Tapez brave://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== VIVALDI ====================
    
    $vivaldiPath = Join-Path $env:LOCALAPPDATA 'Vivaldi\Application\vivaldi.exe'
    if (Test-Path $vivaldiPath) {
        $browsers += @{
            Name = 'Vivaldi'
            DisplayName = 'Vivaldi'
            Path = $vivaldiPath
            AppDataPath = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'
            Instructions = @"
1. Ouvrez Vivaldi (cliquez sur la tuile ci-dessus)
2. Tapez vivaldi://settings/passwords dans la barre d'adresse
3. Cliquez sur ⋮ à côté de "Mots de passe enregistrés"
4. Sélectionnez "Exporter les mots de passe"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== TOR BROWSER ====================
    
    # Tor peut être installé n'importe où, on cherche dans les emplacements communs
    $torPaths = @(
        "${env:USERPROFILE}\Desktop\Tor Browser\Browser\firefox.exe",
        "${env:LOCALAPPDATA}\Tor Browser\Browser\firefox.exe",
        "C:\Tor Browser\Browser\firefox.exe"
    )
    
    foreach ($torPath in $torPaths) {
        if (Test-Path $torPath) {
            $browsers += @{
                Name = 'TorBrowser'
                DisplayName = 'Tor Browser'
                Path = $torPath
                AppDataPath = $null  # Tor utilise son propre profil portable
                Instructions = @"
1. Ouvrez Tor Browser (cliquez sur la tuile ci-dessus)
2. Note : Tor Browser n'a pas de fonction d'export natif des mots de passe
3. Les mots de passe sont stockés dans le profil Firefox intégré
4. Pour une migration manuelle, copiez le dossier du profil Tor Browser
"@
            }
            break
        }
    }
    
    # ==================== WATERFOX ====================
    
    $waterfoxPath = "${env:ProgramFiles}\Waterfox\waterfox.exe"
    if (Test-Path $waterfoxPath) {
        $browsers += @{
            Name = 'Waterfox'
            DisplayName = 'Waterfox'
            Path = $waterfoxPath
            AppDataPath = Join-Path $env:APPDATA 'Waterfox\Profiles'
            Instructions = @"
1. Ouvrez Waterfox (cliquez sur la tuile ci-dessus)
2. Menu ☰ → Paramètres → Vie privée et sécurité
3. "Identifiants et mots de passe" → "Identifiants enregistrés"
4. Cliquez sur ⋮ → "Exporter les identifiants"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    # ==================== LIBREWOLF ====================
    
    $librewolfPath = "${env:ProgramFiles}\LibreWolf\librewolf.exe"
    if (Test-Path $librewolfPath) {
        $browsers += @{
            Name = 'LibreWolf'
            DisplayName = 'LibreWolf'
            Path = $librewolfPath
            AppDataPath = Join-Path $env:APPDATA 'LibreWolf\Profiles'
            Instructions = @"
1. Ouvrez LibreWolf (cliquez sur la tuile ci-dessus)
2. Menu ☰ → Paramètres → Vie privée et sécurité
3. "Identifiants et mots de passe" → "Identifiants enregistrés"
4. Cliquez sur ⋮ → "Exporter les identifiants"
5. Enregistrez le fichier CSV
"@
        }
    }
    
    return $browsers
}

function Get-MWBrowserIcon {
    <#
    .SYNOPSIS
    Extrait l'icône d'un navigateur depuis son exécutable
    
    .PARAMETER BrowserPath
    Chemin vers l'exécutable du navigateur
    
    .OUTPUTS
    System.Windows.Media.ImageSource (icône WPF)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BrowserPath
    )
    
    try {
        if (-not (Test-Path $BrowserPath)) {
            return $null
        }
        
        # Extraire l'icône de l'exécutable
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($BrowserPath)
        
        if ($icon) {
            # Convertir en BitmapSource WPF
            $bitmap = $icon.ToBitmap()
            $hBitmap = $bitmap.GetHbitmap()
            
            try {
                $imageSource = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
                    $hBitmap,
                    [IntPtr]::Zero,
                    [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                )
                $imageSource.Freeze()
                return $imageSource
            }
            finally {
                # Liberer les ressources GDI
                # DeleteObject pour liberer le HBITMAP
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class GDI32 {
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);
}
"@ -ErrorAction SilentlyContinue
                
                [GDI32]::DeleteObject($hBitmap) | Out-Null
                $bitmap.Dispose()
                $icon.Dispose()
            }
        }
    }
    catch {
        Write-MWLogWarning "Impossible d'extraire l'icône de $BrowserPath : $($_.Exception.Message)"
        return $null
    }
    
    return $null
}

Export-ModuleMember -Function Get-MWInstalledBrowsers, Get-MWBrowserIcon
