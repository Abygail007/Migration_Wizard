# src/Features/Printers.psm1

function Export-MWPrinters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte la configuration des imprimantes.
        .DESCRIPTION
            Produit :
              - Printers_List.json : liste des imprimantes (nom, driver, port, etc.)
              - DefaultPrinter.txt : nom de l'imprimante par dÃ©faut
              - Ports.json         : listes des ports TCP/IP
    #>

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-MWLogInfo "Dossier d'export imprimantes crÃ©Ã© : $DestinationFolder"
        } catch {
            Write-MWLogError "Impossible de crÃ©er le dossier d'export imprimantes '$DestinationFolder' : $_"
            throw
        }
    }

    # Export de la liste des imprimantes
    if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
        try {
            $plist = Get-Printer | Select-Object `
                Name,
                DriverName,
                PortName,
                Shared,
                Published,
                Type,
                Location,
                Comment,
                @{Name='IsDefault';Expression={ $_.Default }}

            $printersJsonPath = Join-Path $DestinationFolder 'Printers_List.json'
            $plist | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $printersJsonPath -Encoding UTF8
            Write-MWLogInfo "Liste imprimantes exportÃ©e -> $printersJsonPath"

            $def = ($plist | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1).Name
            if ($def) {
                $defPath = Join-Path $DestinationFolder 'DefaultPrinter.txt'
                $def | Set-Content -LiteralPath $defPath -Encoding UTF8
                Write-MWLogInfo "Imprimante par dÃ©faut exportÃ©e : $def"
            } else {
                Write-MWLogWarning "Aucune imprimante par dÃ©faut dÃ©tectÃ©e."
            }
        } catch {
            Write-MWLogError "Erreur lors de l'export de la liste des imprimantes : $_"
        }
    } else {
        Write-MWLogWarning "Cmdlet Get-Printer introuvable. Impossible d'exporter la liste des imprimantes."
    }

    # Export des ports TCP/IP
    if (Get-Command Get-PrinterPort -ErrorAction SilentlyContinue) {
        try {
            $ports = Get-PrinterPort | Select-Object `
                Name,
                Description,
                PortMonitor,
                PrinterHostAddress,
                PortNumber,
                SNMP,
                SNMPCommunity,
                SNMPDevIndex

            $portsJsonPath = Join-Path $DestinationFolder 'Ports.json'
            $ports | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $portsJsonPath -Encoding UTF8
            Write-MWLogInfo "Ports d'imprimantes exportÃ©s -> $portsJsonPath"
        } catch {
            Write-MWLogError "Erreur lors de l'export des ports d'imprimantes : $_"
        }
    } else {
        Write-MWLogWarning "Cmdlet Get-PrinterPort introuvable. Impossible d'exporter les ports."
    }
}

