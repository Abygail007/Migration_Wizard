# src/Core/FileCopy.psm1

function Get-MWDirectorySize {
    [OutputType([int64])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $total = 0L

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $total += $_.Length
        }
    } else {
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($item -and -not $item.PSIsContainer) {
            $total = $item.Length
        }
    }

    return $total
}

function Test-MWSufficientDiskSpace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [int]$SafetyMarginMB = 500
    )
    <#
        .SYNOPSIS
            Vérifie qu'il y a suffisamment d'espace disque pour la copie.
        .DESCRIPTION
            Calcule la taille des données à copier puis la compare à l'espace
            libre sur le volume cible, avec une marge de sécurité.
    #>

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-MWLogWarning "Source introuvable pour le test d'espace disque : $SourcePath"
        return $false
    }

    $dataSizeBytes = Get-MWDirectorySize -Path $SourcePath

    $targetRoot = [System.IO.Path]::GetPathRoot($TargetPath)
    if (-not $targetRoot) {
        Write-MWLogWarning "Impossible de déterminer le volume cible pour : $TargetPath"
        return $false
    }

    try {
        $driveInfo = New-Object System.IO.DriveInfo($targetRoot)
        $freeBytes = $driveInfo.AvailableFreeSpace
    } catch {
        Write-MWLogWarning ("Erreur lors de la récupération de l'espace libre sur {0} : {1}" -f $targetRoot, $_)
        return $false
    }

    $marginBytes = [int64]$SafetyMarginMB * 1MB
    $required    = $dataSizeBytes + $marginBytes

    if ($freeBytes -lt $required) {
        $neededGB = [math]::Round($required / 1GB, 2)
        $freeGB   = [math]::Round($freeBytes / 1GB, 2)
        Write-MWLogWarning ("Espace disque insuffisant. Requis ~{0} Go (avec marge), disponible {1} Go." -f $neededGB, $freeGB)
        return $false
    }

    Write-MWLogInfo ("Espace disque suffisant pour copier {0} octets depuis '{1}' vers '{2}'." -f $dataSizeBytes, $SourcePath, $TargetPath)
    return $true
}

function Copy-MWPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [switch]$SkipDiskCheck
    )
    <#
        .SYNOPSIS
            Copie un chemin (fichier ou dossier) avec la logique MigrationWizard.
        .DESCRIPTION
            Utilise Copy-Item pour l'instant. Plus tard, pourra être remplacé
            par RoboCopy avec exclusions, filtres, etc.
    #>

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-MWLogError "Source introuvable pour la copie : $SourcePath"
        return
    }

    if (-not $SkipDiskCheck) {
        if (-not (Test-MWSufficientDiskSpace -SourcePath $SourcePath -TargetPath $TargetPath)) {
            Write-MWLogError "Copie annulée pour cause d'espace disque insuffisant."
            return
        }
    }

    try {
        if (Test-Path -LiteralPath $SourcePath -PathType Container) {
            if (-not (Test-Path -LiteralPath $TargetPath)) {
                New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
            }

            Write-MWLogInfo "Copie du dossier '$SourcePath' vers '$TargetPath'."
            Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Recurse -Force -ErrorAction Stop
        } else {
            $targetDir = Split-Path -Parent $TargetPath
            if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            Write-MWLogInfo "Copie du fichier '$SourcePath' vers '$TargetPath'."
            Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force -ErrorAction Stop
        }
    } catch {
        Write-MWLogError ("Erreur lors de la copie de '{0}' vers '{1}' : {2}" -f $SourcePath, $TargetPath, $_)
        throw
    }
}

Export-ModuleMember -Function Test-MWSufficientDiskSpace, Copy-MWPath
