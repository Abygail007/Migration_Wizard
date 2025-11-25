# Module : Core/Export
# Construction et sauvegarde d'un "snapshot" d'export MigrationWizard.

function Test-MWLogAvailable {
    try {
        $cmd = Get-Command -Name Write-MWLog -ErrorAction SilentlyContinue
        return ($null -ne $cmd)
    }
    catch {
        return $false
    }
}

function Write-MWLogSafe {
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
        # On ne casse jamais l’export juste pour un log.
    }
}

function New-MWExportSnapshot {
    <#
        .SYNOPSIS
        Construit l’objet d’export MigrationWizard.
    #>
    param(
        [string]$UserName = $env:USERNAME,
        [string]$SnapshotPath
    )

    Write-MWLogSafe -Message "Construction du snapshot d’export pour l’utilisateur $UserName." -Level 'INFO'

    # Récupération des applications installées si le module est dispo
    $apps = @()
    try {
        $cmd = Get-Command -Name Get-MWApplicationsForExport -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $apps = Get-MWApplicationsForExport
        }
        else {
            Write-MWLogSafe -Message "Get-MWApplicationsForExport non disponible, section Applications vide." -Level 'WARN'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la récupération des applications : $_" -Level 'ERROR'
    }

    # Préparation des chemins (si on connaît le chemin du snapshot)
    $paths = $null
    if ($SnapshotPath) {
        $exportRoot   = Split-Path -Path $SnapshotPath -Parent
        $appsDir      = Join-Path -Path $exportRoot -ChildPath 'Applications'
        $userDataRoot = Join-Path -Path $exportRoot -ChildPath 'UserData'

        $paths = [pscustomobject]@{
            ExportRoot               = $exportRoot
            SnapshotPath             = $SnapshotPath
            ApplicationsManifestPath = (Join-Path -Path $appsDir      -ChildPath 'applications.json')
            UserDataRoot             = $userDataRoot
            DataFoldersManifestPath  = (Join-Path -Path $userDataRoot -ChildPath 'DataFolders.manifest.json')
        }
    }

    $snapshot = [pscustomobject]@{
        SchemaVersion = '1.1'
        GeneratedAt   = (Get-Date).ToString('s')
        MachineName   = $env:COMPUTERNAME
        UserName      = $UserName
        Paths         = $paths

        # Sections de données (pour l’instant juste Applications)
        Applications  = $apps

        # TODO : à remplir plus tard
        # UserFolders   = $null
        # Browsers      = $null
        # WifiProfiles  = $null
        # Printers      = $null
        # Etc.
    }

    Write-MWLogSafe -Message "Snapshot d’export construit (Applications : $($apps.Count))." -Level 'INFO'

    return $snapshot
}

function Save-MWExportSnapshot {
    <#
        .SYNOPSIS
        Construit et enregistre le snapshot d’export dans un fichier JSON.

        .PARAMETER Path
        Chemin complet du fichier JSON à créer.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$UserName = $env:USERNAME
    )

    try {
        Write-MWLogSafe -Message "Sauvegarde du snapshot d’export vers '$Path'." -Level 'INFO'

        $snapshot = New-MWExportSnapshot -UserName $UserName -SnapshotPath $Path

        $json = $snapshot | ConvertTo-Json -Depth 6

        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $json | Set-Content -LiteralPath $Path -Encoding UTF8

        Write-MWLogSafe -Message "Snapshot d’export enregistré avec succès." -Level 'INFO'
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de Save-MWExportSnapshot : $_" -Level 'ERROR'
        throw
    }
}

function Import-MWExportSnapshot {
    <#
        .SYNOPSIS
        Charge un snapshot d’export MigrationWizard depuis un fichier JSON.

        .PARAMETER Path
        Chemin du fichier JSON d’export.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-MWLogSafe -Message "Chargement du snapshot d’export depuis '$Path'." -Level 'INFO'

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-MWLogSafe -Message "Fichier d’export introuvable : $Path" -Level 'ERROR'
        throw "Fichier d’export introuvable : $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $snapshot = $json | ConvertFrom-Json
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors du parsing JSON de l’export : $_" -Level 'ERROR'
        throw
    }

    return $snapshot
}

Export-ModuleMember -Function New-MWExportSnapshot, Save-MWExportSnapshot, Import-MWExportSnapshot
