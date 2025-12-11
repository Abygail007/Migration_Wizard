# ==============================================================================
# UINavigation.psm1
# Module de navigation entre pages
# ==============================================================================

$script:CurrentPage = 1

function Show-UIPage {
    <#
    .SYNOPSIS
    Affiche une page et masque les autres
    .PARAMETER PageNumber
    Numéro de la page à afficher
    .PARAMETER Window
    Fenêtre contenant les pages
    .PARAMETER IsExport
    Mode Export (true) ou Import (false) - obligatoire pour page 3
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$PageNumber,
        
        [Parameter(Mandatory=$true)]
        $Window,
        
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [Nullable[bool]]$IsExport = $null
    )
    
    $script:CurrentPage = $PageNumber
    
    # Masquer toutes les pages
    $pages = @('page1', 'page2', 'page21', 'page3', 'page4', 'page5', 'pagePasswords', 'pageApps')
    
    foreach ($pageName in $pages) {
        $page = $Window.FindName($pageName)
        if ($page) {
            $page.Visibility = 'Collapsed'
        }
    }
    
    # Afficher la page demandée
    $pageToShow = switch ($PageNumber) {
        1  { 'page1' }
        2  { 'page2' }
        21 { 'page21' }
        3  { 'page3' }
        4  { 'page4' }
        5  { 'page5' }
        20 { 'pagePasswords' }
        22 { 'pageApps' }
        default { 'page1' }
    }
    
    $page = $Window.FindName($pageToShow)
    if ($page) {
        $page.Visibility = 'Visible'
        Write-MWLogInfo "Page $PageNumber affichée"
    }
    
    # CORRECTION: Gérer visibilité panelExport/panelImport sur page 3
    if ($PageNumber -eq 3 -and $IsExport -ne $null) {
        $panelExport = $Window.FindName('panelExport')
        $panelImport = $Window.FindName('panelImport')
        
        if ($IsExport) {
            # Mode EXPORT
            if ($panelExport) { $panelExport.Visibility = 'Visible' }
            if ($panelImport) { $panelImport.Visibility = 'Collapsed' }
            Write-MWLogInfo "Mode EXPORT - panelExport rendu visible"
        }
        else {
            # Mode IMPORT
            if ($panelExport) { $panelExport.Visibility = 'Collapsed' }
            if ($panelImport) { $panelImport.Visibility = 'Visible' }
            Write-MWLogInfo "Mode IMPORT - panelImport rendu visible"
        }
    }
    
    # Gérer visibilité boutons
    Update-NavigationButtons -Window $Window
}

function Update-NavigationButtons {
    <#
    .SYNOPSIS
    Met à jour la visibilité des boutons de navigation
    .PARAMETER Window
    Fenêtre contenant les boutons
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Window
    )
    
    $btnPrev = $Window.FindName('btnPrev')
    $btnNext = $Window.FindName('btnNext')
    $btnRun = $Window.FindName('btnRun')
    
    if (-not $btnPrev -or -not $btnNext -or -not $btnRun) {
        return
    }
    
    # Récupérer btnClose
    $btnClose = $Window.FindName('btnClose')

    # Récupérer IsExport depuis script scope pour logique conditionnelle
    $isExportMode = if ($null -ne $script:IsExport) { $script:IsExport } else { $true }

    switch ($script:CurrentPage) {
        1 {
            $btnPrev.Visibility = 'Collapsed'
            $btnNext.Visibility = 'Visible'
            $btnRun.Visibility = 'Collapsed'
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
        }
        {$_ -in @(2, 21, 22)} {
            $btnPrev.Visibility = 'Visible'
            $btnNext.Visibility = 'Visible'
            $btnRun.Visibility = 'Collapsed'
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
        }
        20 {
            # Page passwords: comportement différent selon mode
            # Export: prev/next visible (navigation normale)
            # Import: seulement next vers page terminée
            if ($isExportMode) {
                $btnPrev.Visibility = 'Visible'
                $btnNext.Visibility = 'Visible'
            } else {
                $btnPrev.Visibility = 'Collapsed'
                $btnNext.Visibility = 'Visible'
            }
            $btnRun.Visibility = 'Collapsed'
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
        }
        3 {
            $btnPrev.Visibility = 'Visible'
            $btnNext.Visibility = 'Collapsed'
            $btnRun.Visibility = 'Visible'
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
        }
        4 {
            # Page d'exécution
            $btnPrev.Visibility = 'Collapsed'
            $btnNext.Visibility = 'Collapsed'
            $btnRun.Visibility = 'Collapsed'
            if ($btnClose) { $btnClose.Visibility = 'Collapsed' }
        }
        5 {
            # Page terminée : afficher bouton Terminer
            $btnPrev.Visibility = 'Collapsed'
            $btnNext.Visibility = 'Collapsed'
            $btnRun.Visibility = 'Collapsed'
            if ($btnClose) { $btnClose.Visibility = 'Visible' }
        }
    }
}

