# src/Core/Bootstrap.psm1

function Test-MWIsAdministrator {
    [OutputType([bool])]
    param()

    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal       = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Confirm-MWStaThread {
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Write-Warning "MigrationWizard doit être exécuté en STA (Single Threaded Apartment)."
    }
}

function Initialize-MWEnvironment {
    <#
        .SYNOPSIS
            Prépare l'environnement d'exécution de MigrationWizard.
        .DESCRIPTION
            Vérifie la version de PowerShell, l'élévation administrateur
            et l'état STA. Met en place une ID de session globale.
    #>

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "MigrationWizard nécessite PowerShell 5.1 minimum."
    }

    Confirm-MWStaThread

    if (-not (Test-MWIsAdministrator)) {
        Write-Warning "MigrationWizard n'est pas lancé en tant qu'administrateur. Certaines fonctions peuvent échouer."
    }

    if (-not $Global:MWSessionId) {
        $Global:MWSessionId = (Get-Date -Format 'yyyyMMdd_HHmmss')
    }
}

function Start-MigrationWizard {
    [CmdletBinding()]
    param()

    Write-Verbose "Lancement de l'interface WPF MigrationWizard..."

    try {
        # La logique UI est dans src/UI/MigrationWizard.UI.psm1
        Start-MWMigrationWizardUI
    } catch {
        Write-MWLogError ("Erreur lors du lancement de l'UI : {0}" -f $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Initialize-MWEnvironment, Test-MWIsAdministrator, Confirm-MWStaThread, Start-MigrationWizard
