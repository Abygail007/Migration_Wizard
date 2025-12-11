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
            Utilise 'netsh wlan export profile' pour chaque profil détecté.
            Si la carte WiFi est désactivée, tente d'exporter depuis le registre.
            Les profils sont exportés en clair (key=clear) dans des fichiers .xml.
    #>

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-MWLogInfo "Dossier d'export Wi-Fi créé : $DestinationFolder"
        } catch {
            Write-MWLogError "Impossible de créer le dossier d'export Wi-Fi '$DestinationFolder' : $_"
            throw
        }
    }

    Write-MWLogInfo "Début de l'export des profils Wi-Fi vers : $DestinationFolder"

    # Récupération de la liste des profils via netsh
    $profilesOutput = netsh wlan show profiles 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-MWLogWarning "Impossible de récupérer les profils Wi-Fi via netsh (adaptateur WiFi absent ou désactivé ?). Code: $LASTEXITCODE"
        Write-MWLogInfo "Tentative d'export depuis le registre..."

        # Fallback: Export depuis le registre
        try {
            Export-MWWifiProfilesFromRegistry -DestinationFolder $DestinationFolder
            return
        } catch {
            Write-MWLogError "Export WiFi depuis registre échoué : $($_.Exception.Message)"
            return
        }
    }

    $profiles = @()

    # Regex plus permissive pour supporter différentes versions de Windows
    foreach ($line in $profilesOutput) {
        # Exemples de lignes possibles:
        # "    All User Profile     : MonWiFi"
        # "    Profil Tous les utilisateurs : MonWiFi"
        # "    User Profile         : MonWiFi"
        # "    Profil utilisateur   : MonWiFi"
        if ($line -match '^\s*(All User Profile|Profil Tous les utilisateurs|User Profile|Profil utilisateur)\s*:\s*(.+)$') {
            $profileName = $matches[2].Trim()
            if ($profileName) {
                $profiles += $profileName
                Write-MWLogInfo "Profil WiFi détecté : '$profileName'"
            }
        }
    }

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-MWLogWarning "Aucun profil Wi-Fi détecté à exporter (sortie netsh: $($profilesOutput.Count) lignes)"
        Write-MWLogInfo "Première ligne netsh: $($profilesOutput | Select-Object -First 1)"
        return
    }

    Write-MWLogInfo ("{0} profil(s) Wi-Fi détecté(s) pour l'export." -f $profiles.Count)

    foreach ($profile in $profiles) {
        try {
            Write-MWLogInfo "Export du profil Wi-Fi '$profile'."
            netsh wlan export profile name="$profile" key=clear folder="$DestinationFolder" 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-MWLogWarning "Échec de l'export du profil Wi-Fi '$profile'."
            }
        } catch {
            Write-MWLogError "Exception lors de l'export du profil Wi-Fi '$profile' : $_"
        }
    }

    Write-MWLogInfo "Export des profils Wi-Fi terminé."
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
            Parcourt les fichiers .xml générés par 'netsh wlan export profile'
            et les réimporte via 'netsh wlan add profile'.
    #>

    if (-not (Test-Path -LiteralPath $SourceFolder)) {
        Write-MWLogError "Dossier source Wi-Fi introuvable : $SourceFolder"
        return
    }

    $xmlFiles = Get-ChildItem -LiteralPath $SourceFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue

    if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
        Write-MWLogWarning "Aucun fichier .xml de profil Wi-Fi trouvé dans : $SourceFolder"
        return
    }

    Write-MWLogInfo ("Import de {0} fichier(s) de profil Wi-Fi depuis : {1}" -f $xmlFiles.Count, $SourceFolder)

    foreach ($file in $xmlFiles) {
        try {
            Write-MWLogInfo "Import du profil Wi-Fi depuis le fichier : $($file.FullName)"
            netsh wlan add profile filename="$($file.FullName)" user=all 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-MWLogWarning "Échec de l'import du profil Wi-Fi depuis : $($file.FullName)"
            }
        } catch {
            Write-MWLogError "Exception lors de l'import du profil Wi-Fi depuis '$($file.FullName)' : $_"
        }
    }

    Write-MWLogInfo "Import des profils Wi-Fi terminé."
}

