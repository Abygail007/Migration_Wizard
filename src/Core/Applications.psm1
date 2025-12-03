# Module : Core/Applications
# Recensement des applications installées (côté utilisateur)
# Objectif : fournir une liste propre pour l'export, et préparer
# une future intégration avec RuckZuck.
#
# NOTE : Test-MWLogAvailable et Write-MWLogSafe sont maintenant centralises
#        dans le module MW.Logging.psm1

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
        Objectif : que ça marche depuis n'importe quel chemin.
        On ne dépend JAMAIS du répertoire courant, uniquement
        de l'endroit où se trouve :

        - le script / module (PSScriptRoot)
        - OU l'exécutable compilé (PS2EXE)

        On vérifie, dans cet ordre :

        1) Dossier de l'exécutable (si on est compilé) :
           <exeDir>\rzget.exe

        2) Dossier du script / module :
           <PSScriptRoot>\rzget.exe
           <PSScriptRoot>\Tools\rzget.exe

        3) Mode "dev" (ton repo Git) :
           <repoRoot>\Tools\rzget.exe
           <repoRoot>\rzget.exe
    #>
    [CmdletBinding()]
    param()

    $candidates = @()

    # 1) Cas EXE compilé (PS2EXE) : dossier de l'exe courant
    try {
        $proc     = [System.Diagnostics.Process]::GetCurrentProcess()
        $exePath  = $proc.MainModule.FileName
        $exeDir   = Split-Path -Parent $exePath

        if ($exeDir -and (Test-Path -LiteralPath $exeDir -PathType Container)) {
            # rzget.exe à côté du .exe => scénario production
            $candidates += (Join-Path $exeDir 'rzget.exe')
        }
    }
    catch {
        # Si on n'arrive pas à déterminer l'exe, on continue avec les autres pistes
    }

    # 2) Dossier du script / module (PSScriptRoot)
    try {
        if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot -PathType Container)) {
            # rzget.exe directement dans le même dossier que le script / module
            $candidates += (Join-Path $PSScriptRoot 'rzget.exe')

            # rzget.exe dans un sous-dossier Tools\
            $candidates += (Join-Path $PSScriptRoot 'Tools\rzget.exe')
        }
    }
    catch {
    }

    # 3) Mode "dev" : arborescence du repo Git
    try {
        # Si PSScriptRoot = ...\Github\src\Core
        # alors srcRoot = ...\Github\src
        # et repoRoot  = ...\Github
        $srcRoot  = $null
        $repoRoot = $null

        if ($PSScriptRoot) {
            $srcRoot  = Split-Path -Parent $PSScriptRoot
            if ($srcRoot) {
                $repoRoot = Split-Path -Parent $srcRoot
            }
        }

        if ($repoRoot -and (Test-Path -LiteralPath $repoRoot -PathType Container)) {
            $candidates += (Join-Path $repoRoot 'Tools\rzget.exe')
            $candidates += (Join-Path $repoRoot 'rzget.exe')
        }
    }
    catch {
        # On ne bloque pas si on ne parvient pas à remonter l'arbo
    }

    # Nettoyage des candidats : fichiers existants uniquement
    $candidates = $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -Unique

    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-MWLogSafe -Message "Get-MWRuckZuckPath : rzget.exe introuvable dans les emplacements prévus." -Level 'DEBUG'
        return $null
    }

    # On résout en chemins complets propres
    $resolved = @()
    foreach ($c in $candidates) {
        try {
            $resolved += (Get-Item -LiteralPath $c).FullName
        }
        catch {
            $resolved += $c
        }
    }

    # On force toujours un tableau, même s'il n'y a qu'un seul élément
    $resolved = @($resolved | Select-Object -Unique)

    $chosen = $resolved[0]

    if ($resolved.Count -gt 1) {
        Write-MWLogSafe -Message ("Get-MWRuckZuckPath : plusieurs rzget.exe trouvés, utilisation de : {0}" -f $chosen) -Level 'WARN'
    }
    else {
        Write-MWLogSafe -Message ("Get-MWRuckZuckPath : rzget.exe détecté à l'emplacement : {0}" -f $chosen) -Level 'INFO'
    }

    return $chosen
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

