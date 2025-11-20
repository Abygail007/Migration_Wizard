# src/Features/TaskbarStart.psm1
# Gestion export / import barre des tâches + menu Démarrer

function Export-MWTaskbarAndStart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    try {
        $uiDir = Join-Path $DestinationFolder 'UI'
        if (-not (Test-Path -LiteralPath $uiDir)) {
            New-Item -ItemType Directory -Force -Path $uiDir | Out-Null
        }

        #
        # 1) Taskband (épingle barre des tâches) – export du registre
        #
        try {
            $regPath      = Join-Path $uiDir 'Taskband.reg'
            $taskbandKeyPs  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
            $taskbandKeyRaw = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"

            if (Test-Path -LiteralPath $taskbandKeyPs) {
                $props = Get-ItemProperty -Path $taskbandKeyPs -ErrorAction SilentlyContinue
                if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
                    & reg.exe export "$taskbandKeyRaw" "$regPath" /y 2>$null | Out-Null
                    if (Test-Path -LiteralPath $regPath) {
                        Write-MWLogInfo "Taskband exporté vers '$regPath'."
                    } else {
                        Write-MWLogWarning "Taskband : export tenté mais le fichier '$regPath' est introuvable."
                    }
                } else {
                    Write-MWLogInfo "Taskband présent mais sans valeurs – export ignoré."
                }
            } else {
                Write-MWLogInfo "Taskband absent – export ignoré."
            }
        } catch {
            Write-MWLogWarning ("Taskband export : {0}" -f $_.Exception.Message)
        }

        #
        # 2) StartLayout (Windows 10/11) – best effort
        #
        try {
            $layoutPath = Join-Path $uiDir 'StartLayout.xml'

            # On tente d’appeler directement Export-StartLayout (si dispo)
            if (Get-Command -Name Export-StartLayout -ErrorAction SilentlyContinue) {
                try {
                    Export-StartLayout -UseDesktopApplicationID -Path $layoutPath -ErrorAction Stop
                    if (Test-Path -LiteralPath $layoutPath) {
                        Write-MWLogInfo "StartLayout exporté vers '$layoutPath'."
                    } else {
                        Write-MWLogWarning "StartLayout : commande exécutée mais '$layoutPath' introuvable."
                    }
                } catch {
                    Write-MWLogWarning ("StartLayout export (cmdlet) : {0}" -f $_.Exception.Message)
                }
            } else {
                Write-MWLogInfo "StartLayout : cmdlet Export-StartLayout indisponible sur ce système, export ignoré."
            }
        } catch {
            Write-MWLogWarning ("StartLayout export : {0}" -f $_.Exception.Message)
        }

        #
        # 3) Épingles directes de la barre des tâches
        #
        try {
            $pinsDirExport = Join-Path $uiDir 'Taskbar_Pinned'
            if (-not (Test-Path -LiteralPath $pinsDirExport)) {
                New-Item -ItemType Directory -Force -Path $pinsDirExport | Out-Null
            }

            $taskbarPinsSrc = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
            if (Test-Path -LiteralPath $taskbarPinsSrc) {
                Copy-Item -LiteralPath $taskbarPinsSrc -Destination $pinsDirExport -Recurse -Force -ErrorAction Stop
                Write-MWLogInfo "Taskbar pinned exporté depuis '$taskbarPinsSrc' vers '$pinsDirExport'."
            } else {
                Write-MWLogInfo "Taskbar pinned : dossier source introuvable ('$taskbarPinsSrc'), export ignoré."
            }
        } catch {
            Write-MWLogWarning ("Taskbar pinned export : {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-MWLogError ("Export Taskbar/Start : {0}" -f $_.Exception.Message)
        throw
    }
}

function Import-MWTaskbarAndStart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    try {
        $uiDir = Join-Path $SourceFolder 'UI'
        if (-not (Test-Path -LiteralPath $uiDir -PathType Container)) {
            Write-MWLogWarning "UI absent dans la source – rien à restaurer pour Taskbar/Start."
            return
        }

        #
        # 1) Taskband (épingle barre des tâches)
        #
        try {
            $regPath = Join-Path $uiDir 'Taskband.reg'
            if (Test-Path -LiteralPath $regPath) {
                & reg.exe import "$regPath" 2>$null | Out-Null
                Write-MWLogInfo "Taskband importé depuis '$regPath'."
            } else {
                Write-MWLogInfo "Taskband : fichier '$regPath' introuvable, import ignoré."
            }
        } catch {
            Write-MWLogWarning ("Taskband import : {0}" -f $_.Exception.Message)
        }

        #
        # 2) StartLayout – best effort
        #
        try {
            $layoutPath = Join-Path $uiDir 'StartLayout.xml'
            if (Test-Path -LiteralPath $layoutPath) {
                if (Get-Command -Name Import-StartLayout -ErrorAction SilentlyContinue) {
                    try {
                        Import-StartLayout -LayoutPath $layoutPath -MountPath ($env:SystemDrive + "\") -ErrorAction Stop
                        Write-MWLogInfo "StartLayout importé depuis '$layoutPath'."
                    } catch {
                        Write-MWLogWarning ("StartLayout import (cmdlet) : {0}" -f $_.Exception.Message)
                    }
                } else {
                    Write-MWLogInfo "StartLayout : cmdlet Import-StartLayout indisponible sur ce système, import ignoré."
                }
            } else {
                Write-MWLogInfo "StartLayout : aucun fichier StartLayout.xml trouvé, import ignoré."
            }
        } catch {
            Write-MWLogWarning ("StartLayout import : {0}" -f $_.Exception.Message)
        }

        #
        # 3) Épingles directes Taskbar
        #
        try {
            $pinsDirImport = Join-Path $uiDir 'Taskbar_Pinned'
            $taskbarPinsDst = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'

            if (Test-Path -LiteralPath $pinsDirImport) {
                if (-not (Test-Path -LiteralPath $taskbarPinsDst)) {
                    New-Item -ItemType Directory -Force -Path $taskbarPinsDst | Out-Null
                }

                Copy-Item -LiteralPath (Join-Path $pinsDirImport '*') -Destination $taskbarPinsDst -Recurse -Force -ErrorAction Stop
                Write-MWLogInfo "Taskbar pinned importé depuis '$pinsDirImport' vers '$taskbarPinsDst'."
            } else {
                Write-MWLogInfo "Taskbar pinned : dossier d’import '$pinsDirImport' introuvable, import ignoré."
            }
        } catch {
            Write-MWLogWarning ("Taskbar pinned import : {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-MWLogError ("Import Taskbar/Start : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWTaskbarAndStart, Import-MWTaskbarAndStart
