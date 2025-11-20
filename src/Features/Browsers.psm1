# src/Features/Browsers.psm1

function Stop-MWBrowserProcesses {
    param(
        [bool]$Chrome,
        [bool]$Edge,
        [bool]$Firefox
    )

    try {
        if ($Chrome) {
            $p = Get-Process -Name 'chrome' -ErrorAction SilentlyContinue
            if ($p) {
                Write-MWLogInfo "Arrêt des processus Chrome."
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }

        if ($Edge) {
            $p = Get-Process -Name 'msedge' -ErrorAction SilentlyContinue
            if ($p) {
                Write-MWLogInfo "Arrêt des processus Edge."
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }

        if ($Firefox) {
            $p = Get-Process -Name 'firefox' -ErrorAction SilentlyContinue
            if ($p) {
                Write-MWLogInfo "Arrêt des processus Firefox."
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-MWLogWarning "Stop-MWBrowserProcesses : $($_.Exception.Message)"
    }
}

function Export-MWBrowsers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        [bool]$Chrome  = $true,
        [bool]$Edge    = $true,
        [bool]$Firefox = $true
    )
    <#
        .SYNOPSIS
            Exporte les données AppData des navigateurs.
        .DESCRIPTION
            - Chrome stable : %LOCALAPPDATA%\Google\Chrome\User Data
            - Chrome bêta  : %LOCALAPPDATA%\Google\Chrome Beta\User Data
            - Edge         : %LOCALAPPDATA%\Microsoft\Edge\User Data
            - Firefox      : %APPDATA%\Mozilla\Firefox\Profiles
    #>

    try {
        $base = Join-Path $DestinationFolder 'AppDataBrowsers'
        if (-not (Test-Path -LiteralPath $base)) {
            New-Item -ItemType Directory -Path $base -Force | Out-Null
        }

        # On arrête les navigateurs avant la copie
        Stop-MWBrowserProcesses -Chrome:$Chrome -Edge:$Edge -Firefox:$Firefox

        if ($Chrome) {
            try {
                $chromeStablePath = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
                $chromeBetaPath   = Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'

                if (Test-Path -LiteralPath $chromeBetaPath) {
                    $srcC = $chromeBetaPath
                    Write-MWLogInfo "Chrome Beta détecté : $srcC"
                } elseif (Test-Path -LiteralPath $chromeStablePath) {
                    $srcC = $chromeStablePath
                    Write-MWLogInfo "Chrome (stable) détecté : $srcC"
                } else {
                    Write-MWLogWarning "Chrome : aucun dossier AppData trouvé (ni stable, ni Beta)."
                    $srcC = $null
                }

                if ($srcC) {
                    $dstC = Join-Path $base 'Chrome'
                    if (-not (Test-Path -LiteralPath $dstC)) {
                        New-Item -ItemType Directory -Path $dstC -Force | Out-Null
                    }

                    Write-MWLogInfo "Export AppData Chrome depuis '$srcC' vers '$dstC'."
                    Get-ChildItem -LiteralPath $srcC -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstC -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Chrome export - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Chrome exporté."
                }
            } catch {
                Write-MWLogError "Chrome export : $($_.Exception.Message)"
            }
        }

        if ($Edge) {
            try {
                $srcE = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
                if (Test-Path -LiteralPath $srcE) {
                    $dstE = Join-Path $base 'Edge'
                    if (-not (Test-Path -LiteralPath $dstE)) {
                        New-Item -ItemType Directory -Path $dstE -Force | Out-Null
                    }

                    Write-MWLogInfo "Export AppData Edge depuis '$srcE' vers '$dstE'."
                    Get-ChildItem -LiteralPath $srcE -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstE -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Edge export - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Edge exporté."
                } else {
                    Write-MWLogWarning "Edge : dossier AppData introuvable : $srcE"
                }
            } catch {
                Write-MWLogError "Edge export : $($_.Exception.Message)"
            }
        }

        if ($Firefox) {
            try {
                $srcF = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
                if (Test-Path -LiteralPath $srcF) {
                    $dstF = Join-Path $base 'Firefox'
                    if (-not (Test-Path -LiteralPath $dstF)) {
                        New-Item -ItemType Directory -Path $dstF -Force | Out-Null
                    }

                    Write-MWLogInfo "Export AppData Firefox depuis '$srcF' vers '$dstF'."
                    Get-ChildItem -LiteralPath $srcF -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstF -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Firefox export - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Firefox exporté."
                } else {
                    Write-MWLogWarning "Firefox : dossier AppData introuvable : $srcF"
                }
            } catch {
                Write-MWLogError "Firefox export : $($_.Exception.Message)"
            }
        }
    } catch {
        Write-MWLogError "Export AppDataBrowsers : $($_.Exception.Message)"
        throw
    }
}

function Import-MWBrowsers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,

        [bool]$Chrome  = $true,
        [bool]$Edge    = $true,
        [bool]$Firefox = $true
    )
    <#
        .SYNOPSIS
            Importe les données AppData des navigateurs.
    #>

    try {
        $base = Join-Path $SourceFolder 'AppDataBrowsers'
        if (-not (Test-Path -LiteralPath $base -PathType Container)) {
            Write-MWLogWarning "AppDataBrowsers absent — rien à restaurer."
            return
        }

        # On arrête les navigateurs avant la copie
        Stop-MWBrowserProcesses -Chrome:$Chrome -Edge:$Edge -Firefox:$Firefox

        if ($Chrome) {
            try {
                $srcC = Join-Path $base 'Chrome'

                # On choisit la cible : Beta si déjà présente, sinon stable
                $dstStable = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
                $dstBeta   = Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'

                if (Test-Path -LiteralPath $dstBeta) {
                    $dstC = $dstBeta
                    Write-MWLogInfo "Import Chrome vers Chrome Beta : $dstC"
                } elseif (Test-Path -LiteralPath $dstStable) {
                    $dstC = $dstStable
                    Write-MWLogInfo "Import Chrome vers Chrome stable : $dstC"
                } else {
                    $dstC = $dstStable
                    Write-MWLogInfo "Création du dossier Chrome stable : $dstC"
                    New-Item -ItemType Directory -Path $dstC -Force | Out-Null
                }

                if (Test-Path -LiteralPath $srcC -PathType Container) {
                    Write-MWLogInfo "Import AppData Chrome depuis '$srcC' vers '$dstC'."
                    Get-ChildItem -LiteralPath $srcC -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstC -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Chrome import - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Chrome importé."
                } else {
                    Write-MWLogInfo "Chrome : aucun dossier source trouvé dans AppDataBrowsers."
                }
            } catch {
                Write-MWLogError "Chrome import : $($_.Exception.Message)"
            }
        }

        if ($Edge) {
            try {
                $srcE = Join-Path $base 'Edge'
                $dstE = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'

                if (Test-Path -LiteralPath $srcE -PathType Container) {
                    if (-not (Test-Path -LiteralPath $dstE)) {
                        New-Item -ItemType Directory -Path $dstE -Force | Out-Null
                    }

                    Write-MWLogInfo "Import AppData Edge depuis '$srcE' vers '$dstE'."
                    Get-ChildItem -LiteralPath $srcE -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstE -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Edge import - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Edge importé."
                } else {
                    Write-MWLogInfo "Edge : aucun dossier source trouvé dans AppDataBrowsers."
                }
            } catch {
                Write-MWLogError "Edge import : $($_.Exception.Message)"
            }
        }

        if ($Firefox) {
            try {
                $srcF = Join-Path $base 'Firefox'
                $dstF = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'

                if (Test-Path -LiteralPath $srcF -PathType Container) {
                    if (-not (Test-Path -LiteralPath $dstF)) {
                        New-Item -ItemType Directory -Path $dstF -Force | Out-Null
                    }

                    Write-MWLogInfo "Import AppData Firefox depuis '$srcF' vers '$dstF'."
                    Get-ChildItem -LiteralPath $srcF -Force | ForEach-Object {
                        $item = $_
                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $dstF -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning "Firefox import - erreur sur '$($item.FullName)' : $($_.Exception.Message)"
                        }
                    }
                    Write-MWLogInfo "AppData Firefox importé."
                } else {
                    Write-MWLogInfo "Firefox : aucun dossier source trouvé dans AppDataBrowsers."
                }
            } catch {
                Write-MWLogError "Firefox import : $($_.Exception.Message)"
            }
        }
    } catch {
        Write-MWLogError "Import AppDataBrowsers : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWBrowsers, Import-MWBrowsers
