# src/Features/Browsers.psm1

function Export-MWBrowserData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    Write-Verbose "[Browsers] Export-MWBrowserData (stub) -> $DestinationFolder"
}

function Import-MWBrowserData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    Write-Verbose "[Browsers] Import-MWBrowserData (stub) <- $SourceFolder"
}

Export-ModuleMember -Function Export-MWBrowserData, Import-MWBrowserData

