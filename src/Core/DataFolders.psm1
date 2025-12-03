# Module : Core/DataFolders
# Gestion des dossiers "classiques" du profil utilisateur pour l'export.
# Objectif de cette première version :
#   - Définir la liste des dossiers utilisateur à gérer (Bureau, Documents, etc.).
#   - Construire un "manifest" décrivant ces dossiers.
#   - Sauvegarder ce manifest en JSON à l'emplacement demandé.
#
# NOTE : Test-MWLogAvailable et Write-MWLogSafe sont maintenant centralisés
#        dans le module MW.Logging.psm1

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
            $standard = Join-Path -Path $UserProfilePath -ChildPath $rel
            
            # CORRECTION OneDrive : résoudre le vrai chemin (OneDrive si KFM activé)
            if (Get-Command -Name Resolve-MWPathWithOneDrive -ErrorAction SilentlyContinue) {
                $full = Resolve-MWPathWithOneDrive -Path $standard
                Write-MWLogSafe -Message ("Export manifest : {0} standard='{1}' résolu='{2}'" -f $folder.Key, $standard, $full) -Level 'DEBUG'
            } else {
                $full = $standard
            }
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
        SourcePath   = $full  # Maintenant, c'est le vrai chemin OneDrive si KFM activé
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

function Get-MWDataFoldersManifest {
    <#
        .SYNOPSIS
        Charge le manifeste des dossiers utilisateur (JSON) et le renvoie sous forme d’objets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    Write-MWLogSafe -Message ("Get-MWDataFoldersManifest : chargement du manifeste '{0}'." -f $ManifestPath) -Level 'INFO'

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        Write-MWLogSafe -Message ("Get-MWDataFoldersManifest : fichier introuvable : {0}" -f $ManifestPath) -Level 'WARN'
        return @()
    }

    try {
        $json   = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
        $items  = $json | ConvertFrom-Json
    }
    catch {
        Write-MWLogSafe -Message ("Get-MWDataFoldersManifest : erreur lors du parsing JSON : {0}" -f $_) -Level 'ERROR'
        return @()
    }

    if (-not $items) {
        return @()
    }

    if ($items -isnot [System.Collections.IEnumerable] -or $items -is [string]) {
        $items = @($items)
    }

    return $items
}

function Export-MWDataFolders {
    <#
        .SYNOPSIS
        Exporte les dossiers utilisateur définis dans le manifeste vers un répertoire d’export.

        .PARAMETER ManifestPath
        Chemin du fichier DataFolders.manifest.json.

        .PARAMETER DestinationRoot
        Répertoire racine d’export (ex: .\Logs\UserData).

        .PARAMETER WhatIf
        Simule l’export sans lancer robocopy.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    Write-MWLogSafe -Message ("Export-MWDataFolders : export des données vers '{0}'." -f $DestinationRoot) -Level 'INFO'

    $items = Get-MWDataFoldersManifest -ManifestPath $ManifestPath
    if (-not $items -or $items.Count -eq 0) {
        Write-MWLogSafe -Message "Export-MWDataFolders : manifeste vide, rien à exporter." -Level 'WARN'
        return
    }

    if (-not (Test-Path -LiteralPath $DestinationRoot)) {
        try {
            New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
        }
        catch {
            Write-MWLogSafe -Message ("Export-MWDataFolders : impossible de créer '{0}' : {1}" -f $DestinationRoot, $_) -Level 'ERROR'
            return
        }
    }

    foreach ($item in $items) {
        if (-not $item) { continue }

        $key       = [string]$item.Key
        $src       = [string]$item.SourcePath
        $rel       = [string]$item.RelativePath

        $include = $true
        if ($item.PSObject.Properties.Name -contains 'Include') {
            $include = [bool]$item.Include
        }

        if (-not $include) {
            Write-MWLogSafe -Message ("Export-MWDataFolders : '{0}' marqué comme non inclus, on ignore." -f $key) -Level 'DEBUG'
            continue
        }

        if ([string]::IsNullOrWhiteSpace($src) -or [string]::IsNullOrWhiteSpace($rel)) {
            Write-MWLogSafe -Message ("Export-MWDataFolders : entrée invalide (Key='{0}') : chemin vide." -f $key) -Level 'WARN'
            continue
        }

        if (-not (Test-Path -LiteralPath $src)) {
            Write-MWLogSafe -Message ("Export-MWDataFolders : source introuvable pour '{0}' : {1}" -f $key, $src) -Level 'WARN'
            continue
        }

        $dst = Join-Path -Path $DestinationRoot -ChildPath $rel

        if (-not (Test-Path -LiteralPath $dst)) {
            try {
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
            }
            catch {
                Write-MWLogSafe -Message ("Export-MWDataFolders : impossible de créer '{0}' : {1}" -f $dst, $_) -Level 'ERROR'
                continue
            }
        }

        $target = ("{0} -> {1}" -f $src, $dst)

        if ($PSCmdlet.ShouldProcess($target, "Copie des données (export)")) {
            Write-MWLogSafe -Message ("Export-MWDataFolders : copie de '{0}' vers '{1}'." -f $src, $dst) -Level 'INFO'

            try {
                $args = @(
                    $src,
                    $dst,
                    '/E',          # Sous-dossiers, y compris vides
                    '/COPY:DAT',   # Données, attributs, timestamps (pas les ACL)
                    '/R:2',        # 2 tentatives
                    '/W:5',        # 5s d’attente
                    '/NFL','/NDL', # Pas de liste de fichiers/dossiers
                    '/NP',         # Pas de pourcentage
                    '/NJH','/NJS'  # Pas de header/summary
                )

                & robocopy.exe @args | Out-Null
                $code = $LASTEXITCODE

                Write-MWLogSafe -Message ("Export-MWDataFolders : robocopy terminé pour '{0}' (code {1})." -f $key, $code) -Level 'DEBUG'
            }
            catch {
                Write-MWLogSafe -Message ("Export-MWDataFolders : erreur lors de la copie de '{0}' : {1}" -f $key, $_) -Level 'ERROR'
            }
        }
    }
}

