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
              - DefaultPrinter.txt : nom de l'imprimante par défaut
              - Ports.json         : liste des ports TCP/IP
    #>

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-MWLogInfo ("Dossier d'export imprimantes créé : {0}" -f $DestinationFolder)
        } catch {
            Write-MWLogError ("Impossible de créer le dossier d'export imprimantes '{0}' : {1}" -f $DestinationFolder, $_)
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
                @{Name = 'IsDefault'; Expression = { $_.Default }}

            $printersJsonPath = Join-Path $DestinationFolder 'Printers_List.json'
            $plist | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $printersJsonPath -Encoding UTF8
            Write-MWLogInfo ("Liste imprimantes exportée -> {0}" -f $printersJsonPath)

            $def = ($plist | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1).Name
            if ($def) {
                $defPath = Join-Path $DestinationFolder 'DefaultPrinter.txt'
                $def | Set-Content -LiteralPath $defPath -Encoding UTF8
                Write-MWLogInfo ("Imprimante par défaut exportée : {0}" -f $def)
            } else {
                Write-MWLogWarning "Aucune imprimante par défaut détectée."
            }
        } catch {
            Write-MWLogError ("Erreur lors de l'export de la liste des imprimantes : {0}" -f $_)
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
            Write-MWLogInfo ("Ports d'imprimantes exportés -> {0}" -f $portsJsonPath)
        } catch {
            Write-MWLogError ("Erreur lors de l'export des ports d'imprimantes : {0}" -f $_)
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
            Recrée les ports TCP/IP, les imprimantes et l'imprimante par défaut
            à partir des fichiers générés par Export-MWPrinters.
    #>

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        Write-MWLogError ("Dossier source imprimantes introuvable : {0}" -f $SourceFolder)
        return
    }

    #
    # 1) Import des ports TCP/IP en priorité
    #
    $portsJsonPath = Join-Path $SourceFolder 'Ports.json'
    if (Test-Path -LiteralPath $portsJsonPath -PathType Leaf) {
        try {
            $ports = Get-Content -LiteralPath $portsJsonPath -Raw | ConvertFrom-Json

            foreach ($p in $ports) {
                # On se concentre sur les ports Standard TCP/IP avec une adresse IP
                if (-not $p.PrinterHostAddress) { continue }

                # Détermination du nom de port : PortName si présent, sinon Name
                $portName = $null
                if ($p.PSObject.Properties['PortName'] -and $p.PortName) {
                    $portName = $p.PortName
                } else {
                    $portName = $p.Name
                }

                if (-not $portName) { continue }

                if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                    try {
                        Write-MWLogInfo ("Création du port TCP/IP '{0}' -> {1}:{2}" -f $portName, $p.PrinterHostAddress, $p.PortNumber)
                        Add-PrinterPort -Name $portName -PrinterHostAddress $p.PrinterHostAddress -PortNumber $p.PortNumber -ErrorAction Stop | Out-Null
                    } catch {
                        Write-MWLogWarning ("Création du port '{0}' échouée : {1}" -f $portName, $_)
                    }
                } else {
                    Write-MWLogInfo ("Port déjà existant, non recréé : {0}" -f $portName)
                }
            }
        } catch {
            Write-MWLogError ("Erreur lors de l'import des ports d'imprimantes : {0}" -f $_)
        }
    } else {
        Write-MWLogWarning "Ports.json absent - création des ports limitée."
    }

    #
    # 2) Import des imprimantes
    #
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
                    Write-MWLogWarning ("Imprimante ignorée (informations incomplètes) : Name='{0}', Driver='{1}', Port='{2}'" -f $name, $drv, $port)
                    continue
                }

                if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) {
                    Write-MWLogWarning ("Imprimante '{0}' ignorée : port '{1}' introuvable (WSD/USB ou partagé ?)." -f $name, $port)
                    continue
                }

                if (-not (Get-Printer -Name $name -ErrorAction SilentlyContinue)) {
                    try {
                        Write-MWLogInfo ("Création de l'imprimante '{0}' (driver='{1}', port='{2}')." -f $name, $drv, $port)
                        Add-Printer -Name $name -DriverName $drv -PortName $port -ErrorAction Stop | Out-Null

                        if ($pr.Location) {
                            try { Set-Printer -Name $name -Location $pr.Location -ErrorAction SilentlyContinue } catch {}
                        }
                        if ($pr.Comment) {
                            try { Set-Printer -Name $name -Comment $pr.Comment -ErrorAction SilentlyContinue } catch {}
                        }
                    } catch {
                        Write-MWLogError ("Création de l'imprimante '{0}' échouée : {1}" -f $name, $_)
                    }
                } else {
                    Write-MWLogInfo ("Imprimante déjà existante, non recréée : {0}" -f $name)
                }
            }

            # Imprimante par défaut
            $defPath = Join-Path $SourceFolder 'DefaultPrinter.txt'
            if (Test-Path -LiteralPath $defPath -PathType Leaf) {
                $def = (Get-Content -LiteralPath $defPath -Raw).Trim()
                if ($def -and (Get-Printer -Name $def -ErrorAction SilentlyContinue)) {
                    try {
                        Set-Printer -Name $def -IsDefault $true -ErrorAction Stop
                        Write-MWLogInfo ("Imprimante par défaut définie : {0}" -f $def)
                    } catch {
                        Write-MWLogWarning ("Impossible de définir l'imprimante par défaut '{0}' : {1}" -f $def, $_)
                    }
                } else {
                    Write-MWLogWarning ("Imprimante par défaut '{0}' introuvable après import." -f $def)
                }
            }
        } catch {
            Write-MWLogError ("Erreur lors de l'import des imprimantes (snapshot) : {0}" -f $_)
        }
    } else {
        Write-MWLogWarning "Printers_List.json absent - aucune imprimante à recréer."
    }
}

Export-ModuleMember -Function Export-MWPrinters, Import-MWPrinters
