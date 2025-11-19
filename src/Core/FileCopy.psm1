# src/Core/FileCopy.psm1

function Test-MWSufficientDiskSpace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )
    <#
        .SYNOPSIS
            Vérifie qu'il y a suffisamment d'espace disque pour la copie.
    #>
    Write-Verbose "[FileCopy] Test-MWSufficientDiskSpace (stub) Source='$SourcePath' Target='$TargetPath'"
    return $true
}

function Copy-MWPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )
    <#
        .SYNOPSIS
            Copie un chemin (fichier ou dossier) avec la logique MigrationWizard.
    #>
    Write-Verbose "[FileCopy] Copy-MWPath (stub) Source='$SourcePath' Target='$TargetPath'"
}

Export-ModuleMember -Function Test-MWSufficientDiskSpace, Copy-MWPath