function Install-MWApplicationsFromExport {
    <#
        .SYNOPSIS
        Installe une liste d'applications à partir des données d'export MigrationWizard.

        .DESCRIPTION
        Cette fonction attend une liste d'objets applicatifs contenant
        au minimum :
        - Name
        - RuckZuckId (Shortname RuckZuck)

        Elle ne tente d'installer que les applications qui ont un RuckZuckId
        non vide, en utilisant RZGet.exe :

            RZGet.exe install "<Shortname>"

        Utilisation typique :

            $missing = Get-MWMissingApplicationsFromExport -ExportedApplications $snap.Applications
            $toInstall = $missing | Where-Object { $_.RuckZuckId }
            Install-MWApplicationsFromExport -ApplicationsToInstall $toInstall -WhatIf

        Le paramètre -WhatIf permet de tester sans réellement installer.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [Object[]]$ApplicationsToInstall = @()
    )

    if (-not $ApplicationsToInstall -or $ApplicationsToInstall.Count -eq 0) {
        Write-MWLogSafe -Message "Install-MWApplicationsFromExport : aucune application à installer (liste vide)." -Level 'INFO'
        return
    }

    Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : lancement pour {0} applications." -f $ApplicationsToInstall.Count) -Level 'INFO'

    $rzPath = Get-MWRuckZuckPath
    if (-not $rzPath) {
        Write-MWLogSafe -Message "Install-MWApplicationsFromExport : RuckZuck (rzget.exe) introuvable, installation impossible." -Level 'ERROR'
        return
    }

    foreach ($app in $ApplicationsToInstall) {
        if (-not $app) { continue }

        $name = [string]$app.Name
        $rzId = [string]$app.RuckZuckId

        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($rzId)) {
            Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : aucun RuckZuckId pour ""{0}"", on ignore." -f $name) -Level 'WARN'
            continue
        }

        $target = ('{0} (RuckZuckId = {1})' -f $name, $rzId)

        if ($PSCmdlet.ShouldProcess($target, "Installation via RuckZuck")) {
            Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : installation de ""{0}"" via RuckZuck ({1})." -f $name, $rzId) -Level 'INFO'

            try {
                & $rzPath 'install' $rzId
                $exitCode = $LASTEXITCODE

                if ($exitCode -eq 0) {
                    Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : installation OK pour ""{0}"" (code {1})." -f $name, $exitCode) -Level 'INFO'
                }
                else {
                    Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : installation échouée pour ""{0}"" (code {1})." -f $name, $exitCode) -Level 'ERROR'
                }
            }
            catch {
                Write-MWLogSafe -Message ("Install-MWApplicationsFromExport : exception lors de l'installation de ""{0}"" ({1}) : {2}" -f $name, $rzId, $_) -Level 'ERROR'
            }
        }
    }
}

function Get-MWApplicationsImportPlan {
    <#
        .SYNOPSIS
        Prépare la liste des applications à proposer à l'installation
        à partir de la section "Applications" d'un export.

        .DESCRIPTION
        Cette fonction est pensée pour être utilisée par l'UI :

            $snap = Import-MWExportSnapshot -Path "..."
            $plan = Get-MWApplicationsImportPlan -ExportedApplications $snap.Applications

        Elle renvoie la liste des applications manquantes, triées,
        avec leurs RuckZuckId éventuels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Object[]]$ExportedApplications
    )

    Write-MWLogSafe -Message "Get-MWApplicationsImportPlan : calcul des applications manquantes à partir de l'export." -Level 'INFO'

    $missing = Get-MWMissingApplicationsFromExport -ExportedApplications $ExportedApplications

    if (-not $missing -or $missing.Count -eq 0) {
        Write-MWLogSafe -Message "Get-MWApplicationsImportPlan : aucune application à proposer à l'installation." -Level 'INFO'
        return @()
    }

    $plan = $missing | Sort-Object Name, Version
    return $plan
}