function Navigate-Next {
    <#
    .SYNOPSIS
    Navigation vers la page suivante avec logique métier
    .PARAMETER Window
    Fenêtre principale
    .PARAMETER IsExport
    Mode Export ou Import
    .PARAMETER OnNavigateCallback
    Callback à exécuter lors de la navigation
    .OUTPUTS
    Numéro de la page suivante ou -1 si bloqué
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Window,
        
        [Parameter(Mandatory=$true)]
        [bool]$IsExport,
        
        [Parameter(Mandatory=$false)]
        [scriptblock]$OnNavigateCallback
    )
    
    $nextPage = -1
    
    switch ($script:CurrentPage) {
        1 {
            # Page 1 → Page 2 (Export) ou Page 21 (Import: sélection client)
            if ($IsExport) {
                $nextPage = 2
            }
            else {
                $nextPage = 21  # Sélection client
            }
        }
        21 {
            # Page 21 (sélection client) → Page 22 (Apps à réinstaller)
            $nextPage = 22
        }
        22 {
            # Page 22 (Apps) → Page 2 (données/options)
            $nextPage = 2
        }
        2 {
            # Page 2 → Page 20 (passwords) SEULEMENT pour Export, sinon résumé
            if ($IsExport) {
                $nextPage = 20
            } else {
                $nextPage = 3  # Import: aller directement au résumé
            }
        }
        20 {
            # Page passwords → Page 3 (résumé) pour Export
            # Pour Import: → Page 5 (terminée) car on vient de l'exécution
            if ($IsExport) {
                $nextPage = 3
            } else {
                $nextPage = 5  # Import: passwords → terminée
            }
        }
        3 {
            # Page 3 → Pas de suivant (c'est le résumé)
            $nextPage = -1
        }
    }
    
    if ($nextPage -gt 0) {
        # Exécuter callback si présent
        if ($OnNavigateCallback) {
            $result = & $OnNavigateCallback -FromPage $script:CurrentPage -ToPage $nextPage
            if ($result -eq $false) {
                # Callback a bloqué la navigation
                return -1
            }
        }
        
        Show-UIPage -PageNumber $nextPage -Window $Window -IsExport $IsExport
        return $nextPage
    }
    
    return -1
}

function Navigate-Previous {
    <#
    .SYNOPSIS
    Navigation vers la page précédente
    .PARAMETER Window
    Fenêtre principale
    .PARAMETER IsExport
    Mode Export ou Import
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Window,
        
        [Parameter(Mandatory=$true)]
        [bool]$IsExport
    )
    
    $prevPage = -1
    
    switch ($script:CurrentPage) {
        20 {
            # Passwords → Page 2
            $prevPage = 2
        }
        3 {
            # Résumé → Page 20 (passwords) pour Export, Page 2 pour Import
            if ($IsExport) {
                $prevPage = 20
            } else {
                $prevPage = 2  # Import: retour aux options
            }
        }
        4 {
            # Exécution → Page 3
            $prevPage = 3
        }
        2 {
            # Page 2 → Page 1 (export) ou Page 22 Apps (import)
            if ($IsExport) {
                $prevPage = 1
            }
            else {
                $prevPage = 22
            }
        }
        22 {
            # Apps → Sélection client
            $prevPage = 21
        }
        21 {
            # Sélection client → Page 1
            $prevPage = 1
        }
    }
    
    if ($prevPage -gt 0) {
        Show-UIPage -PageNumber $prevPage -Window $Window -IsExport $IsExport
        return $prevPage
    }
    
    return -1
}

function Get-CurrentPage {
    <#
    .SYNOPSIS
    Retourne le numéro de la page actuelle
    .OUTPUTS
    Numéro de page
    #>
    return $script:CurrentPage
}

# Export des fonctions
Export-ModuleMember -Function @(
    'Show-UIPage',
    'Update-NavigationButtons',
    'Navigate-Next',
    'Navigate-Previous',
    'Get-CurrentPage'
)
