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
            CrÃ©e un dossier Logs dans le rÃ©pertoire courant et initialise
            un fichier texte et un fichier HTML pour la session.
    #>

    $currentPath = (Get-Location).Path
    $script:MWLogRoot = Join-Path $currentPath 'Logs'

    if (-not (Test-Path -LiteralPath $script:MWLogRoot)) {
        New-Item -ItemType Directory -Path $script:MWLogRoot -Force | Out-Null
    }

    if (-not $Global:MWSessionId) {
        $Global:MWSessionId = (Get-Date -Format 'yyyyMMdd_HHmmss')
    }

    $sessionId = $Global:MWSessionId

    $script:MWLogFile     = Join-Path $script:MWLogRoot ("MigrationWizard_{0}.log" -f $sessionId)
    $script:MWHtmlLogFile = Join-Path $script:MWLogRoot ("MigrationWizard_{0}.html" -f $sessionId)

    $header = "[{0}] --- DÃ©marrage de MigrationWizard (session {1}) ---" -f (Get-Date), $sessionId
    $header | Out-File -FilePath $script:MWLogFile -Encoding UTF8

    $htmlHeader = @(
        '<!DOCTYPE html>'
        '<html>'
        '<head>'
        '<meta charset="utf-8" />'
        '<title>MigrationWizard Log</title>'
        '</head>'
        '<body>'
        '<table border="1" cellspacing="0" cellpadding="4">'
        '<tr><th>Date/Heure</th><th>Niveau</th><th>Message</th></tr>'
    )
    $htmlHeader | Out-File -FilePath $script:MWHtmlLogFile -Encoding UTF8
}

function Write-MWLogInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    if ($script:MWLogFile) {
        Add-Content -Path $script:MWLogFile -Value $line -Encoding UTF8
    }

    if ($script:MWHtmlLogFile) {
        $htmlRow = '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f $timestamp, $Level, $Message
        Add-Content -Path $script:MWHtmlLogFile -Value $htmlRow -Encoding UTF8
    }
}

function Write-MWLogInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Verbose "[INFO] $Message"
    Write-MWLogInternal -Level 'INFO' -Message $Message
}

function Write-MWLogWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Warning $Message
    Write-MWLogInternal -Level 'WARN' -Message $Message
}

function Write-MWLogError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Error $Message
    Write-MWLogInternal -Level 'ERROR' -Message $Message
}

Export-ModuleMember -Function Initialize-MWLogging, Write-MWLogInfo, Write-MWLogWarning, Write-MWLogError