function Invoke-MWApplicationsInstall {
    <#
        .SYNOPSIS
        Orchestration haut niveau pour l'installation des applications sélectionnées.

        .DESCRIPTION
        Pensée pour être appelée par l'UI après sélection des applis :

            $plan      = Get-MWApplicationsImportPlan -ExportedApplications $snap.Applications
            $selected  = $plan | Where-Object { $_.RuckZuckId -and $_.Install } # exemple, via l'UI
            Invoke-MWApplicationsInstall -ApplicationsToInstall $selected -WhatIf

        Le -WhatIf est supporté car la fonction interne Install-MWApplicationsFromExport
        supporte déjà ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [Object[]]$ApplicationsToInstall
    )

    if (-not $ApplicationsToInstall -or $ApplicationsToInstall.Count -eq 0) {
        Write-MWLogSafe -Message "Invoke-MWApplicationsInstall : liste reçue vide, rien à installer." -Level 'INFO'
        return
    }

    Write-MWLogSafe -Message ("Invoke-MWApplicationsInstall : {0} applications sélectionnées pour installation." -f $ApplicationsToInstall.Count) -Level 'INFO'

    # On délègue au moteur bas niveau
    Install-MWApplicationsFromExport -ApplicationsToInstall $ApplicationsToInstall
}

function Show-MWApplicationsImportPlan {
    <#
        .SYNOPSIS
        Affiche le plan d'import des applications dans un Out-GridView
        et permet de lancer l'installation via RuckZuck.

        .DESCRIPTION
        - Charge le snapshot d'export (JSON)
        - Génère le plan via Get-MWApplicationsImportPlan
        - Ouvre un Out-GridView avec sélection multiple
        - Installe en utilisant Install-MWApplicationsFromExport

        Par défaut, on ne met pas de -WhatIf ici, c'est vraiment le
        "mode interactif" où tu décides quoi installer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportPath
    )

    if (-not (Test-Path -LiteralPath $ExportPath)) {
        Write-MWLogSafe -Message ("Show-MWApplicationsImportPlan : fichier d'export introuvable : {0}" -f $ExportPath) -Level 'ERROR'
        return
    }

    try {
        $snap = Import-MWExportSnapshot -Path $ExportPath
    }
    catch {
        Write-MWLogSafe -Message ("Show-MWApplicationsImportPlan : erreur lors du chargement de l'export : {0}" -f $_) -Level 'ERROR'
        return
    }

    if (-not $snap -or -not $snap.Applications) {
        Write-MWLogSafe -Message "Show-MWApplicationsImportPlan : aucune section Applications dans le snapshot." -Level 'WARN'
        return
    }

    try {
        $plan = Get-MWApplicationsImportPlan -ExportedApplications $snap.Applications
    }
    catch {
        Write-MWLogSafe -Message ("Show-MWApplicationsImportPlan : erreur lors de la génération du plan : {0}" -f $_) -Level 'ERROR'
        return
    }

    if (-not $plan -or $plan.Count -eq 0) {
        Write-MWLogSafe -Message "Show-MWApplicationsImportPlan : aucune application manquante à proposer." -Level 'INFO'
        return
    }

    # Affichage interactif
    $selected = $plan |
        Select-Object Name, Version, Publisher, RuckZuckId |
        Out-GridView -Title "Applications à (ré)installer via RuckZuck" -PassThru

    if (-not $selected) {
        Write-MWLogSafe -Message "Show-MWApplicationsImportPlan : aucune application sélectionnée." -Level 'INFO'
        return
    }

    # On doit retrouver les objets complets dans $plan (avec toutes propriétés)
    $toInstall = @()
    foreach ($sel in $selected) {
        $name    = [string]$sel.Name
        $version = [string]$sel.Version

        $match = $plan | Where-Object {
            $_.Name -eq $name -and $_.Version -eq $version
        }

        if ($match) {
            $toInstall += $match
        }
    }

    if (-not $toInstall -or $toInstall.Count -eq 0) {
        Write-MWLogSafe -Message "Show-MWApplicationsImportPlan : rien à installer après résolution de la sélection." -Level 'INFO'
        return
    }

    Write-MWLogSafe -Message ("Show-MWApplicationsImportPlan : installation de {0} application(s) sélectionnée(s)." -f $toInstall.Count) -Level 'INFO'

    # Ici on installe réellement (pas de -WhatIf, c'est une action volontaire)
    Install-MWApplicationsFromExport -ApplicationsToInstall $toInstall
}

Export-ModuleMember -Function `
    Get-MWInstalledApplications, `
    Get-MWApplicationsForExport, `
    Get-MWMissingApplicationsFromExport, `
    Install-MWApplicationsFromExport, `
    Get-MWRuckZuckPath, `
    Find-MWRuckZuckPackageForApp, `
    Get-MWApplicationsImportPlan, `
    Invoke-MWApplicationsInstall, `
    Show-MWApplicationsImportPlan
