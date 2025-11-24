# src/UI/MigrationWizard.UI.psm1
# Logique de la fenêtre WPF principale (chargement XAML + handlers)

function Start-MWMigrationWizardUI {
    <#
        .SYNOPSIS
            Lance la fenêtre WPF principale de MigrationWizard.
        .DESCRIPTION
            Charge le XAML, connecte les boutons Export/Import
            à Export-MWProfile / Import-MWProfile, gère le choix du dossier
            et affiche un statut simple.
    #>

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    } catch {
        Write-Warning ("Impossible de charger PresentationFramework (WPF) : {0}" -f $_.Exception.Message)
        return
    }

    # Localisation du XAML à partir du chemin du module UI
    $xamlPath = Join-Path $PSScriptRoot 'MigrationWizard.xaml'

    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        Write-MWLogError ("XAML introuvable : {0}" -f $xamlPath)
        return
    }

    try {
        $xamlContent = Get-Content -LiteralPath $xamlPath -Raw
        [xml]$xaml = $xamlContent
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-MWLogError ("Erreur lors du chargement du XAML : {0}" -f $_.Exception.Message)
        return
    }

    if (-not $window) {
        Write-MWLogError "Impossible de créer la fenêtre WPF à partir du XAML."
        return
    }

    # Récupération des contrôles
    $txtFolderPath = $window.FindName('txtFolderPath')
    $btnBrowse     = $window.FindName('btnBrowse')
    $btnExport     = $window.FindName('btnExport')
    $btnImport     = $window.FindName('btnImport')
    $lblStatus     = $window.FindName('lblStatus')

    if (-not $txtFolderPath -or -not $btnBrowse -or -not $btnExport -or -not $btnImport -or -not $lblStatus) {
        Write-MWLogWarning "Certains contrôles WPF n'ont pas été trouvés dans le XAML (vérifier les Name=...)."
    }

    # Petite fonction interne pour mettre à jour le statut
    function Set-MWUiStatus {
        param(
            [string]$Message
        )
        if ($lblStatus -ne $null) {
            $lblStatus.Text = $Message
        }
        Write-MWLogInfo ("UI: {0}" -f $Message)
    }

    # Handler "Parcourir..."
    if ($btnBrowse -and $txtFolderPath) {
        $btnBrowse.Add_Click({
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null

                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($txtFolderPath.Text -and (Test-Path -LiteralPath $txtFolderPath.Text)) {
                    $dialog.SelectedPath = $txtFolderPath.Text
                }

                $result = $dialog.ShowDialog()
                if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                    $txtFolderPath.Text = $dialog.SelectedPath
                    Set-MWUiStatus ("Dossier sélectionné : {0}" -f $dialog.SelectedPath)
                }
            } catch {
                Set-MWUiStatus ("Erreur lors de la sélection du dossier : {0}" -f $_.Exception.Message)
            }
        })
    }

    # Handler "Exporter le profil"
    if ($btnExport -and $txtFolderPath) {
        $btnExport.Add_Click({
            try {
                $path = $txtFolderPath.Text.Trim()
                if (-not $path) {
                    Set-MWUiStatus "Merci de sélectionner un dossier avant l'export."
                    return
                }

                Set-MWUiStatus ("Export du profil vers '{0}'..." -f $path)
                Export-MWProfile -DestinationFolder $path
                Set-MWUiStatus "Export du profil terminé."
            } catch {
                Set-MWUiStatus ("Erreur lors de l'export du profil : {0}" -f $_.Exception.Message)
            }
        })
    }

    # Handler "Importer le profil"
    if ($btnImport -and $txtFolderPath) {
        $btnImport.Add_Click({
            try {
                $path = $txtFolderPath.Text.Trim()
                if (-not $path) {
                    Set-MWUiStatus "Merci de sélectionner un dossier avant l'import."
                    return
                }

                if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                    Set-MWUiStatus ("Dossier d'import introuvable : {0}" -f $path)
                    return
                }

                Set-MWUiStatus ("Import du profil depuis '{0}'..." -f $path)
                Import-MWProfile -SourceFolder $path
                Set-MWUiStatus "Import du profil terminé."
            } catch {
                Set-MWUiStatus ("Erreur lors de l'import du profil : {0}" -f $_.Exception.Message)
            }
        })
    }

    # Affichage de la fenêtre
    [void]$window.ShowDialog()
}

Export-ModuleMember -Function Start-MWMigrationWizardUI
