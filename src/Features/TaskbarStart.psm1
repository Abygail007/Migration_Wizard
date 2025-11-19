# src/Features/TaskbarStart.psm1

function Export-MWTaskbarStartLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    Write-Verbose "[TaskbarStart] Export-MWTaskbarStartLayout (stub) -> $DestinationFolder"
}

function Import-MWTaskbarStartLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    Write-Verbose "[TaskbarStart] Import-MWTaskbarStartLayout (stub) <- $SourceFolder"
}

Export-ModuleMember -Function Export-MWTaskbarStartLayout, Import-MWTaskbarStartLayout
