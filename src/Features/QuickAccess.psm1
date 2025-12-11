# QuickAccess.psm1
# Gestion de l'export/import des dossiers épinglés dans l'accès rapide de l'Explorateur Windows

function Export-MWQuickAccess {
    <#
    .SYNOPSIS
    Exporte les dossiers épinglés dans l'accès rapide de l'Explorateur
    
    .PARAMETER DestinationFolder
    Dossier de destination pour l'export
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestinationFolder
    )
    
    try {
        $base = Join-Path $DestinationFolder 'ExplorerQuickAccess'
        New-Item -ItemType Directory -Force -Path $base | Out-Null
        
        Write-MWLogInfo "Export Accès rapide Explorateur vers: $base"
        
        # Export AutomaticDestinations (jump lists)
        $src1 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
        if (Test-Path $src1) {
            $dst1 = Join-Path $base 'AutomaticDestinations'
            Copy-TreeRobust -Source $src1 -Destination $dst1
            Write-MWLogInfo "AutomaticDestinations exporté"
        }
        
        # Export CustomDestinations (pinned items)
        $src2 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations'
        if (Test-Path $src2) {
            $dst2 = Join-Path $base 'CustomDestinations'
            Copy-TreeRobust -Source $src2 -Destination $dst2
            Write-MWLogInfo "CustomDestinations exporté"
        }
        
        Write-MWLogInfo "Export Accès rapide terminé"
    }
    catch {
        Write-MWLogError "Export QuickAccess : $($_.Exception.Message)"
    }
}

function Import-MWQuickAccess {
    <#
    .SYNOPSIS
    Importe les dossiers épinglés dans l'accès rapide de l'Explorateur
    
    .PARAMETER SourceFolder
    Dossier source contenant l'export
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFolder
    )
    
    try {
        $base = Join-Path $SourceFolder 'ExplorerQuickAccess'
        if (-not (Test-Path $base)) {
            Write-MWLogWarning "ExplorerQuickAccess absent - rien Ã  restaurer"
            return
        }
        
        Write-MWLogInfo "Import Accès rapide Explorateur depuis: $base"
        
        # Import AutomaticDestinations
        $src1 = Join-Path $base 'AutomaticDestinations'
        $dst1 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
        if (Test-Path $src1) {
            New-Item -ItemType Directory -Force -Path $dst1 | Out-Null
            Copy-TreeRobust -Source $src1 -Destination $dst1
            Write-MWLogInfo "AutomaticDestinations importé"
        }
        
        # Import CustomDestinations
        $src2 = Join-Path $base 'CustomDestinations'
        $dst2 = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations'
        if (Test-Path $src2) {
            New-Item -ItemType Directory -Force -Path $dst2 | Out-Null
            Copy-TreeRobust -Source $src2 -Destination $dst2
            Write-MWLogInfo "CustomDestinations importé"
        }
        
        Write-MWLogInfo "Import Accès rapide terminé"
    }
    catch {
        Write-MWLogError "Import QuickAccess : $($_.Exception.Message)"
    }
}

# Helper pour copie robuste
function Copy-TreeRobust {
    param(
        [string]$Source,
        [string]$Destination
    )
    
    if (-not (Test-Path $Source)) {
        Write-MWLogWarning "Source absente: $Source"
        return
    }
    
    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    
    # Utiliser Copy-MWTree si disponible, sinon robocopy direct
    if (Get-Command Copy-MWTree -ErrorAction SilentlyContinue) {
        Copy-MWTree -SourcePath $Source -DestinationPath $Destination
    }
    else {
        $args = "`"$Source`" `"$Destination`" /E /R:1 /W:1 /MT:8 /COPY:DAT /DCOPY:T /ZB /FFT /NP /NFL /NDL /XJ /SL"
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "robocopy.exe"
        $psi.Arguments = $args
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        $rc = $p.ExitCode
        
        if ($rc -ge 8) {
            Write-MWLogWarning "Copie: code $rc pour $Source -> $Destination"
        }
        else {
            Write-MWLogInfo "Copie OK: $Source -> $Destination (rc=$rc)"
        }
    }
}

Export-ModuleMember -Function Export-MWQuickAccess, Import-MWQuickAccess


