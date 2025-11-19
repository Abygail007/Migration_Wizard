# src/Features/Outlook.psm1

function Export-MWOutlookData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    Write-Verbose "[Outlook] Export-MWOutlookData (stub) -> $DestinationFolder"
}

function Import-MWOutlookData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    Write-Verbose "[Outlook] Import-MWOutlookData (stub) <- $SourceFolder"
}

Export-ModuleMember -Function Export-MWOutlookData, Import-MWOutlookData
