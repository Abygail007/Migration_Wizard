# src/Features/Browsers.psm1
# Module d'export/import AppData des navigateurs

function Stop-MWBrowserProcesses {
    <#
    .SYNOPSIS
    Arrete les processus des navigateurs specifies
    
    .PARAMETER BrowserNames
    Array des noms de navigateurs a arreter (ex: @('Chrome', 'Edge', 'Firefox'))
    Si vide, n'arrete rien
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$BrowserNames = @()
    )

    if ($BrowserNames.Count -eq 0) {
        Write-MWLogInfo "Aucun navigateur a arreter"
        return
    }

    try {
        # Mapping navigateur -> nom de processus
        $processMap = @{
            'Chrome'         = 'chrome'
            'ChromeBeta'     = 'chrome'
            'ChromeDev'      = 'chrome'
            'ChromeCanary'   = 'chrome'
            'Edge'           = 'msedge'
            'EdgeBeta'       = 'msedge'
            'EdgeDev'        = 'msedge'
            'EdgeCanary'     = 'msedge'
            'Firefox'        = 'firefox'
            'FirefoxDev'     = 'firefox'
            'FirefoxNightly' = 'firefox'
            'Opera'          = 'opera'
            'OperaGX'        = 'opera'
            'Brave'          = 'brave'
            'Vivaldi'        = 'vivaldi'
            'Waterfox'       = 'waterfox'
            'LibreWolf'      = 'librewolf'
        }
        
        # Collecter les processus uniques a arreter
        $processesToStop = @()
        foreach ($browserName in $BrowserNames) {
            if ($processMap.ContainsKey($browserName)) {
                $procName = $processMap[$browserName]
                if ($processesToStop -notcontains $procName) {
                    $processesToStop += $procName
                }
            }
        }
        
        # Arreter chaque processus
        foreach ($procName in $processesToStop) {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($procs) {
                Write-MWLogInfo "Arret des processus $procName..."
                $procs | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
        }
    } catch {
        Write-MWLogWarning "Stop-MWBrowserProcesses : $($_.Exception.Message)"
    }
}

