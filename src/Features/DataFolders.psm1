# src/Features/DataFolders.psm1
# Futur module pour gérer l’export / import des dossiers de données utilisateur
# (Documents, Bureau, dossiers perso, etc.) via le moteur de copie de FileCopy.psm1.

function Export-MWDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Export des dossiers de données utilisateur.
        .DESCRIPTION
            S’appuiera plus tard sur la configuration d’arborescence (dossiers standard
            + personnalisés) et sur le moteur de copie du module FileCopy.
            Pour l’instant, c’est juste un placeholder qui logue l’appel.
    #>

    try {
        Write-MWLogInfo ("Export-MWDataFolders appelé vers '{0}' (fonction non encore implémentée)." -f $DestinationFolder)
        # TODO : implémenter la copie réelle des dossiers (Documents, Bureau, etc.).
    } catch {
        Write-MWLogError ("Export-MWDataFolders : {0}" -f $_.Exception.Message)
        throw
    }
}

function Import-MWDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Import des dossiers de données utilisateur.
        .DESCRIPTION
            Fera l’inverse de Export-MWDataFolders en se basant sur la même
            configuration d’arborescence. Pour l’instant, simple placeholder.
    #>

    try {
        Write-MWLogInfo ("Import-MWDataFolders appelé depuis '{0}' (fonction non encore implémentée)." -f $SourceFolder)
        # TODO : implémenter la restauration réelle des dossiers (Documents, Bureau, etc.).
    } catch {
        Write-MWLogError ("Import-MWDataFolders : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Export-MWDataFolders, Import-MWDataFolders
