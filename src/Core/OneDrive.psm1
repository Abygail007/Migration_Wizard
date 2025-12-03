# src/Core/OneDrive.psm1
# Gestion intelligente de OneDrive et Known Folder Move (KFM)

function Get-MWOneDriveRoots {
    <#
        .SYNOPSIS
        Retourne tous les dossiers racine OneDrive configurés sur le poste.
    #>
    $roots = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    # Variables d'environnement OneDrive
    foreach ($v in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
        if ($v) {
            try {
                $resolved = Resolve-Path -LiteralPath $v -ErrorAction SilentlyContinue
                if ($resolved) {
                    [void]$roots.Add($resolved.Path.TrimEnd('\'))
                }
            } catch {}
        }
    }

    # Clés de registre OneDrive (multi-comptes)
    try {
        $accountKeys = Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue
        foreach ($key in $accountKeys) {
            try {
                $userFolder = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).UserFolder
                if ($userFolder) {
                    $userFolder = [Environment]::ExpandEnvironmentVariables($userFolder)
                    $resolved = Resolve-Path -LiteralPath $userFolder -ErrorAction SilentlyContinue
                    if ($resolved) {
                        [void]$roots.Add($resolved.Path.TrimEnd('\'))
                    }
                }
            } catch {}
        }
    } catch {}

    return $roots.ToArray()
}

function Test-MWIsUnderOneDrive {
    <#
        .SYNOPSIS
        Détermine si un chemin est sous OneDrive (redirection KFM).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($resolved) {
            $Path = $resolved.Path
        }
    } catch {}

    $odRoots = Get-MWOneDriveRoots
    foreach ($root in $odRoots) {
        if ($Path -like "$root*") {
            return $true
        }
    }

    return $false
}

function Resolve-MWOneDriveSubFolder {
    <#
        .SYNOPSIS
        Résout un sous-dossier OneDrive (gère multilingue : Documents/Mes documents, Desktop/Bureau, etc.)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        
        [Parameter(Mandatory = $true)]
        [string[]]$PossibleNames
    )

    foreach ($name in $PossibleNames) {
        $candidate = Join-Path $Root $name
        if (Test-Path -LiteralPath $candidate) {
            try {
                return (Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue).Path
            } catch {
                return $candidate
            }
        }
    }

    return $null
}

function Get-MWOneDriveInfo {
    <#
        .SYNOPSIS
        Retourne les informations OneDrive pour l'utilisateur courant.
        
        .DESCRIPTION
        Détecte :
        - Les dossiers racine OneDrive (Personal / Business)
        - Les redirections KFM (Known Folder Move) pour Desktop/Documents/Pictures
        - Le mapping des dossiers utilisateur vers OneDrive
    #>
    
    $info = [PSCustomObject]@{
        Roots       = @()
        KFMEnabled  = $false
        Mappings    = @{}
    }

    $info.Roots = Get-MWOneDriveRoots

    if ($info.Roots.Count -eq 0) {
        return $info
    }

    # Détection KFM : si Desktop/Documents/Pictures sont sous OneDrive
    $kfmFolders = @(
        @{ Key = 'Desktop';   Names = @('Desktop', 'Bureau') }
        @{ Key = 'Documents'; Names = @('Documents', 'Mes documents') }
        @{ Key = 'Pictures';  Names = @('Pictures', 'Images', 'Photos') }
    )

    foreach ($root in $info.Roots) {
        foreach ($folder in $kfmFolders) {
            $resolved = Resolve-MWOneDriveSubFolder -Root $root -PossibleNames $folder.Names
            if ($resolved) {
                $info.Mappings[$folder.Key] = $resolved
                $info.KFMEnabled = $true
            }
        }
    }

    return $info
}

function Invoke-MWOneDriveHydration {
    <#
        .SYNOPSIS
        Force l'hydratation (téléchargement) des fichiers OneDrive avant copie.
        
        .DESCRIPTION
        Lit 1 octet de chaque fichier pour forcer OneDrive à télécharger les fichiers
        marqués comme "Online-only" (reparse points).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$MaxSeconds = 180
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-MWLogWarning "Invoke-MWOneDriveHydration : chemin introuvable : $Path"
        return
    }

    Write-MWLogInfo "Hydratation OneDrive : $Path (timeout: ${MaxSeconds}s)"

    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $hydrated = 0
    $skipped  = 0

    try {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            if ((Get-Date) -ge $deadline) {
                Write-MWLogWarning "Hydratation OneDrive : timeout atteint après ${MaxSeconds}s."
                break
            }

            try {
                # Détection fichier "Online-only" (attribut ReparsePoint ou Offline)
                if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
                    ($file.Attributes -band [System.IO.FileAttributes]::Offline)) {
                    
                    # Forcer le téléchargement en lisant 1 octet
                    $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $buffer = New-Object byte[] 1
                        [void]$stream.Read($buffer, 0, 1)
                        $hydrated++
                    } finally {
                        $stream.Dispose()
                    }
                } else {
                    $skipped++
                }
            } catch {
                Write-MWLogWarning "Hydratation OneDrive : erreur sur '$($file.FullName)' : $_"
            }
        }

        Write-MWLogInfo "Hydratation OneDrive terminée : $hydrated fichiers hydratés, $skipped déjà locaux."
    } catch {
        Write-MWLogError "Invoke-MWOneDriveHydration : erreur globale : $_"
    }
}

function Resolve-MWPathWithOneDrive {
    <#
        .SYNOPSIS
        Résout un chemin logique en tenant compte de OneDrive/KFM.
        
        .DESCRIPTION
        Si un dossier utilisateur (Desktop/Documents) est redirigé vers OneDrive,
        retourne le chemin OneDrive réel au lieu du chemin standard du profil.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Si le chemin est déjà sous OneDrive, on le retourne tel quel
    if (Test-MWIsUnderOneDrive -Path $Path) {
        return $Path
    }

    # Sinon, on cherche si un mapping KFM existe
    $odInfo = Get-MWOneDriveInfo

    if (-not $odInfo.KFMEnabled) {
        return $Path
    }

    # Exemple : si $Path = C:\Users\JM\Desktop
    # et que Desktop est redirigé vers OneDrive, on retourne le chemin OneDrive
    $profileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

    foreach ($key in $odInfo.Mappings.Keys) {
        $standardPath = Join-Path $profileRoot $key
        if ($Path -like "$standardPath*") {
            $oneDrivePath = $odInfo.Mappings[$key]
            $relativePart = $Path.Substring($standardPath.Length).TrimStart('\')
            
            if ([string]::IsNullOrWhiteSpace($relativePart)) {
                return $oneDrivePath
            } else {
                return (Join-Path $oneDrivePath $relativePart)
            }
        }
    }

    return $Path
}

Export-ModuleMember -Function `
    Get-MWOneDriveRoots, `
    Test-MWIsUnderOneDrive, `
    Get-MWOneDriveInfo, `
    Invoke-MWOneDriveHydration, `
    Resolve-MWPathWithOneDrive