function Import-MWDataFolders {
    <#
        .SYNOPSIS
        Importe les dossiers utilisateur à partir du répertoire d’export vers
        les dossiers spéciaux du profil courant.
        ...
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    Write-MWLogSafe -Message ("Import-MWDataFolders : import des données depuis '{0}'." -f $SourceRoot) -Level 'INFO'

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        Write-MWLogSafe -Message ("Import-MWDataFolders : SourceRoot introuvable : {0}" -f $SourceRoot) -Level 'ERROR'
        return
    }

    $items = Get-MWDataFoldersManifest -ManifestPath $ManifestPath
    if (-not $items -or $items.Count -eq 0) {
        Write-MWLogSafe -Message "Import-MWDataFolders : manifeste vide, rien à importer." -Level 'WARN'
        return
    }

    # Dossiers cibles pour le profil courant (Desktop, Documents, etc.)
    # On reconstruit un manifest pour le profil actuel afin d'avoir les bons chemins.
    $targetManifest = New-MWDataFoldersManifest
    $targetsByKey   = @{}

    foreach ($t in $targetManifest) {
        if (-not $t) { continue }

        $k = [string]$t.Key
        $p = [string]$t.SourcePath

        if ([string]::IsNullOrWhiteSpace($k) -or [string]::IsNullOrWhiteSpace($p)) {
            continue
        }

        $targetsByKey[$k] = $p
    }

    foreach ($item in $items) {
        if (-not $item) { continue }

        $key       = [string]$item.Key
        $rel       = [string]$item.RelativePath

        $include = $true
        if ($item.PSObject.Properties.Name -contains 'Include') {
            $include = [bool]$item.Include
        }

        if (-not $include) {
            Write-MWLogSafe -Message ("Import-MWDataFolders : '{0}' marqué comme non inclus, on ignore." -f $key) -Level 'DEBUG'
            continue
        }

        if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($rel)) {
            Write-MWLogSafe -Message ("Import-MWDataFolders : entrée invalide (Key='{0}') : RelativePath vide." -f $key) -Level 'WARN'
            continue
        }

        if (-not $targetsByKey.ContainsKey($key)) {
            Write-MWLogSafe -Message ("Import-MWDataFolders : aucun dossier cible connu pour la clé '{0}', on ignore." -f $key) -Level 'WARN'
            continue
        }

        $src = Join-Path -Path $SourceRoot -ChildPath $rel
        $dst = [string]$targetsByKey[$key]

        if (-not (Test-Path -LiteralPath $src)) {
            Write-MWLogSafe -Message ("Import-MWDataFolders : source d'import introuvable pour '{0}' : {1}" -f $key, $src) -Level 'WARN'
            continue
        }

        if (-not (Test-Path -LiteralPath $dst)) {
            try {
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
            }
            catch {
                Write-MWLogSafe -Message ("Import-MWDataFolders : impossible de créer '{0}' : {1}" -f $dst, $_) -Level 'ERROR'
                continue
            }
        }

        $target = ("{0} -> {1}" -f $src, $dst)

        if ($PSCmdlet.ShouldProcess($target, "Copie des données (import)")) {
            Write-MWLogSafe -Message ("Import-MWDataFolders : copie de '{0}' vers '{1}'." -f $src, $dst) -Level 'INFO'

            try {
                $args = @(
                    $src,
                    $dst,
                    '/E',
                    '/COPY:DAT',
                    '/R:2',
                    '/W:5',
                    '/NFL','/NDL',
                    '/NP',
                    '/NJH','/NJS'
                )

                & robocopy.exe @args | Out-Null
                $code = $LASTEXITCODE

                Write-MWLogSafe -Message ("Import-MWDataFolders : robocopy terminé pour '{0}' (code {1})." -f $key, $code) -Level 'DEBUG'
            }
            catch {
                Write-MWLogSafe -Message ("Import-MWDataFolders : erreur lors de la copie de '{0}' : {1}" -f $key, $_) -Level 'ERROR'
            }
        }
    }
}

