# src/Features/UserData.psm1
# Export / import des dossiers "classiques" du profil utilisateur (hors AppData)

# Dossiers standards du profil à gérer
$script:MWUserDataFolders = @(
    @{ Key = 'Desktop';   Relative = 'Desktop';   Label = 'Bureau'             }
    @{ Key = 'Documents'; Relative = 'Documents'; Label = 'Documents'          }
    @{ Key = 'Downloads'; Relative = 'Downloads'; Label = 'Téléchargements'    }
    @{ Key = 'Pictures';  Relative = 'Pictures';  Label = 'Images'             }
    @{ Key = 'Music';     Relative = 'Music';     Label = 'Musique'            }
    @{ Key = 'Videos';    Relative = 'Videos';    Label = 'Vidéos'             }
    @{ Key = 'Favorites'; Relative = 'Favorites'; Label = 'Favoris'            }
    @{ Key = 'Links';     Relative = 'Links';     Label = 'Liens'              }
    @{ Key = 'Contacts';  Relative = 'Contacts';  Label = 'Contacts'           }
)

function Get-MWUserProfileRoot {
    [CmdletBinding()]
    param()

    # On part du USERPROFILE de l'utilisateur courant (même s'il est admin)
    $profileRoot = [Environment]::ExpandEnvironmentVariables('%USERPROFILE%')
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
        throw "Dossier profil utilisateur introuvable : $profileRoot"
    }

    return $profileRoot
}

function Copy-MWUserDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [string]$FolderName = "",

        [Parameter(Mandatory = $false)]
        [bool]$IncrementalMode = $false
    )

    try {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            Write-MWLogWarning "Copy-MWUserDirectory : source introuvable : $Source"
            return
        }

        $srcItem = Get-Item -LiteralPath $Source -ErrorAction Stop
        if ($srcItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-MWLogWarning "Copy-MWUserDirectory : source '$Source' est un reparse point, ignoré."
            return
        }

        # Crée le dossier racine destination
        if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }

        # 1) Crée les sous-dossiers (sans reparse points)
        $dirs = Get-ChildItem -LiteralPath $Source -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

        foreach ($d in $dirs) {
            $rel = $d.FullName.Substring($Source.Length).TrimStart('\','/')
            if (-not $rel) { continue }

            $destDir = Join-Path $Destination $rel
            if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                } catch {
                    Write-MWLogWarning ("Copy-MWUserDirectory : création du dossier '{0}' échouée : {1}" -f $destDir, $_.Exception.Message)
                }
            }
        }

        # 2) Copie les fichiers (en incluant cachés / système grâce à -Force)
        $files = Get-ChildItem -LiteralPath $Source -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

        $totalFiles = @($files).Count
        $fileIndex = 0
        $lastUIUpdate = [DateTime]::MinValue

        foreach ($file in $files) {
            $fileIndex++
            $Global:MWCopiedFiles++

            # Rafraîchir l'UI tous les 50 fichiers OU toutes les 1 seconde
            $now = [DateTime]::Now
            if (($fileIndex % 50 -eq 0) -or (($now - $lastUIUpdate).TotalSeconds -ge 1)) {
                $lastUIUpdate = $now

                # Calculer le pourcentage global
                if ($Global:MWTotalFiles -gt 0) {
                    $percentGlobal = [Math]::Min(100, [Math]::Round(($Global:MWCopiedFiles / $Global:MWTotalFiles) * 100))
                } else {
                    $percentGlobal = 0
                }

                # Mettre à jour l'UI avec progression réelle
                if (Get-Command -Name Update-ProgressUI -ErrorAction SilentlyContinue) {
                    $folderLabel = if ($FolderName) { $FolderName } else { "Données utilisateur" }
                    $msg = "Copie $folderLabel : $($Global:MWCopiedFiles) / $($Global:MWTotalFiles) fichiers ($percentGlobal%)"
                    Update-ProgressUI -Message $msg -Percent $percentGlobal
                }

                # Dispatcher.Invoke pour forcer le rafraîchissement WPF
                if ($Global:MWWindow) {
                    try {
                        $Global:MWWindow.Dispatcher.Invoke([action]{}, 'Background')
                    } catch {
                        # Silencieux si pas d'UI
                    }
                }
            }

            $rel = $file.FullName.Substring($Source.Length).TrimStart('\','/')
            if (-not $rel) { continue }

            $destFile = Join-Path $Destination $rel
            $destDir  = Split-Path -Parent $destFile

            if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
                try {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                } catch {
                    Write-MWLogWarning ("Copy-MWUserDirectory : création du dossier parent '{0}' échouée : {1}" -f $destDir, $_.Exception.Message)
                    continue
                }
            }

            try {
                # Mode incrémental : copier uniquement si modifié ou nouveau
                $shouldCopy = $true
                if ($IncrementalMode -and (Test-Path $destFile)) {
                    $srcLastWrite = (Get-Item -LiteralPath $file.FullName).LastWriteTime
                    $destLastWrite = (Get-Item -LiteralPath $destFile).LastWriteTime

                    # Copier uniquement si le fichier source est plus récent
                    if ($srcLastWrite -le $destLastWrite) {
                        $shouldCopy = $false
                    }
                }

                if ($shouldCopy) {
                    Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force -ErrorAction Stop
                }
            } catch {
                Write-MWLogWarning ("Copy-MWUserDirectory : copie '{0}' -> '{1}' échouée : {2}" -f $file.FullName, $destFile, $_.Exception.Message)
            }
        }

    } catch {
        Write-MWLogError ("Copy-MWUserDirectory : {0}" -f $_.Exception.Message)
    }
}

