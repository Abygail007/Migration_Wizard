# src/UI/MigrationWizard.UI.psm1

function Start-MigrationWizard {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
    } catch {
        Write-MWLogError ("Erreur chargement assemblies WPF/WinForms : {0}" -f $_.Exception.Message)
        return
    }

    $xamlPath = Join-Path $PSScriptRoot 'MigrationWizard.xaml'

    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) {
        Write-MWLogError ("Fichier XAML introuvable : {0}" -f $xamlPath)
        [System.Windows.MessageBox]::Show(
            "Fichier UI introuvable :`n`n$xamlPath",
            "MigrationWizard",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return
    }

    try {
        $xamlContent = Get-Content -LiteralPath $xamlPath -Raw
        $stringReader = New-Object System.IO.StringReader($xamlContent)
        $xmlReader    = [System.Xml.XmlReader]::Create($stringReader)
        $window       = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    } catch {
        Write-MWLogError ("Erreur chargement XAML : {0}" -f $_.Exception.Message)
        [System.Windows.MessageBox]::Show(
            "Erreur lors du chargement de la fenêtre UI :`n`n$($_.Exception.Message)",
            "MigrationWizard",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return
    }

    # Récupération des contrôles
    $tbProfileFolder   = $window.FindName('tbProfileFolder')
    $btnBrowse         = $window.FindName('btnBrowse')
    $btnExportProfile  = $window.FindName('btnExportProfile')
    $btnImportProfile  = $window.FindName('btnImportProfile')
    $lblStatus         = $window.FindName('lblStatus')

    $cbAll             = $window.FindName('cbAll')
    $cbUserData        = $window.FindName('cbUserData')
    $cbUseDataFolders  = $window.FindName('cbUseDataFoldersManifest')
    $cbWifi            = $window.FindName('cbWifi')
    $cbPrinters        = $window.FindName('cbPrinters')
    $cbNetworkDrives   = $window.FindName('cbNetworkDrives')
    $cbRdp             = $window.FindName('cbRdp')
    $cbBrowsers        = $window.FindName('cbBrowsers')
    $cbOutlook         = $window.FindName('cbOutlook')
    $cbWallpaper       = $window.FindName('cbWallpaper')
    $cbDesktopLayout   = $window.FindName('cbDesktopLayout')
    $cbTaskbarStart    = $window.FindName('cbTaskbarStart')

    $checkboxes = @(
        $cbUserData,
        $cbUseDataFolders,
        $cbWifi,
        $cbPrinters,
        $cbNetworkDrives,
        $cbRdp,
        $cbBrowsers,
        $cbOutlook,
        $cbWallpaper,
        $cbDesktopLayout,
        $cbTaskbarStart,
        $cbAll
    ) | Where-Object { $_ -ne $null }


    # Par défaut, tout coché
    foreach ($cb in $checkboxes) {
        if ($cb -ne $cbAll) {
            $cb.IsChecked = $true
        }
    }
    if ($cbAll) { $cbAll.IsChecked = $true }

    # Gestion "Tout cocher / décocher"
    $updateAll = {
        param($sender, $e)
        if (-not $cbAll) { return }
        $value = $cbAll.IsChecked
        foreach ($cb in $checkboxes) {
            if (($cb -ne $null) -and ($cb -ne $cbAll)) {
                $cb.IsChecked = $value
            }
        }
    }

    if ($cbAll) {
        $null = $cbAll.Add_Checked($updateAll)
        $null = $cbAll.Add_Unchecked($updateAll)
    }

    # Synchroniser cbAll quand on change individuellement
    $syncAll = {
        param($sender, $e)
        if (-not $cbAll) { return }

        $allTrue = $true
        foreach ($cb in $checkboxes) {
            if (($cb -ne $null) -and ($cb -ne $cbAll)) {
                if (-not $cb.IsChecked) {
                    $allTrue = $false
                    break
                }
            }
        }
        $cbAll.IsChecked = $allTrue
    }

    foreach ($cb in $checkboxes) {
        if (($cb -ne $null) -and ($cb -ne $cbAll)) {
            $null = $cb.Add_Checked($syncAll)
            $null = $cb.Add_Unchecked($syncAll)
        }
    }

    # Helper pour construire les paramètres d'Export/Import
    $buildProfileParams = {
        param([string]$path)
        @{
            IncludeUserData        = [bool]($cbUserData       -and $cbUserData.IsChecked)
            UseDataFoldersManifest = [bool]($cbUseDataFolders -and $cbUseDataFolders.IsChecked)

            IncludeWifi            = [bool]($cbWifi           -and $cbWifi.IsChecked)
            IncludePrinters        = [bool]($cbPrinters       -and $cbPrinters.IsChecked)
            IncludeNetworkDrives   = [bool]($cbNetworkDrives  -and $cbNetworkDrives.IsChecked)
            IncludeRdp             = [bool]($cbRdp            -and $cbRdp.IsChecked)
            IncludeBrowsers        = [bool]($cbBrowsers       -and $cbBrowsers.IsChecked)
            IncludeOutlook         = [bool]($cbOutlook        -and $cbOutlook.IsChecked)
            IncludeWallpaper       = [bool]($cbWallpaper      -and $cbWallpaper.IsChecked)
            IncludeDesktopLayout   = [bool]($cbDesktopLayout  -and $cbDesktopLayout.IsChecked)
            IncludeTaskbarStart    = [bool]($cbTaskbarStart   -and $cbTaskbarStart.IsChecked)
        }
    }

    # Bouton Parcourir
    if ($btnBrowse) {
        $null = $btnBrowse.Add_Click({
            param($s,$e)
            try {
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = "Choisir le dossier d'export / import du profil"
                $dlg.ShowNewFolderButton = $true

                $initial = $tbProfileFolder.Text
                if ([string]::IsNullOrWhiteSpace($initial)) {
                    $initial = [System.Environment]::GetFolderPath(
                        [System.Environment+SpecialFolder]::Desktop
                    )
                }
                $dlg.SelectedPath = $initial

                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $tbProfileFolder.Text = $dlg.SelectedPath
                }
            } catch {
                Write-MWLogError ("Erreur UI - Parcourir : {0}" -f $_.Exception.Message)
            }
        })
    }

    # Bouton Export
    if ($btnExportProfile) {
        $null = $btnExportProfile.Add_Click({
            param($s,$e)
            try {
                $path = $tbProfileFolder.Text
                if ([string]::IsNullOrWhiteSpace($path)) {
                    [System.Windows.MessageBox]::Show(
                        "Veuillez choisir un dossier pour l'export.",
                        "MigrationWizard",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    return
                }

                if ($lblStatus) { $lblStatus.Text = "Export en cours..." }

                [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                try {
                    $params = & $buildProfileParams -path $path
                    $params.DestinationFolder = $path
                    Export-MWProfile @params
                    if ($lblStatus) { $lblStatus.Text = "Export terminé." }
                } finally {
                    [System.Windows.Input.Mouse]::OverrideCursor = $null
                }
            } catch {
                if ($lblStatus) { $lblStatus.Text = "Erreur pendant l'export." }
                Write-MWLogError ("Erreur UI - Export : {0}" -f $_.Exception.Message)
                [System.Windows.MessageBox]::Show(
                    "Erreur pendant l'export :`n`n$($_.Exception.Message)",
                    "MigrationWizard",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
        })
    }

    # Bouton Import
    if ($btnImportProfile) {
        $null = $btnImportProfile.Add_Click({
            param($s,$e)
            try {
                $path = $tbProfileFolder.Text
                if ([string]::IsNullOrWhiteSpace($path)) {
                    [System.Windows.MessageBox]::Show(
                        "Veuillez choisir un dossier pour l'import.",
                        "MigrationWizard",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Warning
                    ) | Out-Null
                    return
                }

                if ($lblStatus) { $lblStatus.Text = "Import en cours..." }

                [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                try {
                    $params = & $buildProfileParams -path $path
                    $params.SourceFolder = $path
                    Import-MWProfile @params
                    if ($lblStatus) { $lblStatus.Text = "Import terminé." }
                } finally {
                    [System.Windows.Input.Mouse]::OverrideCursor = $null
                }
            } catch {
                if ($lblStatus) { $lblStatus.Text = "Erreur pendant l'import." }
                Write-MWLogError ("Erreur UI - Import : {0}" -f $_.Exception.Message)
                [System.Windows.MessageBox]::Show(
                    "Erreur pendant l'import :`n`n$($_.Exception.Message)",
                    "MigrationWizard",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
        })
    }

    Write-MWLogInfo "Lancement de l'UI principale MigrationWizard."
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Start-MigrationWizard
