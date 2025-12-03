# Module : MW.Logging
# Gestion centralisée des logs pour MigrationWizard

function Get-MWRootDirectory {
    <#
        .SYNOPSIS
        Retourne le dossier racine du projet MigrationWizard.
    #>
    
    # Mode portable (EXE compile) : utiliser la variable globale
    if ($Global:MWRootPath -and (Test-Path -LiteralPath $Global:MWRootPath -ErrorAction SilentlyContinue)) {
        return $Global:MWRootPath
    }
    
    # Mode developpement : utiliser PSScriptRoot
    try {
        if ($PSScriptRoot) {
            # $PSScriptRoot = ...\src\Modules
            $modulesPath = $PSScriptRoot
            $srcPath     = Split-Path -Path $modulesPath -Parent  # ...\src
            $rootPath    = Split-Path -Path $srcPath -Parent      # ...\Github
            return $rootPath
        }
    }
    catch { }
    
    # Fallback : dossier courant
    return (Get-Location).Path
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
        $logFileName = "MigrationWizard_{0}_$($env:COMPUTERNAME).log" -f $date
        $logFilePath = Join-Path -Path $logsDir -ChildPath $logFileName

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line      = "{0} [{1}] {2}" -f $timestamp, $Level, $Message

        # Retry logic pour éviter concurrent access errors
        $retries = 3
        $written = $false
        
        for ($i = 0; $i -lt $retries -and -not $written; $i++) {
            try {
                Add-Content -Path $logFilePath -Value $line -ErrorAction Stop
                $written = $true
            }
            catch [System.IO.IOException] {
                # Erreur I/O (fichier verrouillé), on réessaye
                if ($i -lt ($retries - 1)) {
                    Start-Sleep -Milliseconds 50
                }
            }
            catch {
                # Autre type d'erreur, on arrête
                break
            }
        }
    }
    catch {
        # Silencieux
    }
}

function Write-MWLogInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-MWLog -Message $Message -Level 'INFO'
}

function Write-MWLogWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-MWLog -Message $Message -Level 'WARN'
}

function Write-MWLogError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-MWLog -Message $Message -Level 'ERROR'
}

function Write-MWLogDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-MWLog -Message $Message -Level 'DEBUG'
}

function Test-MWLogAvailable {
    <#
        .SYNOPSIS
        Verifie si Write-MWLog est disponible.
        Fonction centralisee pour tous les modules MigrationWizard.
    #>
    try {
        $cmd = Get-Command -Name Write-MWLog -ErrorAction SilentlyContinue
        return ($null -ne $cmd)
    }
    catch {
        return $false
    }
}

function Write-MWLogSafe {
    <#
        .SYNOPSIS
        Wrapper securise autour de Write-MWLog (ne plante jamais).
        Fonction centralisee pour tous les modules MigrationWizard.

        .DESCRIPTION
        Si Write-MWLog n'est pas disponible, cette fonction ne fait rien
        et ne provoque aucune erreur. Cela permet aux modules de logger
        de maniere optionnelle sans dependre strictement du module de log.

        .PARAMETER Message
        Message a ecrire dans le log.

        .PARAMETER Level
        Niveau de log : INFO, WARN, ERROR, DEBUG.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    if (-not (Test-MWLogAvailable)) {
        return
    }

    try {
        Write-MWLog -Message $Message -Level $Level
    }
    catch {
        # On ne casse jamais l'outil juste pour un log
    }
}

function Get-MWLogPath {
    <#
        .SYNOPSIS
        Retourne le chemin complet du fichier log du jour.
    #>
    try {
        $logsDir = Get-MWLogsDirectory
        $date = Get-Date -Format 'yyyy-MM-dd'
        $logFileName = "MigrationWizard_{0}.log" -f $date
        return (Join-Path -Path $logsDir -ChildPath $logFileName)
    }
    catch {
        return $null
    }
}

Export-ModuleMember -Function `
    Initialize-MWLogging, `
    Write-MWLog, `
    Write-MWLogInfo, `
    Write-MWLogWarning, `
    Write-MWLogError, `
    Write-MWLogDebug, `
    Get-MWLogsDirectory, `
    Get-MWLogPath, `
    Test-MWLogAvailable, `
    Write-MWLogSafe
