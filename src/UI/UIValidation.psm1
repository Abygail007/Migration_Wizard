# ==============================================================================
# UIValidation.psm1
# Module de validation des inputs utilisateur
# ==============================================================================

function Select-FolderDialog {
    <#
    .SYNOPSIS
    Affiche un dialogue de sélection de dossier
    .PARAMETER Title
    Titre du dialogue
    .PARAMETER InitialPath
    Chemin initial
    .OUTPUTS
    Chemin sélectionné ou $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Title = "Sélectionner un dossier",
        
        [Parameter(Mandatory=$false)]
        [string]$InitialPath = ""
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Title
    
    if ($InitialPath -and (Test-Path $InitialPath)) {
        $dialog.SelectedPath = $InitialPath
    }
    
    $result = $dialog.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-MWLogInfo "Dossier sélectionné : $($dialog.SelectedPath)"
        return $dialog.SelectedPath
    }
    
    Write-MWLogInfo "Sélection de dossier annulée"
    return $null
}

function Validate-ExportPath {
    <#
    .SYNOPSIS
    Valide un chemin d'export
    .PARAMETER Path
    Chemin à valider
    .PARAMETER ShowError
    Afficher une MessageBox en cas d'erreur
    .OUTPUTS
    $true si valide, $false sinon
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [bool]$ShowError = $true
    )
    
    # Vérifier si vide
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Veuillez spécifier un dossier de destination.",
                "Chemin manquant",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    # Vérifier si le chemin parent existe
    $parentPath = Split-Path -Path $Path -Parent
    
    if ($parentPath -and -not (Test-Path $parentPath)) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Le dossier parent n'existe pas : $parentPath",
                "Chemin invalide",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    # Si le dossier existe déjà, demander confirmation
    if (Test-Path $Path) {
        if ($ShowError) {
            $result = [System.Windows.MessageBox]::Show(
                "Le dossier existe déjà. Son contenu sera écrasé. Continuer ?",
                "Dossier existant",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            
            if ($result -eq [System.Windows.MessageBoxResult]::No) {
                return $false
            }
        }
    }
    
    Write-MWLogInfo "Chemin d'export validé : $Path"
    return $true
}

function Validate-ImportPath {
    <#
    .SYNOPSIS
    Valide un chemin d'import
    .PARAMETER Path
    Chemin à valider
    .PARAMETER ShowError
    Afficher une MessageBox en cas d'erreur
    .OUTPUTS
    $true si valide, $false sinon
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [bool]$ShowError = $true
    )
    
    # Vérifier si vide
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Veuillez sélectionner un dossier d'import.",
                "Chemin manquant",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    # Vérifier si le dossier existe
    if (-not (Test-Path $Path)) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Le dossier n'existe pas : $Path",
                "Chemin invalide",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    # Vérifier présence de ProfileInfo.json ou ExportManifest.json
    $hasProfileInfo = Test-Path (Join-Path $Path "ProfileInfo.json")
    $hasManifest = Test-Path (Join-Path $Path "ExportManifest.json")
    
    if (-not $hasProfileInfo -and -not $hasManifest) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Ce dossier ne contient pas d'export valide (ProfileInfo.json ou ExportManifest.json manquant).",
                "Export invalide",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    Write-MWLogInfo "Chemin d'import validé : $Path"
    return $true
}

function Validate-Selection {
    <#
    .SYNOPSIS
    Valide qu'au moins une option est cochée
    .PARAMETER UIControls
    Hashtable des contrôles à vérifier
    .PARAMETER ShowError
    Afficher une MessageBox en cas d'erreur
    .OUTPUTS
    $true si au moins une option cochée, $false sinon
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UIControls,
        
        [Parameter(Mandatory=$false)]
        [bool]$ShowError = $true
    )
    
    $hasSelection = $false
    
    # Vérifier les checkboxes
    foreach ($key in $UIControls.Keys) {
        $control = $UIControls[$key]
        
        if ($control -is [System.Windows.Controls.CheckBox]) {
            if ($control.IsChecked -eq $true) {
                $hasSelection = $true
                break
            }
        }
    }
    
    if (-not $hasSelection) {
        if ($ShowError) {
            [System.Windows.MessageBox]::Show(
                "Veuillez sélectionner au moins une option à migrer.",
                "Aucune sélection",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
        }
        return $false
    }
    
    Write-MWLogInfo "Validation sélection : OK"
    return $true
}

function Get-SafeFileName {
    <#
    .SYNOPSIS
    Génère un nom de fichier/dossier sécurisé
    .PARAMETER Name
    Nom à nettoyer
    .OUTPUTS
    Nom nettoyé
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeName = $Name
    
    foreach ($char in $invalidChars) {
        $safeName = $safeName.Replace($char, '_')
    }
    
    return $safeName
}

function Get-DefaultExportPath {
    <#
    .SYNOPSIS
    Retourne le dossier où l'EXE est exécuté comme destination par défaut
    .OUTPUTS
    Chemin du dossier d'exécution
    #>
    [CmdletBinding()]
    param()

    # Retourner le dossier où l'EXE/script est exécuté
    if ($Global:MWRootPath) {
        return $Global:MWRootPath
    }

    # Fallback : dossier courant
    return (Get-Location).Path
}

# Export des fonctions
Export-ModuleMember -Function @(
    'Select-FolderDialog',
    'Validate-ExportPath',
    'Validate-ImportPath',
    'Validate-Selection',
    'Get-SafeFileName',
    'Get-DefaultExportPath'
)
