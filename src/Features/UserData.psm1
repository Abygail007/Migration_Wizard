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
        [string]$Destination
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

        foreach ($file in $files) {
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
                Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force -ErrorAction Stop
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
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les dossiers "classiques" du profil utilisateur.
        .DESCRIPTION
            Copie Bureau, Documents, Téléchargements, Images, etc.
            vers un sous-dossier 'Profile' dans le dossier d'export.
            Ne touche pas AppData (géré ailleurs).
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

        foreach ($f in $script:MWUserDataFolders) {
            $src  = Join-Path $profileRoot  $f.Relative
            $dest = Join-Path $profileDestRoot $f.Relative

            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                Write-MWLogInfo ("Export-MWUserData : dossier '{0}' introuvable, ignoré. (src={1})" -f $f.Label, $src)
                continue
            }

            Write-MWLogInfo ("Export-MWUserData : copie '{0}' : {1} -> {2}" -f $f.Label, $src, $dest)
            Copy-MWUserDirectory -Source $src -Destination $dest
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

    } catch {
        Write-MWLogError ("Import-MWUserData : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWUserData, Import-MWUserData
