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
            Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue

                    if (-not (Test-MWIsUserFacingApp -Properties $props)) {
                        return
                    }

                    $obj = [pscustomobject]@{
                        Name            = [string]$props.DisplayName
                        Version         = [string]$props.DisplayVersion
                        Publisher       = [string]$props.Publisher
                        InstallLocation = [string]$props.InstallLocation
                        UninstallString = [string]$props.UninstallString
                        # Prévu pour plus tard : ID/nom RuckZuck si on trouve une correspondance
                        RuckZuckId      = $null
                    }

                    $apps += $obj
                }
                catch {
                    # On ignore les entrées qui posent problème
                }
            }
        }
        catch {
            # On ignore les branches de registre qui posent problème
        }
    }

    # On évite les doublons simples sur le nom + version
    $result = $apps |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } |
        Sort-Object Name, Version -Unique

    Write-MWLogSafe -Message ("Get-MWInstalledApplications : {0} applications retenues après filtrage." -f $result.Count) -Level 'INFO'

    return $result
}

function Get-MWApplicationsForExport {
    <#
        .SYNOPSIS
        Prépare la liste des applications pour l'export MigrationWizard.

        .DESCRIPTION
        Renvoie simplement la liste des applications installées au format
        prêt à être sérialisé en JSON (section "Applications" du futur fichier
        d'export).
    #>
    $apps = Get-MWInstalledApplications
    return $apps
}

Export-ModuleMember -Function Get-MWInstalledApplications, Get-MWApplicationsForExport