function Export-MWBrowsers {
    <#
    .SYNOPSIS
    Exporte les donnees AppData de tous les navigateurs detectes
    
    .PARAMETER DestinationFolder
    Dossier racine de destination
    
    .PARAMETER BrowsersToExport
    Array des navigateurs a exporter (optionnel, si vide = tous detectes)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,
        
        [Parameter(Mandatory = $false)]
        [array]$BrowsersToExport = @()
    )

    try {
        $base = Join-Path $DestinationFolder 'AppDataBrowsers'
        if (-not (Test-Path -LiteralPath $base)) {
            New-Item -ItemType Directory -Path $base -Force | Out-Null
        }

        Write-MWLogInfo "Export des navigateurs : debut"
        
        # Definir tous les navigateurs a exporter avec leurs chemins AppData
        $allBrowsers = @{
            # CHROME
            'Chrome' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
                DisplayName = 'Chrome'
            }
            'ChromeBeta' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'
                DisplayName = 'Chrome Beta'
            }
            'ChromeDev' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Dev\User Data'
                DisplayName = 'Chrome Dev'
            }
            'ChromeCanary' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\User Data'
                DisplayName = 'Chrome Canary'
            }
            
            # EDGE
            'Edge' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
                DisplayName = 'Edge'
            }
            'EdgeBeta' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Beta\User Data'
                DisplayName = 'Edge Beta'
            }
            'EdgeDev' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Dev\User Data'
                DisplayName = 'Edge Dev'
            }
            'EdgeCanary' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge SxS\User Data'
                DisplayName = 'Edge Canary'
            }
            
            # FIREFOX
            'Firefox' = @{
                AppDataPath = Join-Path $env:APPDATA 'Mozilla\Firefox'
                DisplayName = 'Firefox'
            }
            'FirefoxDev' = @{
                AppDataPath = Join-Path $env:APPDATA 'Firefox Developer Edition'
                DisplayName = 'Firefox Developer Edition'
            }
            'FirefoxNightly' = @{
                AppDataPath = Join-Path $env:APPDATA 'Firefox Nightly'
                DisplayName = 'Firefox Nightly'
            }
            
            # OPERA
            'Opera' = @{
                AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera Stable'
                DisplayName = 'Opera'
            }
            'OperaGX' = @{
                AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera GX Stable'
                DisplayName = 'Opera GX'
            }
            
            # AUTRES
            'Brave' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
                DisplayName = 'Brave'
            }
            'Vivaldi' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'
                DisplayName = 'Vivaldi'
            }
            'Waterfox' = @{
                AppDataPath = Join-Path $env:APPDATA 'Waterfox'
                DisplayName = 'Waterfox'
            }
            'LibreWolf' = @{
                AppDataPath = Join-Path $env:APPDATA 'LibreWolf'
                DisplayName = 'LibreWolf'
            }
        }
        
        # Si aucun navigateur specifie, exporter tous ceux qui existent
        if ($BrowsersToExport.Count -eq 0) {
            $BrowsersToExport = $allBrowsers.Keys
        }
        
        # Arreter les processus des navigateurs selectionnes AVANT l'export
        Stop-MWBrowserProcesses -BrowserNames $BrowsersToExport
        
        $exportedCount = 0
        
        foreach ($browserKey in $BrowsersToExport) {
            if (-not $allBrowsers.ContainsKey($browserKey)) {
                Write-MWLogWarning "Navigateur inconnu : $browserKey"
                continue
            }
            
            $browser = $allBrowsers[$browserKey]
            $srcPath = $browser.AppDataPath
            $displayName = $browser.DisplayName
            
            if (Test-Path -LiteralPath $srcPath) {
                try {
                    $dstPath = Join-Path $base $browserKey
                    if (-not (Test-Path -LiteralPath $dstPath)) {
                        New-Item -ItemType Directory -Path $dstPath -Force | Out-Null
                    }
                    
                    Write-MWLogInfo "Export $displayName depuis '$srcPath'..."
                    
                    Get-ChildItem -LiteralPath $srcPath -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstPath -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "$displayName export - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    
                    Write-MWLogInfo "$displayName exporte avec succes"
                    $exportedCount++
                    
                } catch {
                    Write-MWLogError "$displayName export : $($_.Exception.Message)"
                }
            } else {
                Write-MWLogInfo "$displayName : AppData non trouve (pas installe ou deja desinstalle)"
            }
        }
        
        Write-MWLogInfo "Export des navigateurs : termine ($exportedCount navigateur(s) exporte(s))"
        
    } catch {
        Write-MWLogError "Export AppDataBrowsers : $($_.Exception.Message)"
        throw
    }
}

