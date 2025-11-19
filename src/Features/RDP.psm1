# src/Features/RDP.psm1

function Export-MWRdpConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les connexions RDP de l'utilisateur.
        .DESCRIPTION
            - Copie le fichier Documents\default.rdp s'il existe
            - Exporte la clé HKCU\Software\Microsoft\Terminal Server Client\Servers
              dans un fichier Servers_HKCU.reg
    #>

    try {
        $base = Join-Path $DestinationFolder 'RDP'
        if (-not (Test-Path -LiteralPath $base)) {
            New-Item -ItemType Directory -Path $base -Force | Out-Null
            Write-MWLogInfo "Dossier d'export RDP créé : $base"
        }

        # 1) default.rdp
        $defRdp = Join-Path $env:USERPROFILE 'Documents\default.rdp'
        if (Test-Path -LiteralPath $defRdp -PathType Leaf) {
            $dstRdp = Join-Path $base 'default.rdp'
            Copy-Item -LiteralPath $defRdp -Destination $dstRdp -Force
            Write-MWLogInfo "Fichier RDP par défaut exporté -> $dstRdp"
        } else {
            Write-MWLogWarning "default.rdp introuvable dans Documents — aucune connexion RDP par défaut à exporter."
        }

        # 2) Clé registre RDP Servers
        $regFile = Join-Path $base 'Servers_HKCU.reg'
        $psKey   = 'HKCU:\Software\Microsoft\Terminal Server Client\Servers'
        $rawKey  = 'HKCU\Software\Microsoft\Terminal Server Client\Servers'

        if (Test-Path -LiteralPath $psKey) {
            try {
                $props = Get-ItemProperty -Path $psKey -ErrorAction SilentlyContinue
                if ($props -and ($props.PSObject.Properties.Count -gt 0)) {
                    & reg.exe export "$rawKey" "$regFile" /y 2>$null | Out-Null
                    Write-MWLogInfo "Clé RDP Servers exportée -> $regFile"
                } else {
                    Write-MWLogInfo "Clé RDP Servers présente mais vide — export ignoré."
                }
            } catch {
                Write-MWLogError "Erreur lors de l'export de la clé RDP Servers : $_"
            }
        } else {
            Write-MWLogInfo "Clé RDP Servers absente — aucune connexion RDP récente à exporter."
        }

        Write-MWLogInfo "Export des connexions RDP terminé."
    } catch {
        Write-MWLogError "Export RDP : $($_.Exception.Message)"
        throw
    }
}

function Import-MWRdpConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe les connexions RDP de l'utilisateur.
        .DESCRIPTION
            - Recopie default.rdp dans Documents
            - Importe Servers_HKCU.reg dans HKCU\Software\Microsoft\Terminal Server Client\Servers
    #>

    try {
        $base = Join-Path $SourceFolder 'RDP'
        if (-not (Test-Path -LiteralPath $base -PathType Container)) {
            Write-MWLogWarning "Dossier RDP absent — rien à restaurer."
            return
        }

        # 1) default.rdp
        $srcRdp = Join-Path $base 'default.rdp'
        if (Test-Path -LiteralPath $srcRdp -PathType Leaf) {
            $dstRdpParent = Join-Path $env:USERPROFILE 'Documents'
            if (-not (Test-Path -LiteralPath $dstRdpParent)) {
                New-Item -ItemType Directory -Path $dstRdpParent -Force | Out-Null
            }
            $dstRdp = Join-Path $dstRdpParent 'default.rdp'
            Copy-Item -LiteralPath $srcRdp -Destination $dstRdp -Force
            Write-MWLogInfo "Fichier RDP par défaut restauré -> $dstRdp"
        } else {
            Write-MWLogInfo "default.rdp non présent dans le dossier RDP — aucune restauration de fichier."
        }

        # 2) Clé registre RDP Servers
        $regFile = Join-Path $base 'Servers_HKCU.reg'
        if (Test-Path -LiteralPath $regFile -PathType Leaf) {
            try {
                & reg.exe import "$regFile" 2>$null | Out-Null
                Write-MWLogInfo "Connexions RDP (Servers_HKCU) importées depuis $regFile."
            } catch {
                Write-MWLogError "Erreur lors de l'import de la clé RDP Servers : $_"
            }
        } else {
            Write-MWLogInfo "Servers_HKCU.reg absent — aucune clé RDP Servers à restaurer."
        }

        Write-MWLogInfo "Import des connexions RDP terminé."
    } catch {
        Write-MWLogError "Import RDP : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWRdpConnections, Import-MWRdpConnections

