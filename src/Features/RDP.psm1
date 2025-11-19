# src/Features/RDP.psm1

function Export-MWRdpConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    Write-Verbose "[RDP] Export-MWRdpConnections (stub) -> $DestinationFolder"
}

function Import-MWRdpConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    Write-Verbose "[RDP] Import-MWRdpConnections (stub) <- $SourceFolder"
}

Export-ModuleMember -Function Export-MWRdpConnections, Import-MWRdpConnections
