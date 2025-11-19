# src/Features/Wifi.psm1

function Export-MWWifiProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    Write-Verbose "[Wifi] Export-MWWifiProfiles (stub) -> $DestinationFolder"
}

function Import-MWWifiProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    Write-Verbose "[Wifi] Import-MWWifiProfiles (stub) <- $SourceFolder"
}

Export-ModuleMember -Function Export-MWWifiProfiles, Import-MWWifiProfiles
