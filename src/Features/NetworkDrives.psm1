# src/Features/NetworkDrives.psm1

function Export-MWNetworkDrives {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les lecteurs réseau mappés.
        .DESCRIPTION
            Crée un sous-dossier NetworkDrives et un fichier drives.csv contenant :
              - lettre du lecteur
              - chemin racine (UNC)
              - Used / Free (en Mo)
              - Scope
    #>

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-MWLogInfo "Dossier d'export des lecteurs réseau créé : $DestinationFolder"
        }

        $outFolder = Join-Path $DestinationFolder 'NetworkDrives'
        if (-not (Test-Path -LiteralPath $outFolder)) {
            New-Item -ItemType Directory -Path $outFolder -Force | Out-Null
        }

        # On ne garde que les lecteurs FileSystem avec DisplayRoot (lecteurs mappés)
        $drives = Get-PSDrive | Where-Object {
            $_.Provider -and $_.Provider.Name -eq 'FileSystem' -and $_.DisplayRoot
        }

        $rows = @()
        foreach ($d in $drives) {
            $rows += [pscustomobject]@{
                Name  = $d.Name
                Root  = $d.DisplayRoot
                Used  = [math]::Round(($d.Used / 1MB), 2)
                Free  = [math]::Round(($d.Free / 1MB), 2)
                Scope = $d.Scope
            }
        }

        if (-not $rows -or $rows.Count -eq 0) {
            Write-MWLogWarning "Aucun lecteur réseau mappé à exporter."
            return
        }

        $csvPath = Join-Path $outFolder 'drives.csv'
        $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -UseCulture -Path $csvPath
        Write-MWLogInfo "Lecteurs réseau exportés -> $csvPath"
    } catch {
        Write-MWLogError "Erreur lors de l'export des lecteurs réseau : $_"
        throw
    }
}

function Import-MWNetworkDrives {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe les lecteurs réseau mappés.
        .DESCRIPTION
            Lit NetworkDrives\drives.csv et recrée les lecteurs réseau persistants.
    #>

    try {
        $csvPath = Join-Path (Join-Path $SourceFolder 'NetworkDrives') 'drives.csv'
        if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
            Write-MWLogWarning "NetworkDrives absent — rien à restaurer. Fichier manquant : $csvPath"
            return
        }

        $rows = Import-Csv -Path $csvPath

        foreach ($r in $rows) {
            $name = $r.Name
            $root = $r.Root

            if (-not $name -or -not $root) { continue }

            try {
                if (Get-PSDrive -Name $name -ErrorAction SilentlyContinue) {
                    Write-MWLogInfo "Lecteur $name existe déjà — saut."
                } else {
                    New-PSDrive -Name $name -PSProvider FileSystem -Root $root -Persist -ErrorAction Stop | Out-Null
                    Write-MWLogInfo "Lecteur réseau mappé : $name -> $root"
                }
            } catch {
                Write-MWLogWarning "Erreur lors du mapping du lecteur $name -> $root : $($_.Exception.Message)"
            }
        }
    } catch {
        Write-MWLogError "Erreur lors de l'import des lecteurs réseau : $_"
        throw
    }
}

Export-ModuleMember -Function Export-MWNetworkDrives, Import-MWNetworkDrives

