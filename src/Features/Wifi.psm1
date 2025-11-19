# src/Features/Wifi.psm1

function Export-MWWifiProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les profils Wi-Fi de la machine vers un dossier.
        .DESCRIPTION
            Utilise 'netsh wlan export profile' pour chaque profil dÃ©tectÃ©.
            Les profils sont exportÃ©s en clair (key=clear) dans des fichiers .xml.
    #>

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-MWLogInfo "Dossier d'export Wi-Fi crÃ©Ã© : $DestinationFolder"
        } catch {
            Write-MWLogError "Impossible de crÃ©er le dossier d'export Wi-Fi '$DestinationFolder' : $_"
            throw
        }
    }

    Write-MWLogInfo "DÃ©but de l'export des profils Wi-Fi vers : $DestinationFolder"

    # RÃ©cupÃ©ration de la liste des profils via netsh
    $profilesOutput = netsh wlan show profiles 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-MWLogError "Erreur lors de la rÃ©cupÃ©ration des profils Wi-Fi via 'netsh wlan show profiles'. Sortie : $profilesOutput"
        return
    }

    $profiles = @()

    foreach ($line in $profilesOutput) {
        if ($line -match '^\s*(All User Profile|Profil Tous les utilisateurs)\s*:\s*(.+)$') {
            $profileName = $matches[2].Trim()
            if ($profileName) {
                $profiles += $profileName
            }
        }
    }

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-MWLogWarning "Aucun profil Wi-Fi dÃ©tectÃ© Ã  exporter."
        return
    }

    Write-MWLogInfo ("{0} profil(s) Wi-Fi dÃ©tectÃ©(s) pour l'export." -f $profiles.Count)

    foreach ($profile in $profiles) {
        try {
            Write-MWLogInfo "Export du profil Wi-Fi '$profile'."
            netsh wlan export profile name="$profile" key=clear folder="$DestinationFolder" 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-MWLogWarning "Ã‰chec de l'export du profil Wi-Fi '$profile'."
            }
        } catch {
            Write-MWLogError "Exception lors de l'export du profil Wi-Fi '$profile' : $_"
        }
    }

    Write-MWLogInfo "Export des profils Wi-Fi terminÃ©."
}

function Import-MWWifiProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder
    )
    <#
        .SYNOPSIS
            Importe les profils Wi-Fi depuis un dossier.
        .DESCRIPTION
            Parcourt les fichiers .xml gÃ©nÃ©rÃ©s par 'netsh wlan export profile'
            et les rÃ©importe via 'netsh wlan add profile'.
    #>

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        Write-MWLogError "Dossier source Wi-Fi introuvable : $SourceFolder"
        return
    }

    $xmlFiles = Get-ChildItem -LiteralPath $SourceFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue

    if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
        Write-MWLogWarning "Aucun fichier .xml de profil Wi-Fi trouvÃ© dans : $SourceFolder"
        return
    }

    Write-MWLogInfo ("Import de {0} fichier(s) de profil Wi-Fi depuis : {1}" -f $xmlFiles.Count, $SourceFolder)

    foreach ($file in $xmlFiles) {
        try {
            Write-MWLogInfo "Import du profil Wi-Fi depuis le fichier : $($file.FullName)"
            netsh wlan add profile filename="$($file.FullName)" user=all 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-MWLogWarning "Ã‰chec de l'import du profil Wi-Fi depuis : $($file.FullName)"
            }
        } catch {
            Write-MWLogError "Exception lors de l'import du profil Wi-Fi depuis '$($file.FullName)' : $_"
        }
    }

    Write-MWLogInfo "Import des profils Wi-Fi terminÃ©."
}

Export-ModuleMember -Function Export-MWWifiProfiles, Import-MWWifiProfiles

