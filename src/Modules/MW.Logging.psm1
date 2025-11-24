# Module : MW.Logging
# Gestion centralisée des logs pour MigrationWizard

function Get-MWRootDirectory {
    <#
        .SYNOPSIS
        Retourne le dossier racine du projet MigrationWizard.
    #>
    try {
        # $PSScriptRoot = ...\src\Modules
        $modulesPath = $PSScriptRoot
        $srcPath     = Split-Path -Path $modulesPath -Parent  # ...\src
        $rootPath    = Split-Path -Path $srcPath -Parent      # ...\Github
        return $rootPath
    }
    catch {
        # Fallback : dossier courant
        return (Get-Location).Path
    }
}

function Get-MWLogsDirectory {
    <#
        .SYNOPSIS
        Retourne le dossier Logs du projet.
    #>
    $root    = Get-MWRootDirectory
    $logsDir = Join-Path -Path $root -ChildPath 'Logs'
    return $logsDir
}

function Initialize-MWLogging {
    <#
        .SYNOPSIS
        Prépare le dossier de logs.
    #>
    try {
        $logsDir = Get-MWLogsDirectory

        if (-not (Test-Path -LiteralPath $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
    }
    catch {
        Write-Verbose ("[Initialize-MWLogging] Impossible d'initialiser le dossier de logs : {0}" -f $_) -ErrorAction SilentlyContinue
    }
}

function Write-MWLog {
    <#
        .SYNOPSIS
        Écrit une ligne dans le fichier de log de MigrationWizard.

        .PARAMETER Message
        Message à écrire.

        .PARAMETER Level
        Niveau de log : INFO, WARN, ERROR, DEBUG.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    try {
        $logsDir = Get-MWLogsDirectory

        if (-not (Test-Path -LiteralPath $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }

        $date        = Get-Date -Format 'yyyy-MM-dd'
        $logFileName = "MigrationWizard_{0}.log" -f $date
        $logFilePath = Join-Path -Path $logsDir -ChildPath $logFileName

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line      = "{0} [{1}] {2}" -f $timestamp, $Level, $Message

        Add-Content -Path $logFilePath -Value $line
    }
    catch {
        Write-Verbose ("[Write-MWLog] Impossible d'écrire dans le fichier de log : {0}" -f $_) -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Initialize-MWLogging, Write-MWLog, Get-MWLogsDirectory
