# src/Features/TaskbarStart.psm1

function Export-MWTaskbarStart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte le menu Démarrer (StartLayout) et les épingles de la barre des tâches.
        .DESCRIPTION
            - Crée DestinationFolder\UI
            - Tente un Export-StartLayout (Windows 10/11, selon édition)
            - Sauvegarde les raccourcis épinglés de la barre des tâches
    #>

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }

        $uiDir = Join-Path $DestinationFolder 'UI'
        if (-not (Test-Path -LiteralPath $uiDir)) {
            New-Item -ItemType Directory -Path $uiDir -Force | Out-Null
        }

        #
        # 1) Export StartLayout (best-effort, comme ton ancien script)
        #
        if (Get-Command -Name 'Export-StartLayout' -ErrorAction SilentlyContinue) {
            try {
                $layout = Join-Path $uiDir 'StartLayout.xml'

                $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                $argList = @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-Command',
                    "Export-StartLayout -UseDesktopApplicationID -Path '$layout'"
                )

                $proc = Start-Process -FilePath $cmd -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
                $rc   = $null
                if ($proc) { $rc = $proc.ExitCode } else { $rc = -1 }

                if ((Test-Path -LiteralPath $layout) -and ($rc -eq 0)) {
                    Write-MWLogInfo ("StartLayout exporté -> {0}" -f $layout)
                } else {
                    Write-MWLogWarning ("StartLayout export : rc={0} (cmdlet dispo mais pas forcément implémentée sur cette édition)" -f $rc)
                }
            } catch {
                Write-MWLogWarning ("StartLayout export (cmdlet) : {0}" -f $_.Exception.Message)
            }
        } else {
            Write-MWLogWarning "Export-StartLayout indisponible sur cette édition de Windows. StartLayout non exporté."
        }

        #
        # 2) Épingles de la barre des tâches
        #
        try {
            $pinsDir = Join-Path $uiDir 'Taskbar_Pinned'
            if (-not (Test-Path -LiteralPath $pinsDir)) {
                New-Item -ItemType Directory -Force -Path $pinsDir | Out-Null
            }

            $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'

            if (Test-Path -LiteralPath $taskbarPins) {
                # Copie récursive des raccourcis épinglés
                Get-ChildItem -LiteralPath $taskbarPins -Recurse -Force | ForEach-Object {
                    $item = $_
                    $relative = $item.FullName.Substring($taskbarPins.Length).TrimStart('\')
                    $target   = Join-Path $pinsDir $relative

                    if ($item.PSIsContainer) {
                        if (-not (Test-Path -LiteralPath $target)) {
                            try {
                                New-Item -ItemType Directory -Path $target -Force | Out-Null
                            } catch {
                                Write-MWLogWarning ("Taskbar export : impossible de créer le dossier '{0}' : {1}" -f $target, $_.Exception.Message)
                            }
                        }
                    } else {
                        $targetDir = Split-Path -Path $target -Parent
                        if (-not (Test-Path -LiteralPath $targetDir)) {
                            try {
                                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                            } catch {
                                Write-MWLogWarning ("Taskbar export : impossible de créer le dossier '{0}' : {1}" -f $targetDir, $_.Exception.Message)
                            }
                        }

                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning ("Taskbar export : erreur lors de la copie de '{0}' : {1}" -f $item.FullName, $_.Exception.Message)
                        }
                    }
                }

                Write-MWLogInfo "Taskbar pinned exporté."
            } else {
                Write-MWLogInfo "Dossier Taskbar pinned introuvable, rien à exporter (profil sans épingles classiques ?)."
            }
        } catch {
            Write-MWLogWarning ("Taskbar pinned export : {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-MWLogError ("Export-MWTaskbarStart : {0}" -f $_.Exception.Message)
        throw
    }
}

function Import-MWTaskbarStart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe le menu Démarrer et les épingles de la barre des tâches.
        .DESCRIPTION
            - Lit SourceFolder\UI\StartLayout.xml si présent + Import-StartLayout (best-effort)
            - Restaure les raccourcis épinglés dans le dossier TaskBar de l’utilisateur
    #>

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            Write-MWLogError ("Import-MWTaskbarStart : dossier source introuvable : {0}" -f $SourceFolder)
            return
        }

        $uiDir = Join-Path $SourceFolder 'UI'

        #
        # 1) Import StartLayout (best-effort)
        #
        $layout = Join-Path $uiDir 'StartLayout.xml'
        if (Test-Path -LiteralPath $layout) {
            if (Get-Command -Name 'Import-StartLayout' -ErrorAction SilentlyContinue) {
                try {
                    $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                    $argList = @(
                        '-NoProfile',
                        '-ExecutionPolicy', 'Bypass',
                        '-Command',
                        "Import-StartLayout -LayoutPath '$layout' -MountPath '$env:SystemDrive\'"
                    )

                    $proc = Start-Process -FilePath $cmd -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
                    $rc   = $null
                    if ($proc) { $rc = $proc.ExitCode } else { $rc = -1 }

                    Write-MWLogInfo ("StartLayout import : rc={0} (fonctionnalité dépendante de l’édition de Windows)" -f $rc)
                } catch {
                    Write-MWLogWarning ("StartLayout import (cmdlet) : {0}" -f $_.Exception.Message)
                }
            } else {
                Write-MWLogWarning "Import-StartLayout indisponible sur cette édition, StartLayout non appliqué."
            }
        } else {
            Write-MWLogInfo "Aucun StartLayout.xml présent dans 'UI', pas d’import du menu Démarrer."
        }

        #
        # 2) Import des épingles de la barre des tâches
        #
        try {
            $pinsDir = Join-Path $uiDir 'Taskbar_Pinned'
            $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'

            if (Test-Path -LiteralPath $pinsDir) {
                if (-not (Test-Path -LiteralPath $taskbarPins)) {
                    New-Item -ItemType Directory -Force -Path $taskbarPins | Out-Null
                }

                Get-ChildItem -LiteralPath $pinsDir -Recurse -Force | ForEach-Object {
                    $item = $_
                    $relative = $item.FullName.Substring($pinsDir.Length).TrimStart('\')
                    $target   = Join-Path $taskbarPins $relative

                    if ($item.PSIsContainer) {
                        if (-not (Test-Path -LiteralPath $target)) {
                            try {
                                New-Item -ItemType Directory -Path $target -Force | Out-Null
                            } catch {
                                Write-MWLogWarning ("Taskbar import : impossible de créer le dossier '{0}' : {1}" -f $target, $_.Exception.Message)
                            }
                        }
                    } else {
                        $targetDir = Split-Path -Path $target -Parent
                        if (-not (Test-Path -LiteralPath $targetDir)) {
                            try {
                                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                            } catch {
                                Write-MWLogWarning ("Taskbar import : impossible de créer le dossier '{0}' : {1}" -f $targetDir, $_.Exception.Message)
                            }
                        }

                        try {
                            Copy-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
                        } catch {
                            Write-MWLogWarning ("Taskbar import : erreur lors de la copie de '{0}' : {1}" -f $item.FullName, $_.Exception.Message)
                        }
                    }
                }

                Write-MWLogInfo "Taskbar pinned importé."
            } else {
                Write-MWLogInfo "Taskbar_Pinned absent dans 'UI', aucune épingle à restaurer."
            }
        } catch {
            Write-MWLogWarning ("Taskbar pinned import : {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-MWLogError ("Import-MWTaskbarStart : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWTaskbarStart, Import-MWTaskbarStart
