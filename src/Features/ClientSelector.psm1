# ==============================================================================
# ClientSelector.psm1
# Module de sélection de clients pour l'import
# ==============================================================================

function Scan-ClientFolders {
    <#
    .SYNOPSIS
    Scanne un dossier pour détecter les exports clients valides (structure Client/PC)
    .PARAMETER BasePath
    Chemin du dossier contenant les exports (ex: C:\MigrationWizard\Exports)
    .OUTPUTS
    Liste d'objets avec FolderPath, FolderName, Metadata
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BasePath
    )

    if (-not (Test-Path $BasePath)) {
        Write-MWLogWarning "Scan-ClientFolders : Chemin inexistant : $BasePath"
        return @()
    }

    $clients = @()

    # Scanner tous les sous-dossiers (niveau Client)
    Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
        $clientFolder = $_

        # Scanner les sous-dossiers PC dans chaque dossier client
        Get-ChildItem -Path $clientFolder.FullName -Directory | ForEach-Object {
            $pcFolder = $_
            $manifestPath = Join-Path $pcFolder.FullName "ExportManifest.json"

            # Vérifier présence du manifest dans le dossier PC
            if (Test-Path $manifestPath) {
                try {
                    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                    $metadata = $manifest.ExportMetadata

                    $clients += [PSCustomObject]@{
                        FolderPath = $pcFolder.FullName
                        FolderName = $pcFolder.Name
                        ClientName = $clientFolder.Name
                        ComputerName = $metadata.ComputerName
                        UserName = $metadata.UserName
                        Date = [DateTime]::Parse($metadata.Date)
                        DisplayInfo = "$($clientFolder.Name) > $($metadata.ComputerName) - $($metadata.UserName) ($($metadata.Date))"
                        Manifest = $manifest
                    }

                    Write-MWLogInfo "Export détecté : $($clientFolder.Name)\$($pcFolder.Name)"
                }
                catch {
                    Write-MWLogWarning "Manifest invalide dans $($clientFolder.Name)\$($pcFolder.Name) : $($_.Exception.Message)"
                }
            }
        }

        # Fallback : si le dossier client contient directement un manifest (ancienne structure)
        $directManifestPath = Join-Path $clientFolder.FullName "ExportManifest.json"
        if (Test-Path $directManifestPath) {
            try {
                $manifest = Get-Content $directManifestPath -Raw | ConvertFrom-Json
                $metadata = $manifest.ExportMetadata

                $clients += [PSCustomObject]@{
                    FolderPath = $clientFolder.FullName
                    FolderName = $clientFolder.Name
                    ClientName = $clientFolder.Name
                    ComputerName = $metadata.ComputerName
                    UserName = $metadata.UserName
                    Date = [DateTime]::Parse($metadata.Date)
                    DisplayInfo = "$($metadata.UserName)@$($metadata.ComputerName) - $($metadata.Date)"
                    Manifest = $manifest
                }

                Write-MWLogInfo "Export détecté (ancienne structure) : $($clientFolder.Name)"
            }
            catch {
                Write-MWLogWarning "Manifest invalide dans $($clientFolder.Name) : $($_.Exception.Message)"
            }
        }
    }

    # Trier par date décroissante (plus récent en premier)
    $clients = @($clients | Sort-Object -Property Date -Descending)

    Write-MWLogInfo "Scan terminé : $($clients.Count) export(s) trouvé(s)"

    return ,$clients
}

function Get-ClientMetadata {
    <#
    .SYNOPSIS
    Lit les métadonnées d'un client depuis son manifest
    .PARAMETER ClientFolder
    Chemin du dossier client
    .OUTPUTS
    Objet avec métadonnées ou $null si invalide
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ClientFolder
    )
    
    $manifestPath = Join-Path $ClientFolder "ExportManifest.json"
    
    if (-not (Test-Path $manifestPath)) {
        Write-MWLogWarning "ExportManifest.json introuvable dans : $ClientFolder"
        return $null
    }
    
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        
        return [PSCustomObject]@{
            ComputerName = $manifest.ExportMetadata.ComputerName
            UserName = $manifest.ExportMetadata.UserName
            Domain = $manifest.ExportMetadata.Domain
            Date = $manifest.ExportMetadata.Date
            OsVersion = $manifest.ExportMetadata.OsVersion
            ExportedItems = $manifest.ExportedItems
        }
    }
    catch {
        Write-MWLogError "Erreur lecture manifest : $($_.Exception.Message)"
        return $null
    }
}

function Show-ClientSelectorDialog {
    <#
    .SYNOPSIS
    Affiche une fenêtre de sélection de client (fallback simple)
    .PARAMETER Clients
    Liste des clients disponibles
    .OUTPUTS
    Chemin du dossier client sélectionné ou $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Clients
    )
    
    if ($Clients.Count -eq 0) {
        Write-MWLogInfo "Aucun client détecté, ouverture dialogue manuel"
        return $null
    }
    
    # Si un seul client, retourner directement
    if ($Clients.Count -eq 1) {
        Write-MWLogInfo "Un seul client détecté : $($Clients[0].FolderName)"
        return $Clients[0].FolderPath
    }
    
    # Sinon afficher Out-GridView (fallback)
    Write-MWLogInfo "Plusieurs clients détectés, affichage sélection"
    
    $selected = $Clients | Out-GridView -Title "Sélectionner un client à importer" -OutputMode Single
    
    if ($selected) {
        Write-MWLogInfo "Client sélectionné : $($selected.FolderName)"
        return $selected.FolderPath
    }
    
    return $null
}

function Select-ClientFolder {
    <#
    .SYNOPSIS
    Workflow complet de sélection de client
    .PARAMETER DefaultPath
    Chemin par défaut où chercher les clients
    .PARAMETER AllowManual
    Permet sélection manuelle si aucun client trouvé
    .OUTPUTS
    Chemin du dossier client sélectionné
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DefaultPath = "C:\MigrationWizard\Exports",
        
        [Parameter(Mandatory=$false)]
        [bool]$AllowManual = $true
    )
    
    Write-MWLogInfo "=== Sélection client pour import ==="
    
    # Scanner les clients disponibles
    $clients = Scan-ClientFolders -BasePath $DefaultPath
    
    # Si clients trouvés
    if ($clients.Count -gt 0) {
        $selected = Show-ClientSelectorDialog -Clients $clients
        
        if ($selected) {
            return $selected
        }
    }
    
    # Si aucun client ou sélection annulée
    if ($AllowManual) {
        Write-MWLogInfo "Ouverture dialogue sélection manuelle"
        
        Add-Type -AssemblyName System.Windows.Forms
        $browser = New-Object System.Windows.Forms.FolderBrowserDialog
        $browser.Description = "Sélectionner le dossier client à importer"
        $browser.SelectedPath = $DefaultPath
        
        if ($browser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folder = $browser.SelectedPath
            
            # Valider présence manifest
            $manifest = Get-ClientMetadata -ClientFolder $folder
            
            if ($manifest) {
                Write-MWLogInfo "Client valide sélectionné : $folder"
                return $folder
            }
            else {
                Write-MWLogWarning "Dossier invalide (pas de manifest) : $folder"
                [System.Windows.MessageBox]::Show(
                    "Ce dossier ne contient pas d'export valide (ExportManifest.json manquant).",
                    "Export invalide",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                
                return $null
            }
        }
    }
    
    Write-MWLogInfo "Aucun client sélectionné"
    return $null
}

# Export des fonctions
Export-ModuleMember -Function @(
    'Scan-ClientFolders',
    'Get-ClientMetadata',
    'Show-ClientSelectorDialog',
    'Select-ClientFolder'
)
