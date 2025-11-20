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
            Crée un dossier Logs dans le répertoire courant et initialise
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

    $header = "[{0}] --- Démarrage de MigrationWizard (session {1}) ---" -f (Get-Date), $sessionId
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

    # Écriture dans le log texte avec retries (gère les locks temporaires : AV, indexation, etc.)
    if ($script:MWLogFile) {
        $maxAttempts = 5
        $attempt     = 1

        while ($attempt -le $maxAttempts) {
            try {
                Add-Content -Path $script:MWLogFile -Value $line -Encoding UTF8 -ErrorAction Stop
                break
            } catch [System.IO.IOException] {
                if ($attempt -eq $maxAttempts) {
                    Write-Verbose ("MWLog: impossible d'écrire dans le fichier texte après {0} tentatives : {1}" -f $maxAttempts, $_.Exception.Message)
                } else {
                    Start-Sleep -Milliseconds 200
                }
            } catch {
                Write-Verbose ("MWLog: erreur inattendue (texte) : {0}" -f $_.Exception.Message)
                break
            }

            $attempt = $attempt + 1
        }
    }

    # Écriture dans le log HTML avec retries aussi (même style, séparé)
    if ($script:MWHtmlLogFile) {
        $htmlRow = '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f $timestamp, $Level, $Message

        $maxAttemptsHtml = 5
        $attemptHtml     = 1

        while ($attemptHtml -le $maxAttemptsHtml) {
            try {
                Add-Content -Path $script:MWHtmlLogFile -Value $htmlRow -Encoding UTF8 -ErrorAction Stop
                break
            } catch [System.IO.IOException] {
                if ($attemptHtml -eq $maxAttemptsHtml) {
                    Write-Verbose ("MWLog: impossible d'écrire dans le fichier HTML après {0} tentatives : {1}" -f $maxAttemptsHtml, $_.Exception.Message)
                } else {
                    Start-Sleep -Milliseconds 200
                }
            } catch {
                Write-Verbose ("MWLog: erreur inattendue (HTML) : {0}" -f $_.Exception.Message)
                break
            }

            $attemptHtml = $attemptHtml + 1
        }
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
