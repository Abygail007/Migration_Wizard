# ==============================================================================
# TreeBuilder.psm1
# Module de construction et gestion des TreeViews
# ==============================================================================

function New-TreeNode {
    <#
    .SYNOPSIS
    Crée un nouveau nœud de TreeView avec checkbox
    .PARAMETER Path
    Chemin complet du dossier
    .PARAMETER Label
    Libellé à afficher
    .PARAMETER IsChecked
    État initial de la checkbox
    .OUTPUTS
    TreeViewItem configuré
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$Label,
        
        [Parameter(Mandatory=$false)]
        [bool]$IsChecked = $true
    )
    
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $Label
    $chk.IsThreeState = $true
    $chk.IsChecked = $IsChecked
    $chk.Tag = [pscustomobject]@{ Path = $Path; Item = $null }
    
    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Header = $chk
    $item.Items.Add("*") | Out-Null
    
    $chk.Tag.Item = $item
    
    # Événements
    $item.Add_Expanded({ 
        param($s, $e)
        Expand-TreeNode $s 
    })
    
    $chk.Add_Checked({ 
        param($s, $e)
        Update-TreeNodeState $s 
    })
    $chk.Add_Unchecked({ 
        param($s, $e)
        Update-TreeNodeState $s 
    })
    
    return $item
}

function Expand-TreeNode {
    <#
    .SYNOPSIS
    Expand un nœud et charge ses enfants
    .PARAMETER Item
    TreeViewItem à expand
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Item
    )
    
    if ($Item.Items.Count -eq 1 -and $Item.Items[0] -is [string]) {
        $Item.Items.Clear()
        
        $chk = $Item.Header
        $path = $chk.Tag.Path
        
        try {
            $dirs = Get-ChildItem -Path $path -Directory -ErrorAction Stop
            
            foreach ($dir in $dirs) {
                $childNode = New-TreeNode -Path $dir.FullName -Label $dir.Name -IsChecked $chk.IsChecked
                $Item.Items.Add($childNode) | Out-Null
            }
        }
        catch {
            Write-MWLogWarning "Expand-TreeNode : impossible de lire '$path' : $($_.Exception.Message)"
        }
    }
}

function Update-TreeNodeState {
    <#
    .SYNOPSIS
    Met à jour l'état du nœud et propage aux parents/enfants
    .PARAMETER CheckBox
    CheckBox modifiée
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $CheckBox
    )
    
    $item = $CheckBox.Tag.Item
    
    # Propager aux enfants
    Set-ChildrenCheckState -Item $item -State $CheckBox.IsChecked
    
    # Mettre à jour les parents
    Update-ParentCheckState -Item $item
}

function Set-ChildrenCheckState {
    <#
    .SYNOPSIS
    Définit l'état de tous les enfants
    .PARAMETER Item
    TreeViewItem parent
    .PARAMETER State
    État à appliquer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Item,
        
        [Parameter(Mandatory=$false)]
        $State
    )
    
    foreach ($child in $Item.Items) {
        if ($child -is [System.Windows.Controls.TreeViewItem]) {
            $childChk = $child.Header
            if ($childChk -is [System.Windows.Controls.CheckBox]) {
                $childChk.IsChecked = $State
                Set-ChildrenCheckState -Item $child -State $State
            }
        }
    }
}

function Update-ParentCheckState {
    <#
    .SYNOPSIS
    Met à jour l'état du parent selon ses enfants
    .PARAMETER Item
    TreeViewItem dont le parent doit être mis à jour
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Item
    )
    
    $parent = $Item.Parent
    
    while ($parent -is [System.Windows.Controls.TreeViewItem]) {
        $parentChk = $parent.Header
        
        if ($parentChk -is [System.Windows.Controls.CheckBox]) {
            $checkedCount = 0
            $uncheckedCount = 0
            $totalCount = 0
            
            foreach ($child in $parent.Items) {
                if ($child -is [System.Windows.Controls.TreeViewItem]) {
                    $childChk = $child.Header
                    if ($childChk -is [System.Windows.Controls.CheckBox]) {
                        $totalCount++
                        if ($childChk.IsChecked -eq $true) {
                            $checkedCount++
                        }
                        elseif ($childChk.IsChecked -eq $false) {
                            $uncheckedCount++
                        }
                    }
                }
            }
            
            if ($checkedCount -eq $totalCount) {
                $parentChk.IsChecked = $true
            }
            elseif ($uncheckedCount -eq $totalCount) {
                $parentChk.IsChecked = $false
            }
            else {
                $parentChk.IsChecked = $null
            }
        }
        
        $parent = $parent.Parent
    }
}

