# Module : Core/Applications
# Recensement des applications installées (côté utilisateur)
# Objectif : fournir une liste propre pour l'export, et préparer
# une future intégration avec RuckZuck.

function Test-MWLogAvailable {
    <#
        .SYNOPSIS
        Vérifie si Write-MWLog est disponible.
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
        Wrapper sécurisé autour de Write-MWLog (ne plante jamais).
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

function Test-MWIsUserFacingApp {
    <#
        .SYNOPSIS
        Détermine si une application est "utilisateur" (pas un composant système).

        .DESCRIPTION
        Prend en entrée les propriétés brutes d'une clé de registre de type
        HKLM/HKCU:\Software\...\Uninstall et applique quelques filtres pour
        éviter les .NET, runtimes, drivers, etc.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Properties
    )

    $name = $Properties.DisplayName

    if ([string]::IsNullOrWhiteSpace($name)) {
        return $false
    }

    # Composant système explicite
    if ($Properties.PSObject.Properties.Name -contains 'SystemComponent') {
        if ($Properties.SystemComponent -eq 1) {
            return $false
        }
    }

    # Mises à jour / hotfix / parents
    if ($Properties.PSObject.Properties.Name -contains 'ReleaseType') {
        $releaseType = [string]$Properties.ReleaseType
        if ($releaseType -like '*Update*' -or $releaseType -like '*Hotfix*') {
            return $false
        }
    }

    if ($Properties.PSObject.Properties.Name -contains 'ParentDisplayName') {
        if (-not [string]::IsNullOrWhiteSpace($Properties.ParentDisplayName)) {
            return $false
        }
    }

    # Filtrage par nom (patterns simples, on ajustera au besoin)
    $excludeNamePatterns = @(
        '*Update*',
        '*Hotfix*',
        'Microsoft .NET*',
        'Microsoft Visual C++*',
        'VC++*',
        '*Redistributable*',
        '*Runtime*',
        'Microsoft Edge WebView2*',
        'NVIDIA * Driver*',
        '*Graphics Driver*',
        '*Driver*'
    )

    foreach ($pattern in $excludeNamePatterns) {
        if ($name -like $pattern) {
            return $false
        }
    }

    return $true
}

function Get-MWInstalledApplications {
    <#
        .SYNOPSIS
        Retourne la liste des applications installées "utilisateur".

        .DESCRIPTION
        Parcourt :
        - HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
        - HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
        - HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall

        Filtre les entrées système / mises à jour, et renvoie des objets
        propres pour l'export.
    #>

    Write-MWLogSafe -Message 'Recensement des applications installées (Get-MWInstalledApplications).' -Level 'INFO'

    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $apps = @()

    foreach ($path in $uninstallPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $subKeys = Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue
        }
        catch {
            # On ignore les branches de registre qui posent problème
            continue
        }

        foreach ($subKey in $subKeys) {
            try {
                $props = Get-ItemProperty -LiteralPath $subKey.PSPath -ErrorAction SilentlyContinue

                if (-not (Test-MWIsUserFacingApp -Properties $props)) {
                    continue
                }

                $obj = [pscustomobject]@{
                    Name            = [string]$props.DisplayName
                    Version         = [string]$props.DisplayVersion
                    Publisher       = [string]$props.Publisher
                    InstallLocation = [string]$props.InstallLocation
                    UninstallString = [string]$props.UninstallString
                    # Prévu pour l'intégration RuckZuck
                    RuckZuckId      = $null
                }

                $apps += $obj
            }
            catch {
                # On ignore les entrées qui posent problème
            }
        }
    }

    # On évite les doublons simples sur le nom + version
    $result = $apps |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } |
        Sort-Object Name, Version -Unique

    Write-MWLogSafe -Message ("Get-MWInstalledApplications : {0} applications retenues après filtrage." -f $result.Count) -Level 'INFO'

    return $result
}

