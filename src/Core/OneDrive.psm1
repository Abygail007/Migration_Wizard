# src/Core/OneDrive.psm1

function Get-MWOneDriveInfo {
    <#
        .SYNOPSIS
            Retourne les infos OneDrive pour l'utilisateur courant.
    #>
    Write-Verbose "[OneDrive] Get-MWOneDriveInfo (stub)"
    return $null
}

function Resolve-MWPathWithOneDrive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    <#
        .SYNOPSIS
            Adapte un chemin logique en tenant compte de OneDrive / KFM.
    #>
    Write-Verbose "[OneDrive] Resolve-MWPathWithOneDrive (stub) Path='$Path'"
    return $Path
}

Export-ModuleMember -Function Get-MWOneDriveInfo, Resolve-MWPathWithOneDrive