function Show-MWDataFoldersExportPlan {
    <#
        .SYNOPSIS
        Affiche la liste des dossiers utilisateur à exporter
        et lance l'export après sélection.

        .DESCRIPTION
        - (Re)génère le manifest si besoin.
        - Charge le manifest.
        - Affiche les dossiers dans un Out-GridView avec sélection multiple.
        - Met à jour la propriété Include en fonction de la sélection.
        - Sauvegarde le manifest modifié.
        - Lance Export-MWDataFolders avec ce manifest.

        Cette fonction est pensée comme un mode interactif "je choisis
        ce que j'exporte". Pas de -WhatIf ici : si tu veux simuler,
        utilise directement Export-MWDataFolders -WhatIf.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    Write-MWLogSafe -Message ("Show-MWDataFoldersExportPlan : préparation de l'export vers '{0}' avec manifest '{1}'." -f $DestinationRoot, $ManifestPath) -Level 'INFO'

    # (Re)générer le manifest si le fichier n'existe pas
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        Write-MWLogSafe -Message ("Show-MWDataFoldersExportPlan : manifest introuvable, génération : {0}" -f $ManifestPath) -Level 'INFO'
        Save-MWDataFoldersManifest -ManifestPath $ManifestPath
    }

    $items = Get-MWDataFoldersManifest -ManifestPath $ManifestPath
    if (-not $items -or $items.Count -eq 0) {
        Write-MWLogSafe -Message "Show-MWDataFoldersExportPlan : manifest vide, rien à proposer." -Level 'WARN'
        return
    }

    # Affichage interactif : sélection des dossiers à inclure
    $selected = $items |
        Select-Object Key, Label, SourcePath, RelativePath, Exists, Include |
        Out-GridView -Title "Dossiers à exporter (sélectionne ceux à inclure)" -PassThru

    if (-not $selected) {
        Write-MWLogSafe -Message "Show-MWDataFoldersExportPlan : aucune sélection effectuée." -Level 'INFO'
        return
    }

    # On met à jour la propriété Include en fonction de la sélection
    $selectedKeys = @($selected | ForEach-Object { [string]$_.Key })

    foreach ($item in $items) {
        if (-not $item) { continue }

        $k = [string]$item.Key
        $item.Include = $selectedKeys -contains $k
    }

    # On resauvegarde le manifest mis à jour
    try {
        $json = $items | ConvertTo-Json -Depth 5
        $json | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
        Write-MWLogSafe -Message "Show-MWDataFoldersExportPlan : manifest mis à jour avec la sélection utilisateur." -Level 'INFO'
    }
    catch {
        Write-MWLogSafe -Message ("Show-MWDataFoldersExportPlan : erreur lors de l'enregistrement du manifest : {0}" -f $_) -Level 'ERROR'
        return
    }

    # Puis on lance l'export réel (pas de -WhatIf ici, c'est volontaire)
    Write-MWLogSafe -Message "Show-MWDataFoldersExportPlan : lancement de Export-MWDataFolders avec le manifest sélectionné." -Level 'INFO'
    Export-MWDataFolders -ManifestPath $ManifestPath -DestinationRoot $DestinationRoot
}