function Get-MWRuckZuckPath {
    <#
        .SYNOPSIS
        Tente de localiser rzget.exe (RuckZuck) sur le poste.

        .DESCRIPTION
        On regarde à plusieurs endroits :
        - Racine du projet (à côté de MigrationWizard.Main.ps1)
        - Dossier Tools\ à la racine
        - Dossier du script courant (utile plus tard si compilé)
    #>
    [CmdletBinding()]
    param()

    $candidates = @()

    try {
        # PSScriptRoot = ...\src\Core
        $srcRoot  = Split-Path -Parent $PSScriptRoot
        $repoRoot = Split-Path -Parent $srcRoot  # racine du projet

        $candidates += (Join-Path $repoRoot 'rzget.exe')
        $candidates += (Join-Path (Join-Path $repoRoot 'Tools') 'rzget.exe')
    }
    catch {
        # On ne bloque pas si erreur
    }

    try {
        if ($MyInvocation.PSCommandPath) {
            $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
            $candidates += (Join-Path $scriptDir 'rzget.exe')
        }
    }
    catch {
    }

    $candidates = $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -Unique

    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-MWLogSafe -Message "Get-MWRuckZuckPath : rzget.exe introuvable." -Level 'DEBUG'
        return $null
    }

    if ($candidates.Count -gt 1) {
        Write-MWLogSafe -Message ("Get-MWRuckZuckPath : plusieurs rzget.exe trouvés, utilisation de : {0}" -f $candidates[0]) -Level 'WARN'
    }
    else {
        Write-MWLogSafe -Message ("Get-MWRuckZuckPath : rzget.exe détecté à l'emplacement : {0}" -f $candidates[0]) -Level 'INFO'
    }

    return $candidates[0]
}

function Find-MWRuckZuckPackageForApp {
    <#
        .SYNOPSIS
        Cherche un package RuckZuck correspondant à une application installée.

        .PARAMETER App
        Objet application tel que renvoyé par Get-MWInstalledApplications.

        .PARAMETER RZExePath
        Chemin explicite vers rzget.exe (sinon Get-MWRuckZuckPath est utilisé).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$App,

        [Parameter(Mandatory = $false)]
        [string]$RZExePath
    )

    if (-not $App -or -not $App.Name) {
        return $null
    }

    if (-not $RZExePath) {
        $RZExePath = Get-MWRuckZuckPath
        if (-not $RZExePath) {
            return $null
        }
    }

    $name      = [string]$App.Name
    $publisher = [string]$App.Publisher

    Write-MWLogSafe -Message ("Find-MWRuckZuckPackageForApp : recherche pour ""{0}"" (Publisher = ""{1}"")." -f $name, $publisher) -Level 'DEBUG'

    try {
        # On lance : rzget.exe search "<nom appli>"
        $args = @('search', $name)
        $raw  = & $RZExePath @args 2>$null

        if (-not $raw) {
            return $null
        }

        $results = $null
        try {
            $results = $raw | ConvertFrom-Json
        }
        catch {
            Write-MWLogSafe -Message ("Find-MWRuckZuckPackageForApp : réponse non JSON pour ""{0}"" : {1}" -f $name, $_) -Level 'DEBUG'
            return $null
        }

        if (-not $results) {
            return $null
        }

        # Normaliser en tableau
        if ($results -isnot [System.Collections.IEnumerable] -or $results -is [string]) {
            $results = @($results)
        }

        # Si on a un publisher, on filtre un peu
        if (-not [string]::IsNullOrWhiteSpace($publisher)) {
            $filtered = $results | Where-Object {
                $_.Manufacturer -and ($_.Manufacturer -like ("*" + $publisher + "*"))
            }

            if ($filtered) {
                $results = $filtered
            }
        }

        # On prend le premier résultat
        $first = $results | Select-Object -First 1
        if ($null -eq $first) {
            return $null
        }

        $shortName = $first.Shortname
        if ([string]::IsNullOrWhiteSpace($shortName)) {
            return $null
        }

        Write-MWLogSafe -Message ("Find-MWRuckZuckPackageForApp : package trouvé pour ""{0}"" -> {1}" -f $name, $shortName) -Level 'DEBUG'
        return $shortName
    }
    catch {
        Write-MWLogSafe -Message ("Find-MWRuckZuckPackageForApp : erreur lors de la recherche pour ""{0}"" : {1}" -f $name, $_) -Level 'DEBUG'
        return $null
    }
}

