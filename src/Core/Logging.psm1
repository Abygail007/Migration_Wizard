# src/Core/Logging.psm1

# Variables internes au module
$script:MWLogRoot      = $null
$script:MWLogFile      = $null
$script:MWHtmlLogFile  = $null

function Initialize-MWLogging {
    <#
        .SYNOPSIS
            Initialise l'infrastructure de logs.
        .DESCRIPTION
            Créera plus tard les dossiers et fichiers de log (texte + HTML).
    #>
    Write-Verbose "[Logging] Initialize-MWLogging (stub)"
}

function Write-MWLogInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Verbose "[INFO] $Message"
}

function Write-MWLogWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Warning $Message
}

function Write-MWLogError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Error $Message
}

Export-ModuleMember -Function Initialize-MWLogging, Write-MWLogInfo, Write-MWLogWarning, Write-MWLogError