function Export-MWWifiProfilesFromRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder
    )
    <#
        .SYNOPSIS
            Exporte les profils Wi-Fi depuis ProgramData (fallback si carte WiFi désactivée)
        .DESCRIPTION
            FIX: Lire les profils WiFi directement depuis les fichiers XML dans:
            $env:ProgramData\Microsoft\Wlansvc\Profiles\Interfaces
            Cette méthode fonctionne même si la carte WiFi est désactivée et inclut les mots de passe
    #>

    try {
        # FIX: Utiliser l'approche du script utilisateur - lire depuis ProgramData
        $profilesRoot = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'

        if (-not (Test-Path $profilesRoot)) {
            Write-MWLogWarning "Aucun profil Wi-Fi trouvé (dossier $profilesRoot introuvable)"
            return
        }

        Write-MWLogInfo "Lecture des profils WiFi depuis ProgramData..."

        $exportedCount = 0
        $exportedProfiles = @()

        # Parcourir chaque interface (GUID)
        $interfaces = Get-ChildItem -Path $profilesRoot -Directory -ErrorAction SilentlyContinue

        foreach ($interface in $interfaces) {
            $interfaceGuid = $interface.Name
            Write-MWLogInfo "Interface WiFi détectée : $interfaceGuid"

            # Parcourir chaque fichier XML de profil
            $xmlFiles = Get-ChildItem -Path $interface.FullName -Filter '*.xml' -File -ErrorAction SilentlyContinue

            foreach ($xmlFile in $xmlFiles) {
                try {
                    # Lire le XML pour extraire le nom du profil
                    [xml]$xml = Get-Content -Path $xmlFile.FullName -ErrorAction Stop
                    $profile = $xml.WLANProfile

                    if ($profile -and $profile.name) {
                        $profileName = $profile.name
                        $ssid = if ($profile.SSIDConfig.SSID.name) { $profile.SSIDConfig.SSID.name } else { $profileName }

                        Write-MWLogInfo "Profil WiFi détecté (ProgramData): '$profileName' (SSID: $ssid)"

                        # Copier le fichier XML vers le dossier d'export
                        $destFile = Join-Path $DestinationFolder $xmlFile.Name
                        Copy-Item -LiteralPath $xmlFile.FullName -Destination $destFile -Force

                        $exportedProfiles += [PSCustomObject]@{
                            InterfaceGuid  = $interfaceGuid
                            ProfileFile    = $xmlFile.Name
                            ProfileName    = $profileName
                            SSID           = $ssid
                            Authentication = if ($profile.MSM.security.authEncryption.authentication) { $profile.MSM.security.authEncryption.authentication } else { "Unknown" }
                            Encryption     = if ($profile.MSM.security.authEncryption.encryption) { $profile.MSM.security.authEncryption.encryption } else { "Unknown" }
                        }

                        $exportedCount++
                    }
                } catch {
                    Write-MWLogWarning "Impossible de lire le profil '$($xmlFile.FullName)' : $($_.Exception.Message)"
                }
            }
        }

        if ($exportedCount -gt 0) {
            # Créer un JSON avec la liste des profils
            $jsonPath = Join-Path $DestinationFolder "wifi_profiles_list.json"
            $exportedProfiles | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8

            Write-MWLogInfo "Profils WiFi exportés depuis ProgramData: $exportedCount profil(s)"

            # Note pour l'utilisateur
            $notePath = Join-Path $DestinationFolder "wifi_readme.txt"
            @"
PROFILS WI-FI EXPORTÉS DEPUIS PROGRAMDATA

Ces profils ont été exportés directement depuis les fichiers système.
Les mots de passe WiFi SONT inclus dans cet export (fichiers XML).

Profils détectés:
$($exportedProfiles | ForEach-Object { "- $($_.ProfileName) (SSID: $($_.SSID))" } | Out-String)

Lors de l'import, ces profils seront restaurés avec les mots de passe.
"@ | Set-Content -Path $notePath -Encoding UTF8

            Write-MWLogInfo "Note d'export créée: $notePath"
        } else {
            Write-MWLogWarning "Aucun profil WiFi valide exporté depuis ProgramData"
        }

    } catch {
        Write-MWLogError "Export-MWWifiProfilesFromRegistry: $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Export-MWWifiProfiles, Import-MWWifiProfiles


