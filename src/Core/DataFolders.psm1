# src/Core/DataFolders.psm1
# Gestion de la copie des dossiers "données utilisateur" standard :
# Bureau, Documents, Images, Favoris, etc.

function Get-MWDefaultDataFolders {
    <#
        .SYNOPSIS
            Retourne la liste des dossiers utilisateur standard à copier.
        .DESCRIPTION
            Pour l’instant on gère quelques dossiers classiques :
            - Bureau
            - Documents
            - Images
            - Favoris
            À l’export, on les mettra dans : <ExportRoot>\UserData\<Key>
    #>
    [OutputType([System.Object[]])]
    param()

    $userProfile = $env:USERPROFILE
    $list = @()

    $pairs = @(
        @{ Key = 'Desktop';   Name = 'Bureau';     Source = [System.IO.Path]::Combine($userProfile, 'Desktop')   }
        @{ Key = 'Documents'; Name = 'Documents';  Source = [System.IO.Path]::Combine($userProfile, 'Documents') }
        @{ Key = 'Pictures';  Name = 'Images';     Source = [System.IO.Path]::Combine($userProfile, 'Pictures')  }
        @{ Key = 'Favorites'; Name = 'Favoris';    Source = [System.IO.Path]::Combine($userProfile, 'Favorites') }
    )

    foreach ($p in $pairs) {
        $src = $p.Source
        if ($src -and (Test-Path -LiteralPath $src)) {
            $list += [pscustomobject]@{
                Key          = $p.Key
                Name         = $p.Name
                SourcePath   = $src
                ExportSubDir = $p.Key
            }
        }
    }

    return $list
}

function Export-MWDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )

    try {
        $dataRoot = Join-Path $DestinationFolder 'UserData'
        if (-not (Test-Path -LiteralPath $dataRoot)) {
            New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        }

        $folders = Get-MWDefaultDataFolders
        if (-not $folders -or $folders.Count -eq 0) {
            Write-MWLogWarning "Export-MWDataFolders : aucun dossier standard détecté à exporter."
            return
        }

        foreach ($f in $folders) {
            $src = $f.SourcePath
            $dst = Join-Path $dataRoot $f.ExportSubDir

            if (-not (Test-Path -LiteralPath $src)) {
                Write-MWLogWarning ("Export-MWDataFolders : dossier source introuvable '{0}' ({1})." -f $src, $f.Name)
                continue
            }

            try {
                Write-MWLogInfo ("Export-MWDataFolders : copie de '{0}' -> '{1}'." -f $src, $dst)

                if (-not (Test-Path -LiteralPath $dst)) {
                    New-Item -ItemType Directory -Path $dst -Force | Out-Null
                }

                Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force -ErrorAction Stop
            } catch {
                Write-MWLogError ("Export-MWDataFolders : erreur lors de la copie de '{0}' : {1}" -f $src, $_.Exception.Message)
            }
        }

        # Petit manifest pour faciliter l’import
        try {
            $manifestPath = Join-Path $dataRoot 'DataFolders.manifest.json'
            $folders | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            Write-MWLogInfo ("Export-MWDataFolders : manifest enregistré -> {0}" -f $manifestPath)
        } catch {
            Write-MWLogWarning ("Export-MWDataFolders : impossible d'écrire le manifest : {0}" -f $_.Exception.Message)
        }
    } catch {
        Write-MWLogError ("Export-MWDataFolders (global) : {0}" -f $_.Exception.Message)
        throw
    }
}

function Import-MWDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )

    try {
        $dataRoot = Join-Path $SourceFolder 'UserData'
        if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) {
            Write-MWLogWarning ("Import-MWDataFolders : dossier 'UserData' introuvable dans '{0}'." -f $SourceFolder)
            return
        }

        $manifestPath = Join-Path $dataRoot 'DataFolders.manifest.json'
        $entries = $null

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            } catch {
                Write-MWLogWarning ("Import-MWDataFolders : manifest illisible : {0}" -f $_.Exception.Message)
            }
        }

        if (-not $entries) {
            # Fallback : on reconstruit à partir des sous-dossiers trouvés
            $dirs = Get-ChildItem -LiteralPath $dataRoot -Directory -ErrorAction SilentlyContinue
            $entries = @()
            foreach ($d in $dirs) {
                $entries += [pscustomobject]@{
                    Key          = $d.Name
                    Name         = $d.Name
                    ExportSubDir = $d.Name
                }
            }
        }

        if (-not $entries -or $entries.Count -eq 0) {
            Write-MWLogWarning "Import-MWDataFolders : aucun dossier à réimporter."
            return
        }

        # Mapping clé -> chemin cible
        $targetMap = @{
            Desktop   = [System.Environment]::GetFolderPath('Desktop')
            Documents = [System.Environment]::GetFolderPath('MyDocuments')
            Pictures  = [System.Environment]::GetFolderPath('MyPictures')
            Favorites = [System.Environment]::GetFolderPath('Favorites')
        }

        foreach ($entry in $entries) {
            $key = $entry.Key
            if (-not $key) {
                $key = $entry.ExportSubDir
            }

            $sourceDir = Join-Path $dataRoot $entry.ExportSubDir
            if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
                Write-MWLogWarning ("Import-MWDataFolders : dossier source introuvable '{0}'." -f $sourceDir)
                continue
            }

            $destPath = $null
            if ($key -and $targetMap.ContainsKey($key)) {
                $destPath = $targetMap[$key]
            }

            if (-not $destPath) {
                Write-MWLogWarning ("Import-MWDataFolders : aucun chemin cible connu pour la clé '{0}', dossier '{1}'." -f $key, $sourceDir)
                continue
            }

            try {
                Write-MWLogInfo ("Import-MWDataFolders : copie de '{0}' -> '{1}'." -f $sourceDir, $destPath)

                if (-not (Test-Path -LiteralPath $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                }

                Copy-Item -LiteralPath (Join-Path $sourceDir '*') -Destination $destPath -Recurse -Force -ErrorAction Stop
            } catch {
                Write-MWLogError ("Import-MWDataFolders : erreur lors de la copie vers '{0}' : {1}" -f $destPath, $_.Exception.Message)
            }
        }
    } catch {
        Write-MWLogError ("Import-MWDataFolders (global) : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWDataFolders, Import-MWDataFolders, Get-MWDefaultDataFolders