function Export-MWUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,

        [Parameter(Mandatory = $false)]
        [string[]]$SelectedFolders = @(),

        [Parameter(Mandatory = $false)]
        [bool]$IncrementalMode = $false
    )
    <#
        .SYNOPSIS
            Exporte les dossiers "classiques" du profil utilisateur.
        .DESCRIPTION
            Copie Bureau, Documents, Téléchargements, Images, etc.
            vers un sous-dossier 'Profile' dans le dossier d'export.
            Ne touche pas AppData (géré ailleurs).
            Si SelectedFolders est fourni, exporte SEULEMENT ces dossiers.
    #>

    try {
        $profileRoot = Get-MWUserProfileRoot

        if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }

        $profileDestRoot = Join-Path $DestinationFolder 'Profile'
        if (-not (Test-Path -LiteralPath $profileDestRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $profileDestRoot -Force | Out-Null
        }

        Write-MWLogInfo ("Export-MWUserData : profil '{0}' -> '{1}'" -f $profileRoot, $profileDestRoot)

        # Si des dossiers spécifiques sont sélectionnés, copier SEULEMENT ceux-là
        if ($SelectedFolders -and $SelectedFolders.Count -gt 0) {
            Write-MWLogInfo ("Export-MWUserData : mode sélection - {0} dossier(s) spécifique(s)" -f $SelectedFolders.Count)

            foreach ($folderPath in $SelectedFolders) {
                if (Test-Path -LiteralPath $folderPath -PathType Container) {
                    # FIX: Détecter les dossiers sous Public\ et préserver la hiérarchie
                    if ($folderPath -like '*\Users\Public\*') {
                        # Extraire le chemin relatif depuis C:\Users\Public\
                        $relativePath = $folderPath -replace '^[A-Z]:\\Users\\Public\\', ''
                        $destPath = Join-Path $profileDestRoot "Public\$relativePath"
                        $folderName = Split-Path -Leaf $folderPath
                    } else {
                        $folderName = Split-Path -Leaf $folderPath
                        $destPath = Join-Path $profileDestRoot $folderName
                    }

                    Write-MWLogInfo ("Export-MWUserData : copie sélection '{0}' -> '{1}'" -f $folderPath, $destPath)
                    Copy-MWUserDirectory -Source $folderPath -Destination $destPath -FolderName $folderName -IncrementalMode $IncrementalMode
                } else {
                    Write-MWLogWarning ("Export-MWUserData : dossier sélectionné introuvable : {0}" -f $folderPath)
                }
            }

            return
        }

        # Sinon, mode classique : exporter tous les dossiers standards
        Write-MWLogInfo "Analyse des fichiers à copier..."
        $totalFilesCount = 0
        foreach ($f in $script:MWUserDataFolders) {
            $src = Join-Path $profileRoot $f.Relative
            if (Test-Path -LiteralPath $src -PathType Container) {
                $files = @(Get-ChildItem -LiteralPath $src -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) })
                $totalFilesCount += $files.Count
                Write-MWLogInfo ("Export-MWUserData : '{0}' contient {1} fichiers" -f $f.Label, $files.Count)
            }
        }
        Write-MWLogInfo ("Export-MWUserData : TOTAL = {0} fichiers à copier" -f $totalFilesCount)

        # Maintenant copier avec progression
        $Global:MWTotalFiles = $totalFilesCount
        $Global:MWCopiedFiles = 0

        foreach ($f in $script:MWUserDataFolders) {
            $src  = Join-Path $profileRoot  $f.Relative
            $dest = Join-Path $profileDestRoot $f.Relative

            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                Write-MWLogInfo ("Export-MWUserData : dossier '{0}' introuvable, ignoré. (src={1})" -f $f.Label, $src)
                continue
            }

            Write-MWLogInfo ("Export-MWUserData : copie '{0}' : {1} -> {2} (Mode incrémental: {3})" -f $f.Label, $src, $dest, $IncrementalMode)
            Copy-MWUserDirectory -Source $src -Destination $dest -FolderName $f.Label -IncrementalMode $IncrementalMode
        }

    } catch {
        Write-MWLogError ("Export-MWUserData : {0}" -f $_.Exception.Message)
        throw
    }
}

