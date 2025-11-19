# src/Core/Bootstrap.psm1

function Initialize-MWEnvironment {
    <#
        .SYNOPSIS
            Prépare l'environnement d'exécution de MigrationWizard.
        .DESCRIPTION
            Vérification version PowerShell, STA, élévation administrateur, etc.
            La logique détaillée sera ajoutée plus tard.
    #>
    Write-Verbose "[Bootstrap] Initialize-MWEnvironment (stub)"
}

Export-ModuleMember -Function Initialize-MWEnvironment
