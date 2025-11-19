# src/Features/Outlook.psm1

function Copy-MWOutlookFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [string[]]$ExcludePatterns = @()
    )
    <#
        .SYNOPSIS
            Copie récursivement un dossier Outlook, en excluant certains fichiers si besoin.
        .DESCRIPTION
            - Recrée l'arborescence de $Source sous $Destination
            - Copie les fichiers en excluant ceux dont le Name matche un des ExcludePatterns (ex: '*.ost')
    #>

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-MWLogInfo "Dossier Outlook introuvable, rien à copier : $Source"
        return
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Write-MWLogInfo "Copie Outlook : '$Source' -> '$Destination'."

    Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object {
        $item = $_

        if ($item.PSIsContainer) {
            # Recrée l'arborescence
            $targetDir = $item.FullName.Replace($Source, $Destination)
            if (-not (Test-Path -LiteralPath $targetDir)) {
                try {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                } catch {
                    Write-MWLogWarning "Outlook: impossible de créer le dossier '$targetDir' : $($_.Exception.Message)"
                }
            }
            return
        }

        # Fichiers : gestion des exclusions (*.ost, etc.)
        $skip = $false
        foreach ($mask in $ExcludePatterns) {
            if ($item.Name -like $mask) {
                $skip = $true
                break
            }
        }
        if ($skip) {
            Write-MWLogInfo "Outlook: fichier ignoré (pattern match) '$($item.FullName)'."
            return
        }

        $targetPath = $item.FullName.Replace($Source, $Destination)
        $targetDir  = Split-Path -Path $targetPath -Parent

        if (-not (Test-Path -LiteralPath $targetDir)) {
            try {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            } catch {
                Write-MWLogWarning "Outlook: impossible de créer le dossier cible '$targetDir' : $($_.Exception.Message)"
            }
        }

        try {
            Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force -ErrorAction Stop
        } catch {
            Write-MWLogWarning "Outlook: erreur lors de la copie de '$($item.FullName)' : $($_.Exception.Message)"
        }
    }
}

function Export-MWOutlookData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les données Outlook (AppData Local/Roaming + Signatures).
        .DESCRIPTION
            Reprend la logique de Export-AppDataOutlook :
            - Local  : %LOCALAPPDATA%\Microsoft\Outlook  -> AppDataOutlook\Local\Microsoft\Outlook
            - Roaming Outlook  : %APPDATA%\Microsoft\Outlook -> AppDataOutlook\Roaming\Microsoft\Outlook
            - Signatures       : %APPDATA%\Microsoft\Signatures -> AppDataOutlook\Roaming\Microsoft\Signatures
            Les fichiers .ost sont exclus (archives volumineuses inutiles ici).
    #>

    try {
        $base = Join-Path $DestinationFolder 'AppDataOutlook'
        if (-not (Test-Path -LiteralPath $base)) {
            New-Item -ItemType Directory -Path $base -Force | Out-Null
        }

        $srcLocalOutlook   = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        $srcRoamingOutlook = Join-Path $env:APPDATA      'Microsoft\Outlook'
        $srcSignatures     = Join-Path $env:APPDATA      'Microsoft\Signatures'

        $dstLocalOutlook   = Join-Path $base 'Local\Microsoft\Outlook'
        $dstRoamingOutlook = Join-Path $base 'Roaming\Microsoft\Outlook'
        $dstSignatures     = Join-Path $base 'Roaming\Microsoft\Signatures'

        # Local (OST exclus)
        Copy-MWOutlookFolder -Source $srcLocalOutlook   -Destination $dstLocalOutlook   -ExcludePatterns @('*.ost')

        # Roaming Outlook (par sécurité on exclut aussi *.ost, même s'il y en a rarement ici)
        Copy-MWOutlookFolder -Source $srcRoamingOutlook -Destination $dstRoamingOutlook -ExcludePatterns @('*.ost')

        # Signatures : on prend tout
        Copy-MWOutlookFolder -Source $srcSignatures     -Destination $dstSignatures     -ExcludePatterns @()

        Write-MWLogInfo "AppData Outlook exporté."
    } catch {
        Write-MWLogError "Export AppData Outlook : $($_.Exception.Message)"
        throw
    }
}

function Import-MWOutlookData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe les données Outlook (AppData Local/Roaming + Signatures).
        .DESCRIPTION
            Reprend la logique de Import-AppDataOutlook :
            - Local  : AppDataOutlook\Local\Microsoft\Outlook       -> %LOCALAPPDATA%\Microsoft\Outlook
            - Roaming Outlook  : AppDataOutlook\Roaming\Microsoft\Outlook   -> %APPDATA%\Microsoft\Outlook
            - Signatures       : AppDataOutlook\Roaming\Microsoft\Signatures -> %APPDATA%\Microsoft\Signatures
    #>

    try {
        $base = Join-Path $SourceFolder 'AppDataOutlook'
        if (-not (Test-Path -LiteralPath $base -PathType Container)) {
            Write-MWLogWarning "AppDataOutlook absent — rien à restaurer. Dossier manquant : $base"
            return
        }

        $srcLocalOutlook   = Join-Path $base 'Local\Microsoft\Outlook'
        $srcRoamingOutlook = Join-Path $base 'Roaming\Microsoft\Outlook'
        $srcSignatures     = Join-Path $base 'Roaming\Microsoft\Signatures'

        $dstLocalOutlook   = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
        $dstRoamingOutlook = Join-Path $env:APPDATA      'Microsoft\Outlook'
        $dstSignatures     = Join-Path $env:APPDATA      'Microsoft\Signatures'

        Copy-MWOutlookFolder -Source $srcLocalOutlook   -Destination $dstLocalOutlook   -ExcludePatterns @()  # à l'import, on ne filtre pas
        Copy-MWOutlookFolder -Source $srcRoamingOutlook -Destination $dstRoamingOutlook -ExcludePatterns @()
        Copy-MWOutlookFolder -Source $srcSignatures     -Destination $dstSignatures     -ExcludePatterns @()

        Write-MWLogInfo "AppData Outlook importé."
    } catch {
        Write-MWLogError "Import AppData Outlook : $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWOutlookData, Import-MWOutlookData