function Import-MWUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe les dossiers "classiques" du profil utilisateur.
        .DESCRIPTION
            Lit le sous-dossier 'Profile' de l'export et recopie Bureau,
            Documents, etc. dans le profil courant.
    #>

    try {
        if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
            throw "Dossier source introuvable : $SourceFolder"
        }

        $profileRoot = Get-MWUserProfileRoot
        $profileSrcRoot = Join-Path $SourceFolder 'Profile'

        if (-not (Test-Path -LiteralPath $profileSrcRoot -PathType Container)) {
            Write-MWLogWarning "Import-MWUserData : aucun sous-dossier 'Profile' trouvé dans la source, rien à importer."
            return
        }

        Write-MWLogInfo ("Import-MWUserData : source '{0}' -> profil '{1}'" -f $profileSrcRoot, $profileRoot)

        foreach ($f in $script:MWUserDataFolders) {
            $src  = Join-Path $profileSrcRoot $f.Relative
            $dest = Join-Path $profileRoot    $f.Relative

            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                Write-MWLogInfo ("Import-MWUserData : dossier export '{0}' introuvable, ignoré. (src={1})" -f $f.Label, $src)
                continue
            }

            Write-MWLogInfo ("Import-MWUserData : copie '{0}' : {1} -> {2}" -f $f.Label, $src, $dest)
            Copy-MWUserDirectory -Source $src -Destination $dest
        }

        # FIX: Importer aussi les dossiers Public\ s'ils existent
        $publicSrcRoot = Join-Path $profileSrcRoot 'Public'
        if (Test-Path -LiteralPath $publicSrcRoot -PathType Container) {
            Write-MWLogInfo "Import-MWUserData : dossiers Public détectés, importation..."

            $publicDestRoot = 'C:\Users\Public'
            $publicFolders = Get-ChildItem -Path $publicSrcRoot -Directory -ErrorAction SilentlyContinue

            foreach ($publicFolder in $publicFolders) {
                $src  = $publicFolder.FullName
                $dest = Join-Path $publicDestRoot $publicFolder.Name

                Write-MWLogInfo ("Import-MWUserData : copie Public\{0} : {1} -> {2}" -f $publicFolder.Name, $src, $dest)
                Copy-MWUserDirectory -Source $src -Destination $dest -FolderName "Public\$($publicFolder.Name)"
            }
        }

    } catch {
        Write-MWLogError ("Import-MWUserData : {0}" -f $_.Exception.Message)
        throw
    }
}

function Repair-MWShortcuts {
    <#
    .SYNOPSIS
    Répare les raccourcis (.lnk) en remplaçant l'ancien nom d'utilisateur par le nouveau
    .PARAMETER OldUserName
    Ancien nom d'utilisateur (du PC source)
    .PARAMETER NewUserName
    Nouveau nom d'utilisateur (du PC cible)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OldUserName,

        [Parameter(Mandatory = $false)]
        [string]$NewUserName = $env:USERNAME
    )

    try {
        $profileRoot = Get-MWUserProfileRoot

        Write-MWLogInfo "Réparation des raccourcis : remplacement '$OldUserName' -> '$NewUserName'"

        # Chercher tous les raccourcis dans le profil
        $shortcuts = Get-ChildItem -Path $profileRoot -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue

        if (-not $shortcuts -or $shortcuts.Count -eq 0) {
            Write-MWLogInfo "Aucun raccourci trouvé à réparer"
            return
        }

        $wshShell = New-Object -ComObject WScript.Shell
        $repairedCount = 0

        foreach ($shortcut in $shortcuts) {
            try {
                $lnk = $wshShell.CreateShortcut($shortcut.FullName)
                $originalTarget = $lnk.TargetPath
                $originalWorkingDir = $lnk.WorkingDirectory
                $originalIconLocation = $lnk.IconLocation

                $modified = $false

                # Remplacer dans le chemin cible
                if ($originalTarget -match "\\Users\\$OldUserName\\") {
                    $lnk.TargetPath = $originalTarget -replace "\\Users\\$OldUserName\\", "\Users\$NewUserName\"
                    $modified = $true
                }

                # Remplacer dans le répertoire de travail
                if ($originalWorkingDir -match "\\Users\\$OldUserName\\") {
                    $lnk.WorkingDirectory = $originalWorkingDir -replace "\\Users\\$OldUserName\\", "\Users\$NewUserName\"
                    $modified = $true
                }

                # Remplacer dans l'emplacement de l'icône
                if ($originalIconLocation -match "\\Users\\$OldUserName\\") {
                    $lnk.IconLocation = $originalIconLocation -replace "\\Users\\$OldUserName\\", "\Users\$NewUserName\"
                    $modified = $true
                }

                if ($modified) {
                    $lnk.Save()
                    $repairedCount++
                    Write-MWLogInfo "Raccourci réparé : $($shortcut.Name)"
                }
            }
            catch {
                Write-MWLogWarning "Erreur réparation raccourci $($shortcut.FullName) : $($_.Exception.Message)"
            }
        }

        Write-MWLogInfo "Réparation raccourcis terminée : $repairedCount/$($shortcuts.Count) modifiés"

        # Libérer l'objet COM
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($wshShell) | Out-Null
    }
    catch {
        Write-MWLogError "Repair-MWShortcuts : $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Export-MWUserData, Import-MWUserData, Repair-MWShortcuts

