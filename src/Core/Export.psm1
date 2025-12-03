# Module : Core/Export
# Construction et sauvegarde d'un "snapshot" d'export MigrationWizard.
#
# NOTE : Test-MWLogAvailable et Write-MWLogSafe sont maintenant centralises
#        dans le module MW.Logging.psm1
function New-MWExportSnapshot {
    <#
        .SYNOPSIS
        Construit l'objet d'export MigrationWizard complet.
        
        .DESCRIPTION
        Cree un snapshot JSON contenant toutes les donnees exportables :
        - Applications installees
        - Dossiers utilisateur (DataFolders)
        - Navigateurs installes
        - Profils WiFi
        - Imprimantes
        - Connexions RDP
        - Lecteurs reseau
    #>
    param(
        [string]$UserName = $env:USERNAME,
        [string]$SnapshotPath
    )

    Write-MWLogSafe -Message "Construction du snapshot d'export pour l'utilisateur $UserName." -Level 'INFO'

    # ========================================
    # 1. Applications installees
    # ========================================
    $apps = @()
    try {
        $cmd = Get-Command -Name Get-MWApplicationsForExport -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $apps = Get-MWApplicationsForExport
            Write-MWLogSafe -Message "Applications : $($apps.Count) detectees." -Level 'INFO'
        }
        else {
            Write-MWLogSafe -Message "Get-MWApplicationsForExport non disponible, section Applications vide." -Level 'WARN'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la recuperation des applications : $_" -Level 'ERROR'
    }

    # ========================================
    # 2. Dossiers utilisateur (DataFolders)
    # ========================================
    $userFolders = @()
    try {
        $cmd = Get-Command -Name New-MWDataFoldersManifest -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $userFolders = New-MWDataFoldersManifest
            Write-MWLogSafe -Message "UserFolders : $($userFolders.Count) dossiers detectes." -Level 'INFO'
        }
        else {
            Write-MWLogSafe -Message "New-MWDataFoldersManifest non disponible, section UserFolders vide." -Level 'WARN'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la recuperation des dossiers utilisateur : $_" -Level 'ERROR'
    }

    # ========================================
    # 3. Navigateurs installes
    # ========================================
    $browsers = @()
    try {
        $cmd = Get-Command -Name Get-MWInstalledBrowsers -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $browsers = Get-MWInstalledBrowsers
            Write-MWLogSafe -Message "Browsers : $($browsers.Count) navigateurs detectes." -Level 'INFO'
        }
        else {
            Write-MWLogSafe -Message "Get-MWInstalledBrowsers non disponible, section Browsers vide." -Level 'WARN'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la detection des navigateurs : $_" -Level 'ERROR'
    }

    # ========================================
    # 4. Profils WiFi
    # ========================================
    $wifiProfiles = @()
    try {
        # On liste les profils WiFi via netsh
        $netshOutput = netsh wlan show profiles 2>$null
        if ($netshOutput) {
            $wifiProfiles = $netshOutput | 
                Select-String -Pattern "Profil Tous les utilisateurs\s*:\s*(.+)|All User Profile\s*:\s*(.+)" | 
                ForEach-Object {
                    $name = if ($_.Matches.Groups[1].Value) { $_.Matches.Groups[1].Value.Trim() } else { $_.Matches.Groups[2].Value.Trim() }
                    [pscustomobject]@{
                        Name = $name
                        Type = 'WiFi'
                    }
                }
            Write-MWLogSafe -Message "WifiProfiles : $($wifiProfiles.Count) profils detectes." -Level 'INFO'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la detection des profils WiFi : $_" -Level 'ERROR'
    }

    # ========================================
    # 5. Imprimantes
    # ========================================
    $printers = @()
    try {
        $cmd = Get-Command -Name Get-Printer -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $printers = Get-Printer -ErrorAction SilentlyContinue | 
                Where-Object { $_.PrinterStatus -ne 'Offline' } |
                Select-Object Name, DriverName, PortName, Shared, PrinterStatus |
                ForEach-Object {
                    [pscustomobject]@{
                        Name         = $_.Name
                        DriverName   = $_.DriverName
                        PortName     = $_.PortName
                        Shared       = $_.Shared
                        Status       = [string]$_.PrinterStatus
                    }
                }
            Write-MWLogSafe -Message "Printers : $($printers.Count) imprimantes detectees." -Level 'INFO'
        }
        else {
            Write-MWLogSafe -Message "Get-Printer non disponible, section Printers vide." -Level 'WARN'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la detection des imprimantes : $_" -Level 'ERROR'
    }

    # ========================================
    # 6. Connexions RDP
    # ========================================
    $rdpConnections = @()
    try {
        $rdpKey = 'HKCU:\Software\Microsoft\Terminal Server Client\Default'
        if (Test-Path -LiteralPath $rdpKey) {
            $rdpValues = Get-ItemProperty -Path $rdpKey -ErrorAction SilentlyContinue
            if ($rdpValues) {
                $rdpConnections = $rdpValues.PSObject.Properties |
                    Where-Object { $_.Name -match '^MRU\d+$' } |
                    ForEach-Object {
                        [pscustomobject]@{
                            Index  = $_.Name
                            Server = $_.Value
                        }
                    }
            }
            Write-MWLogSafe -Message "RDP : $($rdpConnections.Count) connexions recentes detectees." -Level 'INFO'
        }
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la detection des connexions RDP : $_" -Level 'ERROR'
    }

    # ========================================
    # 7. Lecteurs reseau
    # ========================================
    $networkDrives = @()
    try {
        $networkDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayRoot -and $_.DisplayRoot -like '\\*' } |
            Select-Object Name, @{N='Path';E={$_.DisplayRoot}} |
            ForEach-Object {
                [pscustomobject]@{
                    DriveLetter = $_.Name
                    UNCPath     = $_.Path
                }
            }
        Write-MWLogSafe -Message "NetworkDrives : $($networkDrives.Count) lecteurs reseau detectes." -Level 'INFO'
    }
    catch {
        Write-MWLogSafe -Message "Erreur lors de la detection des lecteurs reseau : $_" -Level 'ERROR'
    }

    # ========================================
    # Preparation des chemins
    # ========================================
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

    # ========================================
    # Construction du snapshot complet
    # ========================================
    $snapshot = [pscustomobject]@{
        SchemaVersion   = '2.0'
        GeneratedAt     = (Get-Date).ToString('s')
        MachineName     = $env:COMPUTERNAME
        UserName        = $UserName
        Paths           = $paths

        # Sections de donnees
        Applications    = $apps
        UserFolders     = $userFolders
        Browsers        = $browsers
        WifiProfiles    = $wifiProfiles
        Printers        = $printers
        RdpConnections  = $rdpConnections
        NetworkDrives   = $networkDrives
    }

    # Resume
    $summary = @(
        "Applications:$($apps.Count)",
        "UserFolders:$($userFolders.Count)",
        "Browsers:$($browsers.Count)",
        "WiFi:$($wifiProfiles.Count)",
        "Printers:$($printers.Count)",
        "RDP:$($rdpConnections.Count)",
        "NetworkDrives:$($networkDrives.Count)"
    ) -join ', '
    
    Write-MWLogSafe -Message "Snapshot d'export construit. Resume: $summary" -Level 'INFO'

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