function Build-FoldersTree {
    <#
    .SYNOPSIS
    Construit l'arbre des dossiers standards
    .PARAMETER TreeView
    Contrôle TreeView à peupler
    .PARAMETER IsExport
    True si mode Export, False si Import
    .PARAMETER ImportFolder
    Dossier d'export source (pour mode Import uniquement)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView,

        [Parameter(Mandatory=$true)]
        [bool]$IsExport,

        [Parameter(Mandatory=$false)]
        [string]$ImportFolder = $null
    )

    $TreeView.Items.Clear()

    $defaultChecked = $IsExport

    # FIX: En mode Import, lister SEULEMENT les dossiers exportés
    if (-not $IsExport -and $ImportFolder -and (Test-Path $ImportFolder)) {
        $profilePath = Join-Path $ImportFolder 'Profile'

        if (Test-Path $profilePath) {
            Write-MWLogInfo "Mode Import : scan des dossiers exportés dans '$profilePath'"

            # Scanner les dossiers qui existent réellement dans l'export
            $exportedFolders = Get-ChildItem -Path $profilePath -Directory -ErrorAction SilentlyContinue

            foreach ($folder in $exportedFolders) {
                $folderName = $folder.Name

                # Gérer le cas spécial Public\
                if ($folderName -eq 'Public') {
                    $publicSubFolders = Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue
                    foreach ($pubFolder in $publicSubFolders) {
                        $label = "Public\$($pubFolder.Name)"
                        $destPath = "C:\Users\Public\$($pubFolder.Name)"
                        $node = New-TreeNode -Path $destPath -Label $label -IsChecked $true
                        $TreeView.Items.Add($node) | Out-Null
                        Write-MWLogInfo "Dossier exporté détecté : $label"
                    }
                } else {
                    # Dossier standard
                    $destPath = Join-Path $env:USERPROFILE $folderName
                    $node = New-TreeNode -Path $destPath -Label $folderName -IsChecked $true
                    $TreeView.Items.Add($node) | Out-Null
                    Write-MWLogInfo "Dossier exporté détecté : $folderName"
                }
            }

            Write-MWLogInfo "Arbre Import construit - $($exportedFolders.Count) dossier(s) exporté(s)"
            return
        }
    }

    # Mode Export classique : lister tous les dossiers standards
    $roots = @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'Favorites')

    foreach ($folder in $roots) {
        $path = Join-Path $env:USERPROFILE $folder
        if (Test-Path $path) {
            $node = New-TreeNode -Path $path -Label $folder -IsChecked $defaultChecked
            $TreeView.Items.Add($node) | Out-Null
        }
    }

    # Bureau public
    $pubDesk = 'C:\Users\Public\Desktop'
    if (Test-Path $pubDesk) {
        $node = New-TreeNode -Path $pubDesk -Label 'Public\Desktop' -IsChecked $defaultChecked
        $TreeView.Items.Add($node) | Out-Null
    }

    Write-MWLogInfo "Arbre des dossiers construit (mode Export)"
}

function Build-AppDataTree {
    <#
    .SYNOPSIS
    Construit l'arbre AppData (section séparée)
    .PARAMETER TreeView
    Contrôle TreeView AppData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView
    )
    
    $TreeView.Items.Clear()
    
    # AppData\Local
    $localPath = Join-Path $env:USERPROFILE 'AppData\Local'
    if (Test-Path $localPath) {
        $nodeLocal = New-TreeNode -Path $localPath -Label 'AppData\Local' -IsChecked $false
        $TreeView.Items.Add($nodeLocal) | Out-Null
    }
    
    # AppData\Roaming
    $roamingPath = Join-Path $env:USERPROFILE 'AppData\Roaming'
    if (Test-Path $roamingPath) {
        $nodeRoaming = New-TreeNode -Path $roamingPath -Label 'AppData\Roaming' -IsChecked $false
        $TreeView.Items.Add($nodeRoaming) | Out-Null
    }
    
    Write-MWLogInfo "Arbre AppData construit"
}

function Get-SelectedFolders {
    <#
    .SYNOPSIS
    Récupère tous les dossiers cochés dans le TreeView
    .PARAMETER TreeView
    Contrôle TreeView à analyser
    .OUTPUTS
    Liste des chemins sélectionnés
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView
    )
    
    $selected = @()
    
    function Get-CheckedPaths {
        param($Items)
        
        foreach ($item in $Items) {
            if ($item -is [System.Windows.Controls.TreeViewItem]) {
                $chk = $item.Header
                if ($chk -is [System.Windows.Controls.CheckBox] -and $chk.IsChecked -eq $true) {
                    $path = $chk.Tag.Path
                    if ($path) {
                        $selected += $path
                    }
                }
                
                # Récursif pour les enfants
                if ($item.Items.Count -gt 0) {
                    Get-CheckedPaths -Items $item.Items
                }
            }
        }
    }
    
    Get-CheckedPaths -Items $TreeView.Items
    
    return $selected
}

function Get-AppDataSelection {
    <#
    .SYNOPSIS
    Récupère l'état des checkboxes AppData
    .PARAMETER TreeView
    TreeView AppData
    .OUTPUTS
    Hashtable avec Local et Roaming
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TreeView
    )
    
    $result = @{
        Local = $false
        Roaming = $false
    }
    
    foreach ($item in $TreeView.Items) {
        if ($item -is [System.Windows.Controls.TreeViewItem]) {
            $chk = $item.Header
            if ($chk -is [System.Windows.Controls.CheckBox]) {
                $label = $chk.Content
                if ($label -like '*Local*') {
                    $result.Local = [bool]$chk.IsChecked
                }
                elseif ($label -like '*Roaming*') {
                    $result.Roaming = [bool]$chk.IsChecked
                }
            }
        }
    }
    
    return $result
}

# Export des fonctions
Export-ModuleMember -Function @(
    'New-TreeNode',
    'Expand-TreeNode',
    'Update-TreeNodeState',
    'Set-ChildrenCheckState',
    'Update-ParentCheckState',
    'Build-FoldersTree',
    'Build-AppDataTree',
    'Get-SelectedFolders',
    'Get-AppDataSelection'
)
