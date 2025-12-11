# TaskbarStart.psm1
# Gestion de l'export/import de la barre des tâches et du menu Démarrer Windows

function Export-TaskbarStart {
    <#
    .SYNOPSIS
    Exporte la configuration de la barre des tâches et du menu Démarrer
    
    .PARAMETER OutRoot
    Dossier racine de destination pour l'export
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutRoot
    )
    
    try {
        $ui = Join-Path $OutRoot 'UI'
        New-Item -ItemType Directory -Force -Path $ui | Out-Null
        Write-MWLogInfo "Export Taskbar/Start vers: $ui"
        
        # Export Taskband (épinglements barre des tâches)
        Export-TaskbandRegistry -OutDir $ui
        
        # Export StartLayout (Windows 11)
        Export-StartLayout -OutDir $ui
        
        # Export épingles directes (exploration dossier)
        Export-TaskbarPinned -OutDir $ui
        
        Write-MWLogInfo "Export Taskbar/Start terminé"
    }
    catch {
        Write-MWLogError "Export Taskbar/Start : $($_.Exception.Message)"
    }
}

function Import-TaskbarStart {
    <#
    .SYNOPSIS
    Importe la configuration de la barre des tâches et du menu Démarrer
    
    .PARAMETER InRoot
    Dossier racine source pour l'import
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InRoot
    )
    
    try {
        $ui = Join-Path $InRoot 'UI'
        if (-not (Test-Path $ui)) {
            Write-MWLogWarning "UI absent - rien à restaurer pour Taskbar/Start"
            return
        }
        
        Write-MWLogInfo "Import Taskbar/Start depuis: $ui"
        
        # Import Taskband
        Import-TaskbandRegistry -InDir $ui
        
        # Import StartLayout (best-effort)
        Import-StartLayout -InDir $ui
        
        # Import épingles directes
        Import-TaskbarPinned -InDir $ui
        
        Write-MWLogInfo "Import Taskbar/Start terminé"
    }
    catch {
        Write-MWLogError "Import Taskbar/Start : $($_.Exception.Message)"
    }
}

# ========== Fonctions internes ==========

function Export-TaskbandRegistry {
    param([string]$OutDir)
    
    try {
        $reg = Join-Path $OutDir 'Taskband.reg'
        $taskbandKeyPs  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        $taskbandKeyRaw = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        
        if (Test-Path $taskbandKeyPs) {
            $props = Get-ItemProperty -Path $taskbandKeyPs -ErrorAction SilentlyContinue
            if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
                & reg.exe export $taskbandKeyRaw "$reg" /y 2>$null | Out-Null
                Write-MWLogInfo "Taskband exporté → $reg"
            }
            else {
                Write-MWLogWarning "Taskband présent mais vide - export ignoré"
            }
        }
        else {
            Write-MWLogWarning "Taskband absent - export ignoré"
        }
    }
    catch {
        Write-MWLogError "Taskband export : $($_.Exception.Message)"
    }
}

function Import-TaskbandRegistry {
    param([string]$InDir)
    
    try {
        $reg = Join-Path $InDir 'Taskband.reg'
        if (Test-Path $reg) {
            & reg.exe import "$reg" 2>$null | Out-Null
            Write-MWLogInfo "Taskband importé"
        }
    }
    catch {
        Write-MWLogError "Taskband import : $($_.Exception.Message)"
    }
}

function Export-StartLayout {
    param([string]$OutDir)
    
    try {
        $layout = Join-Path $OutDir 'StartLayout.xml'
        $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $args = "-NoProfile -ExecutionPolicy Bypass -Command `"Export-StartLayout -UseDesktopApplicationID -Path `"$layout`"`""
        
        # Utiliser Run-External si disponible, sinon fallback
        if (Get-Command Run-External -ErrorAction SilentlyContinue) {
            $rc = Run-External -FilePath $cmd -Arguments $args
        }
        else {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $cmd
            $psi.Arguments = $args
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit()
            $rc = $p.ExitCode
        }
        
        if ((Test-Path $layout) -and ($rc -eq 0)) {
            Write-MWLogInfo "StartLayout exporté → $layout"
        }
        else {
            Write-MWLogWarning "StartLayout export: rc=$rc (peut être indisponible selon édition)"
        }
    }
    catch {
        Write-MWLogError "StartLayout export : $($_.Exception.Message)"
    }
}

function Import-StartLayout {
    param([string]$InDir)
    
    try {
        $layout = Join-Path $InDir 'StartLayout.xml'
        if (Test-Path $layout) {
            $cmd = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            $args = "-NoProfile -ExecutionPolicy Bypass -Command `"Import-StartLayout -LayoutPath `"$layout`" -MountPath `"$env:SystemDrive\`"`""
            
            if (Get-Command Run-External -ErrorAction SilentlyContinue) {
                $rc = Run-External -FilePath $cmd -Arguments $args
            }
            else {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $cmd
                $psi.Arguments = $args
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $p = [System.Diagnostics.Process]::Start($psi)
                $p.WaitForExit()
                $rc = $p.ExitCode
            }
            
            Write-MWLogInfo "StartLayout import: rc=$rc (selon édition)"
        }
    }
    catch {
        Write-MWLogError "StartLayout import : $($_.Exception.Message)"
    }
}

function Export-TaskbarPinned {
    param([string]$OutDir)
    
    try {
        $pinsDir = Join-Path $OutDir 'Taskbar_Pinned'
        New-Item -ItemType Directory -Force -Path $pinsDir | Out-Null
        $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        
        if (Test-Path $taskbarPins) {
            Copy-Tree -src $taskbarPins -dst $pinsDir
            Write-MWLogInfo "Taskbar pinned exporté"
        }
    }
    catch {
        Write-MWLogError "Taskbar pinned export : $($_.Exception.Message)"
    }
}

function Import-TaskbarPinned {
    param([string]$InDir)
    
    try {
        $pinsDir = Join-Path $InDir 'Taskbar_Pinned'
        $taskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        
        if (Test-Path $pinsDir) {
            New-Item -ItemType Directory -Force -Path $taskbarPins | Out-Null
            Copy-Tree -src $pinsDir -dst $taskbarPins
            Write-MWLogInfo "Taskbar pinned importé"
        }
    }
    catch {
        Write-MWLogError "Taskbar pinned import : $($_.Exception.Message)"
    }
}

# Helper pour copie robuste (si Copy-Tree pas disponible)
if (-not (Get-Command Copy-Tree -ErrorAction SilentlyContinue)) {
    function Copy-Tree {
        param([string]$src, [string]$dst)
        
        if (-not (Test-Path $src)) {
            Write-MWLogWarning "Source absente: $src"
            return
        }
        
        if (-not (Test-Path $dst)) {
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
        }
        
        $args = "`"$src`" `"$dst`" /E /R:1 /W:1 /MT:16 /COPY:DAT /DCOPY:T /ZB /FFT /NP /NFL /NDL /XJ /SL"
        
        if (Get-Command Run-External -ErrorAction SilentlyContinue) {
            $rc = Run-External -FilePath "robocopy.exe" -Arguments $args
        }
        else {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "robocopy.exe"
            $psi.Arguments = $args
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit()
            $rc = $p.ExitCode
        }
        
        if ($rc -ge 8) {
            Write-MWLogWarning "Copie: code $rc (erreur) $src -> $dst"
        }
        else {
            Write-MWLogInfo "Copie OK: $src -> $dst"
        }
    }
}

Export-ModuleMember -Function Export-TaskbarStart, Import-TaskbarStart

