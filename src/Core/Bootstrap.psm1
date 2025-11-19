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
        Write-Warning "MigrationWizard doit Ãªtre exÃ©cutÃ© en STA (Single Threaded Apartment)."
    }
}

function Initialize-MWEnvironment {
    <#
        .SYNOPSIS
            PrÃ©pare l'environnement d'exÃ©cution de MigrationWizard.
        .DESCRIPTION
            VÃ©rifie la version de PowerShell, l'Ã©lÃ©vation administrateur
            et l'Ã©tat STA. Met en place une ID de session globale.
    #>

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "MigrationWizard nÃ©cessite PowerShell 5.1 minimum."
    }

    Confirm-MWStaThread

    if (-not (Test-MWIsAdministrator)) {
        Write-Warning "MigrationWizard n'est pas lancÃ© en tant qu'administrateur. Certaines fonctions peuvent Ã©chouer."
    }

    if (-not $Global:MWSessionId) {
        $Global:MWSessionId = (Get-Date -Format 'yyyyMMdd_HHmmss')
    }
}

Export-ModuleMember -Function Initialize-MWEnvironment, Test-MWIsAdministrator, Confirm-MWStaThread


