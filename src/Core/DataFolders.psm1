# Module : Core/DataFolders
# Gestion des dossiers "classiques" du profil utilisateur pour l'export.
# Objectif de cette première version :
#   - Définir la liste des dossiers utilisateur à gérer (Bureau, Documents, etc.).
#   - Construire un "manifest" décrivant ces dossiers.
#   - Sauvegarder ce manifest en JSON à l'emplacement demandé.

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
        # On ne casse jamais l'outil juste pour un log.
    }
}

function Get-MWDefaultDataFolders {
    <#
        .SYNOPSIS
        Retourne la liste des dossiers "classiques" du profil utilisateur.

        .DESCRIPTION
        Pour l'instant on colle à ce que tu avais dans ton ancien module UserData :
        - Bureau, Documents, Téléchargements, Images, Musique, Vidéos, Favoris, Liens, Contacts.

        Chaque entrée contient :
        - Key           : identifiant logique
        - RelativePath  : chemin relatif sous le profil (ex: "Desktop")
        - Label         : libellé pour l'UI
        - Include       : booléen, inclus par défaut
    #>
    [CmdletBinding()]
    param()

    $list = @(
        @{ Key = 'Desktop';   RelativePath = 'Desktop';   Label = 'Bureau';          Include = $true }
        @{ Key = 'Documents'; RelativePath = 'Documents'; Label = 'Documents';       Include = $true }
        @{ Key = 'Downloads'; RelativePath = 'Downloads'; Label = 'Téléchargements'; Include = $true }
        @{ Key = 'Pictures';  RelativePath = 'Pictures';  Label = 'Images';          Include = $true }
        @{ Key = 'Music';     RelativePath = 'Music';     Label = 'Musique';         Include = $true }
        @{ Key = 'Videos';    RelativePath = 'Videos';    Label = 'Vidéos';          Include = $true }
        @{ Key = 'Favorites'; RelativePath = 'Favorites'; Label = 'Favoris';         Include = $true }
        @{ Key = 'Links';     RelativePath = 'Links';     Label = 'Liens';           Include = $true }
        @{ Key = 'Contacts';  RelativePath = 'Contacts';  Label = 'Contacts';        Include = $true }
    )

    $objects = @()

    foreach ($item in $list) {
        $objects += [pscustomobject]@{
            Key          = [string]$item.Key
            RelativePath = [string]$item.RelativePath
            Label        = [string]$item.Label
            Include      = [bool]$item.Include
        }
    }

    return $objects
}

function New-MWDataFoldersManifest {
    <#
        .SYNOPSIS
        Construit l'objet "manifest" des dossiers utilisateur.

        .PARAMETER UserProfilePath
        Chemin du profil utilisateur (ex: C:\Users\jmthomas).
        Par défaut : $env:USERPROFILE (l'utilisateur courant).

        .DESCRIPTION
        Pour chaque dossier "classique" :
        - calcule le chemin complet SourcePath,
        - indique s'il existe vraiment (Exists),
        - expose aussi RelativePath, Label, Include.

        L'idée : ce manifest sera sérialisé en JSON et utilisé ensuite
        par l'export et l'import (UI).
    #>
    [CmdletBinding()]
    param(
        [string]$UserProfilePath = $env:USERPROFILE
    )

    if ([string]::IsNullOrWhiteSpace($UserProfilePath)) {
        $UserProfilePath = $env:USERPROFILE
    }

    Write-MWLogSafe -Message ("New-MWDataFoldersManifest : construction du manifest pour le profil '{0}'." -f $UserProfilePath) -Level 'INFO'

    $folders = Get-MWDefaultDataFolders
    $manifest = @()

    foreach ($folder in $folders) {
        $rel  = [string]$folder.RelativePath
        $full = $null

        if (-not [string]::IsNullOrWhiteSpace($rel) -and -not [string]::IsNullOrWhiteSpace($UserProfilePath)) {
            try {
                $full = Join-Path -Path $UserProfilePath -ChildPath $rel
            }
            catch {
                $full = $null
            }
        }

        $exists = $false
        if ($full -and (Test-Path -LiteralPath $full -PathType Container)) {
            $exists = $true
        }

        $manifest += [pscustomobject]@{
            Key          = [string]$folder.Key
            Label        = [string]$folder.Label
            RelativePath = $rel
            SourcePath   = $full
            Exists       = $exists
            Include      = [bool]$folder.Include
        }
    }

    Write-MWLogSafe -Message ("New-MWDataFoldersManifest : {0} dossier(s) décrits dans le manifest." -f $manifest.Count) -Level 'INFO'

    return $manifest
}

function Save-MWDataFoldersManifest {
    <#
        .SYNOPSIS
        Sauvegarde le manifest des dossiers utilisateur au format JSON.

        .PARAMETER ManifestPath
        Chemin complet du fichier JSON à créer (ex: .\Logs\UserData\DataFolders.manifest.json).

        .PARAMETER UserProfilePath
        Chemin du profil utilisateur pour calculer les SourcePath.
        Par défaut : $env:USERPROFILE.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [string]$UserProfilePath = $env:USERPROFILE
    )

    Write-MWLogSafe -Message ("Save-MWDataFoldersManifest : génération du manifest vers '{0}'." -f $ManifestPath) -Level 'INFO'

    try {
        $manifest = New-MWDataFoldersManifest -UserProfilePath $UserProfilePath

        $dir = Split-Path -Path $ManifestPath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            catch {
                Write-MWLogSafe -Message ("Save-MWDataFoldersManifest : impossible de créer le dossier '{0}'." -f $dir) -Level 'ERROR'
                throw
            }
        }

        $json = $manifest | ConvertTo-Json -Depth 5
        $json | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

        Write-MWLogSafe -Message "Save-MWDataFoldersManifest : manifest enregistré avec succès." -Level 'INFO'
    }
    catch {
        Write-MWLogSafe -Message ("Save-MWDataFoldersManifest : erreur lors de l'enregistrement du manifest : {0}" -f $_) -Level 'ERROR'
        throw
    }
}

Export-ModuleMember -Function `
    Get-MWDefaultDataFolders, `
    New-MWDataFoldersManifest, `
    Save-MWDataFoldersManifest