function Import-MWBrowsers {
    <#
    .SYNOPSIS
    Importe les donnees AppData de tous les navigateurs detectes dans l'export
    
    .PARAMETER SourceFolder
    Dossier racine source contenant AppDataBrowsers
    
    .PARAMETER BrowsersToImport
    Array des navigateurs a importer (optionnel, si vide = tous trouves)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        
        [Parameter(Mandatory = $false)]
        [array]$BrowsersToImport = @()
    )

    try {
        $base = Join-Path $SourceFolder 'AppDataBrowsers'
        if (-not (Test-Path -LiteralPath $base -PathType Container)) {
            Write-MWLogWarning "AppDataBrowsers absent - rien a restaurer."
            return
        }

        Write-MWLogInfo "Import des navigateurs : debut"
        
        # Definir tous les navigateurs avec leurs chemins de destination
        $allBrowsers = @{
            # CHROME
            'Chrome' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
                DisplayName = 'Chrome'
            }
            'ChromeBeta' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'
                DisplayName = 'Chrome Beta'
            }
            'ChromeDev' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome Dev\User Data'
                DisplayName = 'Chrome Dev'
            }
            'ChromeCanary' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Google\Chrome SxS\User Data'
                DisplayName = 'Chrome Canary'
            }
            
            # EDGE
            'Edge' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
                DisplayName = 'Edge'
            }
            'EdgeBeta' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Beta\User Data'
                DisplayName = 'Edge Beta'
            }
            'EdgeDev' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge Dev\User Data'
                DisplayName = 'Edge Dev'
            }
            'EdgeCanary' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge SxS\User Data'
                DisplayName = 'Edge Canary'
            }
            
            # FIREFOX
            'Firefox' = @{
                AppDataPath = Join-Path $env:APPDATA 'Mozilla\Firefox'
                DisplayName = 'Firefox'
            }
            'FirefoxDev' = @{
                AppDataPath = Join-Path $env:APPDATA 'Firefox Developer Edition'
                DisplayName = 'Firefox Developer Edition'
            }
            'FirefoxNightly' = @{
                AppDataPath = Join-Path $env:APPDATA 'Firefox Nightly'
                DisplayName = 'Firefox Nightly'
            }
            
            # OPERA
            'Opera' = @{
                AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera Stable'
                DisplayName = 'Opera'
            }
            'OperaGX' = @{
                AppDataPath = Join-Path $env:APPDATA 'Opera Software\Opera GX Stable'
                DisplayName = 'Opera GX'
            }
            
            # AUTRES
            'Brave' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
                DisplayName = 'Brave'
            }
            'Vivaldi' = @{
                AppDataPath = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'
                DisplayName = 'Vivaldi'
            }
            'Waterfox' = @{
                AppDataPath = Join-Path $env:APPDATA 'Waterfox'
                DisplayName = 'Waterfox'
            }
            'LibreWolf' = @{
                AppDataPath = Join-Path $env:APPDATA 'LibreWolf'
                DisplayName = 'LibreWolf'
            }
        }
        
        # Si aucun navigateur specifie, importer tous ceux qui existent dans l'export
        if ($BrowsersToImport.Count -eq 0) {
            $BrowsersToImport = (Get-ChildItem -LiteralPath $base -Directory).Name
        }
        
        # Arreter les processus des navigateurs selectionnes AVANT l'import
        Stop-MWBrowserProcesses -BrowserNames $BrowsersToImport
        
        $importedCount = 0
        
        foreach ($browserKey in $BrowsersToImport) {
            $srcPath = Join-Path $base $browserKey
            
            if (-not (Test-Path -LiteralPath $srcPath -PathType Container)) {
                Write-MWLogInfo "$browserKey : dossier source non trouve, ignore"
                continue
            }
            
            if (-not $allBrowsers.ContainsKey($browserKey)) {
                Write-MWLogWarning "Navigateur inconnu dans export : $browserKey, ignore"
                continue
            }
            
            $browser = $allBrowsers[$browserKey]
            $dstPath = $browser.AppDataPath
            $displayName = $browser.DisplayName
            
            try {
                # Creer le dossier de destination s'il n'existe pas
                if (-not (Test-Path -LiteralPath $dstPath)) {
                    Write-MWLogInfo "$displayName : creation du dossier de destination"
                    New-Item -ItemType Directory -Path $dstPath -Force | Out-Null
                }
                
                Write-MWLogInfo "Import $displayName vers '$dstPath'..."
                
                Get-ChildItem -LiteralPath $srcPath -Force | ForEach-Object {
                    $item = $_
                    try {
                        Copy-Item -LiteralPath $item.FullName -Destination $dstPath -Recurse -Force -ErrorAction Stop
                    } catch {
                        Write-MWLogWarning "$displayName import - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                    }
                }
                
                Write-MWLogInfo "$displayName importe avec succes"
                $importedCount++
                
            } catch {
                Write-MWLogError "$displayName import : $($_.Exception.Message)"
            }
        }
        
        Write-MWLogInfo "Import des navigateurs : termine ($importedCount navigateur(s) importe(s))"
        
    } catch {
        Write-MWLogError "Import AppDataBrowsers : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWBrowsers, Import-MWBrowsers, Stop-MWBrowserProcesses