function Import-MWPrinters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe la configuration des imprimantes.
        .DESCRIPTION
            RecrÃ©e les ports TCP/IP, les imprimantes et l'imprimante par dÃ©faut
            Ã  partir des fichiers gÃ©nÃ©rÃ©s par Export-MWPrinters.
    #>

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        Write-MWLogError "Dossier source imprimantes introuvable : $SourceFolder"
        return
    }

    # Import des ports TCP/IP en prioritÃ©
    $portsJsonPath = Join-Path $SourceFolder 'Ports.json'
    if (Test-Path -LiteralPath $portsJsonPath -PathType Leaf) {
        try {
            $ports = Get-Content -LiteralPath $portsJsonPath -Raw | ConvertFrom-Json

            foreach ($p in $ports) {
                # On se concentre sur les ports Standard TCP/IP avec une adresse IP
                if (-not $p.PrinterHostAddress) { continue }
                if (-not $p.PortName) { $p.PortName = $p.Name }

                $portName = $p.Name
                if (-not $portName) { continue }

                if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                    try {
                        Write-MWLogInfo ("CrÃ©ation du port TCP/IP '{0}' -> {1}:{2}" -f $portName, $p.PrinterHostAddress, $p.PortNumber)
                        Add-PrinterPort -Name $portName -PrinterHostAddress $p.PrinterHostAddress -PortNumber $p.PortNumber -ErrorAction Stop | Out-Null
                    } catch {
                        Write-MWLogWarning ("CrÃ©ation du port '{0}' Ã©chouÃ©e : {1}" -f $portName, $_)
                    }
                } else {
                    Write-MWLogInfo "Port dÃ©jÃ  existant, non recrÃ©Ã© : $portName"
                }
            }
        } catch {
            Write-MWLogError "Erreur lors de l'import des ports d'imprimantes : $_"
        }
    } else {
        Write-MWLogWarning "Ports.json absent â€” crÃ©ation des ports limitÃ©e."
    }

    # Import des imprimantes
    $printersJsonPath = Join-Path $SourceFolder 'Printers_List.json'
    if (Test-Path -LiteralPath $printersJsonPath -PathType Leaf) {
        try {
            $plist = Get-Content -LiteralPath $printersJsonPath -Raw | ConvertFrom-Json

            foreach ($pr in $plist) {

                # On ignore les imprimantes virtuelles "classiques"
                if ($pr.DriverName -match 'Microsoft|OneNote|XPS|PDF') {
                    continue
                }

                $name = $pr.Name
                $drv  = $pr.DriverName
                $port = $pr.PortName

                if (-not $name -or -not $drv -or -not $port) {
                    Write-MWLogWarning "Imprimante ignorÃ©e (informations incomplÃ¨tes) : Name='$name', Driver='$drv', Port='$port'"
                    continue
                }

                if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) {
                    Write-MWLogWarning "Imprimante '$name' ignorÃ©e : port '$port' introuvable (WSD/USB ou partagÃ© ?)."
                    continue
                }

                if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
                    try {
                        Write-MWLogInfo "CrÃ©ation de l'imprimante '$name' (driver='$drv', port='$port')."
                        Add-Printer -Name $name -DriverName $drv -PortName $port -ErrorAction Stop | Out-Null

                        if ($pr.Location) {
                            try { Set-Printer -Name $name -Location $pr.Location -ErrorAction SilentlyContinue } catch {}
                        }
                        if ($pr.Comment) {
                            try { Set-Printer -Name $name -Comment $pr.Comment -ErrorAction SilentlyContinue } catch {}
                        }
                    } catch {
                        Write-MWLogError "CrÃ©ation de l'imprimante '$name' Ã©chouÃ©e : $_"
                    }
                } else {
                    Write-MWLogInfo "Imprimante dÃ©jÃ  existante, non recrÃ©Ã©e : $name"
                }
            }

            # Imprimante par dÃ©faut
            $defPath = Join-Path $SourceFolder 'DefaultPrinter.txt'
            if (Test-Path -LiteralPath $defPath -PathType Leaf) {
                $def = (Get-Content -LiteralPath $defPath -Raw).Trim()
                if ($def -and (Get-Printer -Name $def -ErrorAction SilentlyContinue)) {
                    try {
                        Set-Printer -Name $def -IsDefault $true -ErrorAction Stop
                        Write-MWLogInfo "Imprimante par dÃ©faut dÃ©finie : $def"
                    } catch {
                        Write-MWLogWarning "Impossible de dÃ©finir l'imprimante par dÃ©faut '$def' : $_"
                    }
                } else {
                    Write-MWLogWarning "Imprimante par dÃ©faut '$def' introuvable aprÃ¨s import."
                }
            }
        } catch {
            Write-MWLogError "Erreur lors de l'import des imprimantes (snapshot) : $_"
        }
    } else {
        Write-MWLogWarning "Printers_List.json absent â€” aucune imprimante Ã  recrÃ©er."
    }
}

Export-ModuleMember -Function Export-MWPrinters, Import-MWPrinters