function Show-MWDataFoldersImportPlan {
    <#
        .SYNOPSIS
        Affiche la liste des dossiers utilisateur à importer
        et lance l'import après sélection.

        .DESCRIPTION
        - Charge le manifest d'export.
        - Recalcule les chemins cibles pour le profil courant.
        - Affiche une grille avec SourcePath (dans UserData) et TargetPath.
        - Met à jour Include selon la sélection.
        - Sauvegarde le manifest puis appelle Import-MWDataFolders.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    Write-MWLogSafe -Message ("Show-MWDataFoldersImportPlan : préparation de l'import depuis '{0}' avec manifest '{1}'." -f $SourceRoot, $ManifestPath) -Level 'INFO'

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        Write-MWLogSafe -Message ("Show-MWDataFoldersImportPlan : SourceRoot introuvable : {0}" -f $SourceRoot) -Level 'ERROR'
        return
    }

    $items = Get-MWDataFoldersManifest -ManifestPath $ManifestPath
    if (-not $items -or $items.Count -eq 0) {
        Write-MWLogSafe -Message "Show-MWDataFoldersImportPlan : manifest vide, rien à proposer." -Level 'WARN'
        return
    }

    # Dossiers cibles pour le profil courant
    $targetManifest = New-MWDataFoldersManifest
    $targetsByKey   = @{}

    foreach ($t in $targetManifest) {
        if (-not $t) { continue }

        $k = [string]$t.Key
        $p = [string]$t.SourcePath

        if ([string]::IsNullOrWhiteSpace($k) -or [string]::IsNullOrWhiteSpace($p)) {
            continue
        }

        $targetsByKey[$k] = $p
    }

    # Objets pour la grille
    $gridItems = @()

    foreach ($item in $items) {
        if (-not $item) { continue }

        $key   = [string]$item.Key
        $rel   = [string]$item.RelativePath
        $incl  = $true

        if ($item.PSObject.Properties.Name -contains 'Include') {
            $incl = [bool]$item.Include
        }

        $srcPath = $null
        if (-not [string]::IsNullOrWhiteSpace($rel)) {
            try {
                $srcPath = Join-Path -Path $SourceRoot -ChildPath $rel
            }
            catch {
                $srcPath = $null
            }
        }

        $srcExists = $false
        if ($srcPath -and (Test-Path -LiteralPath $srcPath -PathType Container)) {
            $srcExists = $true
        }

        $targetPath = $null
        if ($targetsByKey.ContainsKey($key)) {
            $targetPath = [string]$targetsByKey[$key]
        }

        $gridItems += [pscustomobject]@{
            Key          = $key
            Label        = [string]$item.Label
            SourcePath   = $srcPath
            TargetPath   = $targetPath
            SourceExists = $srcExists
            Include      = $incl
        }
    }

    if (-not $gridItems -or $gridItems.Count -eq 0) {
        Write-MWLogSafe -Message "Show-MWDataFoldersImportPlan : aucun élément à afficher." -Level 'WARN'
        return
    }

    $selected = $gridItems |
        Out-GridView -Title "Dossiers à importer (sélectionne ceux à inclure)" -PassThru

    if (-not $selected) {
        Write-MWLogSafe -Message "Show-MWDataFoldersImportPlan : aucune sélection effectuée." -Level 'INFO'
        return
    }

    $selectedKeys = @($selected | ForEach-Object { [string]$_.Key })

    foreach ($item in $items) {
        if (-not $item) { continue }

        $k = [string]$item.Key
        $item.Include = $selectedKeys -contains $k
    }

    # Sauvegarde du manifest mis à jour
    try {
        $json = $items | ConvertTo-Json -Depth 5
        $json | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
        Write-MWLogSafe -Message "Show-MWDataFoldersImportPlan : manifest mis à jour avec la sélection utilisateur." -Level 'INFO'
    }
    catch {
        Write-MWLogSafe -Message ("Show-MWDataFoldersImportPlan : erreur lors de l'enregistrement du manifest : {0}" -f $_) -Level 'ERROR'
        return
    }

    # Lancement de l'import réel
    Write-MWLogSafe -Message "Show-MWDataFoldersImportPlan : lancement de Import-MWDataFolders avec le manifest sélectionné." -Level 'INFO'
    Import-MWDataFolders -ManifestPath $ManifestPath -SourceRoot $SourceRoot
}

Export-ModuleMember -Function `
    Get-MWDefaultDataFolders, `
    New-MWDataFoldersManifest, `
    Save-MWDataFoldersManifest, `
    Get-MWDataFoldersManifest, `
    Export-MWDataFolders, `
    Import-MWDataFolders, `
    Show-MWDataFoldersExportPlan, `
    Show-MWDataFoldersImportPlan