function Get-MWApplicationsForExport {
    <#
        .SYNOPSIS
        Prépare la liste des applications pour l'export MigrationWizard.

        .DESCRIPTION
        Récupère la liste des applications installées et, si rzget.exe
        (RuckZuck) est disponible, tente de trouver un package pour
        chacune d'elles. Le résultat est prêt à être sérialisé dans
        la section "Applications" du snapshot d'export.
    #>
    [CmdletBinding()]
    param(
        [switch]$SkipRuckZuck
    )

    Write-MWLogSafe -Message "Get-MWApplicationsForExport : préparation de la liste des applications..." -Level 'INFO'

    $apps = Get-MWInstalledApplications

    if (-not $apps -or $apps.Count -eq 0) {
        Write-MWLogSafe -Message "Get-MWApplicationsForExport : aucune application installée détectée." -Level 'INFO'
        return @()
    }

    if ($SkipRuckZuck) {
        $apps | ForEach-Object {
            if (-not $_.PSObject.Properties['RuckZuckId']) {
                $_ | Add-Member -MemberType NoteProperty -Name 'RuckZuckId' -Value $null
            }
        }
        return $apps
    }

    $rzPath = Get-MWRuckZuckPath
    if (-not $rzPath) {
        Write-MWLogSafe -Message "Get-MWApplicationsForExport : RuckZuck (rzget.exe) introuvable, aucune correspondance ne sera recherchée." -Level 'WARN'

        $apps | ForEach-Object {
            if (-not $_.PSObject.Properties['RuckZuckId']) {
                $_ | Add-Member -MemberType NoteProperty -Name 'RuckZuckId' -Value $null
            }
        }
        return $apps
    }

    Write-MWLogSafe -Message ("Get-MWApplicationsForExport : RuckZuck détecté ({0}). Recherche des packages..." -f $rzPath) -Level 'INFO'

    $annotated = @()
    $withRZ   = 0

    foreach ($app in $apps) {
        if (-not $app) { continue }

        $rzId = Find-MWRuckZuckPackageForApp -App $app -RZExePath $rzPath

        $obj = [pscustomobject]@{
            Name            = $app.Name
            Version         = $app.Version
            Publisher       = $app.Publisher
            InstallLocation = $app.InstallLocation
            UninstallString = $app.UninstallString
            RuckZuckId      = $null
        }

        if ($rzId) {
            $obj.RuckZuckId = $rzId
            $withRZ++
        }

        $annotated += $obj
    }

    Write-MWLogSafe -Message ("Get-MWApplicationsForExport : {0} applications, dont {1} avec un package RuckZuck." -f $annotated.Count, $withRZ) -Level 'INFO'

    return $annotated
}

function Get-MWMissingApplicationsFromExport {
    <#
        .SYNOPSIS
        Détermine quelles applications de l’export ne sont pas présentes
        sur la machine actuelle.

        .PARAMETER ExportedApplications
        Tableau d’applications tel que lu depuis le fichier d’export
        (section "Applications").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Object[]]$ExportedApplications
    )

    Write-MWLogSafe -Message "Comparaison des applications exportées avec celles installées (Get-MWMissingApplicationsFromExport)." -Level 'INFO'

    $currentApps = Get-MWInstalledApplications
    $missing     = @()

    foreach ($exp in $ExportedApplications) {
        if ($null -eq $exp) { continue }

        $name    = [string]$exp.Name
        $version = [string]$exp.Version

        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $match = $currentApps | Where-Object {
            $_.Name -eq $name -and (
                [string]::IsNullOrWhiteSpace($version) -or
                $_.Version -eq $version
            )
        }

        if (-not $match) {
            $missing += [pscustomobject]@{
                Name       = $name
                Version    = $version
                Publisher  = [string]$exp.Publisher
                RuckZuckId = $exp.RuckZuckId
            }
        }
    }

    Write-MWLogSafe -Message ("Get-MWMissingApplicationsFromExport : {0} applications à proposer à l'installation." -f $missing.Count) -Level 'INFO'

    return $missing
}

Export-ModuleMember -Function `
    Get-MWInstalledApplications, `
    Get-MWApplicationsForExport, `
    Get-MWMissingApplicationsFromExport
