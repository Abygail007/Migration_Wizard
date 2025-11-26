



\## 1) Commandes PowerShell pour créer / ouvrir le fichier



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



New-Item -ItemType Directory -Path .\\docs -Force | Out-Null

New-Item -ItemType File      -Path .\\docs\\MW-Work-Done.md -Force | Out-Null



notepad .\\docs\\MW-Work-Done.md

```



Ensuite tu colles le contenu ci-dessous dans `MW-Work-Done.md`.



---



\## 2) Contenu à coller dans `MW-Work-Done.md`



````markdown

\# MigrationWizard – Ce qui est déjà fait (travail réalisé)



Ce document liste \*\*tout ce qui est déjà implémenté\*\* dans la nouvelle version modulaire de MigrationWizard, à partir :

\- du script historique ~3000 lignes,

\- des refactors déjà faits,

\- des nouveaux modules (Logging, Export, DataFolders, Profile, …),

\- des tests réalisés en console.



L'idée : savoir précisément ce qui est \*\*OK / testé\*\*, avant de lister ce qu’il reste à faire dans un autre fichier.



---



\## 1. Logging centralisé – `src\\Modules\\MW.Logging.psm1`



\### 1.1. Objectif



\- Avoir un \*\*système de log unique\*\* pour tout le projet.

\- Ne plus réécrire du `Write-Host` partout.

\- Produire un fichier log par jour dans `.\\Logs\\MigrationWizard\_YYYY-MM-DD.log`.



\### 1.2. Fonctions principales déjà en place



\- `Initialize-MWLogging`

&nbsp; - Crée le dossier `.\\Logs` si nécessaire.

&nbsp; - Détermine le nom du fichier log du jour.

&nbsp; - Prépare l’environnement (variable globale / scope module) pour les autres fonctions.



\- `Write-MWLog`

&nbsp; - Point d’entrée principal pour écrire une ligne de log.

&nbsp; - Gère :

&nbsp;   - le niveau (`INFO`, `WARN`, `ERROR`, `DEBUG`),

&nbsp;   - le timestamp,

&nbsp;   - le message formaté,

&nbsp;   - l’écriture dans le fichier via `Add-Content`.



\- `Write-MWLogInfo`, `Write-MWLogWarn`, `Write-MWLogError`, `Write-MWLogDebug`

&nbsp; - Wrappers pratiques pour appeler `Write-MWLog` avec un niveau donné.



\- Gestion d’erreur sur le log :

&nbsp; - Si le fichier est verrouillé ou inaccessible, les erreurs d’`Add-Content` sont capturées

&nbsp;   et n’empêchent pas le reste du code de tourner (même si le log ne s’écrit pas).



\### 1.3. Utilisation actuelle



\- Tous les nouveaux modules Core (Export, DataFolders, Profile) utilisent ce logging :

&nbsp; - `Write-MWLogInfo "message ..."`

&nbsp; - `Write-MWLogError "message ..."`

&nbsp; - etc.



---



\## 2. Snapshots Export – `src\\Core\\Export.psm1`



\### 2.1. Objectif



\- Centraliser \*\*tous les chemins\*\* utilisés par l’export :

&nbsp; - dossier racine d’export,

&nbsp; - sous-dossier des logs,

&nbsp; - dossier des données utilisateur,

&nbsp; - manifest des applications,

&nbsp; - manifest des DataFolders,

&nbsp; - etc.

\- Remplacer les concaténations en dur du script historique par une structure propre.



\### 2.2. Fonctions déjà implémentées



\- `Save-MWExportSnapshot`

&nbsp; - Construit un objet PowerShell avec :

&nbsp;   - métadonnées (date, machine, utilisateur, OS, etc.),

&nbsp;   - un bloc `Paths` contenant tous les chemins calculés (relatifs ou absolus).

&nbsp; - Sérialise le tout en JSON dans un fichier (par ex. `.\\Logs\\test\_export\_snapshot\_rz.json`).



\- `Import-MWExportSnapshot`

&nbsp; - Relit le JSON,

&nbsp; - Le reconvertit en objet PowerShell,

&nbsp; - Permet d’accéder facilement à `$snap.Paths.<Truc>`.



\### 2.3. Exemples de champs déjà dans `Paths`



\- `ExportRoot`

\- `UserDataRoot` (ex : `.\\Logs\\UserData`)

\- `DataFoldersManifestPath` (ex : `.\\Logs\\UserData\\DataFolders.manifest.json`)

\- `ApplicationsManifestPath`

\- (et autres chemins nécessaires pour la suite)



\### 2.4. Tests réalisés



\- Génération + relecture d’un snapshot :



&nbsp; ```powershell

&nbsp; $exportPath = ".\\Logs\\test\_export\_snapshot\_rz.json"



&nbsp; Save-MWExportSnapshot -Path $exportPath

&nbsp; $snap = Import-MWExportSnapshot -Path $exportPath



&nbsp; $snap.Paths | Format-List \*

````



\* Validation : les chemins clés sont bien présents et cohérents.



---



\## 3. Dossiers utilisateur (DataFolders) – `src\\Core\\DataFolders.psm1`



\### 3.1. Objectif



\* Remplacer l’ancien bloc “export brut des dossiers Windows” par :



&nbsp; \* un \*\*manifest JSON\*\* listant les dossiers “classiques”,

&nbsp; \* la possibilité de \*\*choisir\*\* ce qu’on exporte via une grille (`Out-GridView`),

&nbsp; \* des fonctions d’export/import réutilisables et testables indépendamment.



\### 3.2. Dossiers gérés



Pour l’instant, la liste par défaut couvre :



\* `Desktop`   → Bureau

\* `Documents` → Documents

\* `Downloads` → Téléchargements

\* `Pictures`  → Images

\* `Music`     → Musique

\* `Videos`    → Vidéos

\* `Favorites` → Favoris

\* `Links`     → Liens

\* `Contacts`  → Contacts



Chaque entrée a :



\* `Key`          (identifiant logique)

\* `RelativePath` (ex: `Desktop`)

\* `Label`        (libellé pour l’UI)

\* `SourcePath`   (chemin complet dans le profil courant)

\* `Exists`       (booléen)

\* `Include`      (booléen – inclus par défaut)



\### 3.3. Fonctions déjà en place



\* `Get-MWDefaultDataFolders`



&nbsp; \* Retourne la liste par défaut (voir ci-dessus).



\* `New-MWDataFoldersManifest`



&nbsp; \* À partir d’un `UserProfilePath` (par défaut `$env:USERPROFILE`),

&nbsp; \* calcule les `SourcePath`,

&nbsp; \* détecte `Exists`,

&nbsp; \* construit un tableau d’objets complet.



\* `Save-MWDataFoldersManifest`



&nbsp; \* Appelle `New-MWDataFoldersManifest`,

&nbsp; \* crée le dossier cible si besoin,

&nbsp; \* sérialise en JSON dans un fichier (ex: `.\\Logs\\UserData\\DataFolders.manifest.json`).



\* `Get-MWDataFoldersManifest`



&nbsp; \* Lit un manifest JSON existant,

&nbsp; \* renvoie un tableau d’objets PowerShell.



\* `Export-MWDataFolders`



&nbsp; \* Parcourt le manifest,

&nbsp; \* respecte le flag `Include`,

&nbsp; \* copie les dossiers source → destination (avec `robocopy`),

&nbsp; \* prend en charge l’option `-WhatIf` via `SupportsShouldProcess`.



\* `Import-MWDataFolders`



&nbsp; \* Recharge le manifest,

&nbsp; \* reconstruit la table des chemins cibles pour \*\*le profil courant\*\*,

&nbsp; \* copie les données depuis le dossier d’export vers les dossiers Windows (Desktop, Documents, etc.),

&nbsp; \* supporte aussi `-WhatIf`.



\* `Show-MWDataFoldersExportPlan`



&nbsp; \* Mode interactif :



&nbsp;   \* (re)génère le manifest si besoin,

&nbsp;   \* affiche les dossiers dans un `Out-GridView` avec sélection multiple,

&nbsp;   \* met à jour `Include` selon la sélection,

&nbsp;   \* resauvegarde le manifest,

&nbsp;   \* lance `Export-MWDataFolders` (export réel, sans `-WhatIf`).



\### 3.4. Tests réalisés



À partir d’un snapshot :



```powershell

$exportPath   = ".\\Logs\\test\_export\_snapshot\_rz.json"



Save-MWExportSnapshot -Path $exportPath

$snap         = Import-MWExportSnapshot -Path $exportPath

$manifestPath = $snap.Paths.DataFoldersManifestPath

$userDataRoot = $snap.Paths.UserDataRoot



\# (Re)génération du manifest

Save-MWDataFoldersManifest -ManifestPath $manifestPath



\# Export en simulation

Export-MWDataFolders -ManifestPath $manifestPath -DestinationRoot $userDataRoot -WhatIf



\# Import en simulation

Import-MWDataFolders -ManifestPath $manifestPath -SourceRoot $userDataRoot -WhatIf

```



Et en mode interactif :



```powershell

Show-MWDataFoldersExportPlan -ManifestPath $manifestPath -DestinationRoot $userDataRoot

Show-MWDataFoldersImportPlan -ManifestPath $manifestPath -SourceRoot      $userDataRoot

```



---



\## 4. Orchestration profil – `src\\Core\\Profile.psm1`



\### 4.1. Objectif



\* Remplacer l’ancien gros script par une \*\*orchestration propre\*\* :



&nbsp; \* une fonction `Export-MWProfile` qui pilote toutes les briques d’export,

&nbsp; \* une fonction `Import-MWProfile` qui pilote toutes les briques d’import,

&nbsp; \* une liste claire de \*\*flags\*\* pour activer/désactiver chaque zone.



\### 4.2. `Export-MWProfile` – état actuel



Signature actuelle :



```powershell

function Export-MWProfile {

&nbsp;   \[CmdletBinding()]

&nbsp;   param(

&nbsp;       \[Parameter(Mandatory = $true)]

&nbsp;       \[string]$DestinationFolder,



&nbsp;       \[bool]$IncludeUserData           = $true,

&nbsp;       \[bool]$IncludeWifi               = $true,

&nbsp;       \[bool]$IncludePrinters           = $true,

&nbsp;       \[bool]$IncludeNetworkDrives      = $true,

&nbsp;       \[bool]$IncludeRdp                = $true,

&nbsp;       \[bool]$IncludeBrowsers           = $true,

&nbsp;       \[bool]$IncludeOutlook            = $true,

&nbsp;       \[bool]$IncludeWallpaper          = $true,

&nbsp;       \[bool]$IncludeDesktopLayout      = $true,

&nbsp;       \[bool]$IncludeTaskbarStart       = $true,

&nbsp;       \[bool]$UseDataFoldersManifest    = $false

&nbsp;   )

}

```



Bloc \*\*données utilisateur\*\* :



\* Si `IncludeUserData = $true` \*\*et\*\* `UseDataFoldersManifest = $true` :



&nbsp; \* on calcule :



&nbsp;   \* `$profileDestRoot = Join-Path $DestinationFolder 'Profile'`

&nbsp;   \* `$manifestPath    = Join-Path $DestinationFolder 'DataFolders.manifest.json'`

&nbsp; \* on logge le mode avancé,

&nbsp; \* on appelle `Show-MWDataFoldersExportPlan -ManifestPath $manifestPath -DestinationRoot $profileDestRoot`.



\* Si `UseDataFoldersManifest = $false` :



&nbsp; \* on garde le \*\*comportement historique\*\* : `Export-MWUserData -DestinationFolder $DestinationFolder`.



Les blocs pour Wifi / Imprimantes / RDP / Navigateur / Outlook / Wallpaper / Layout / Taskbar sont en place côté structure

(appels à des fonctions Features), mais les fonctionnalités détaillées restent à finaliser dans leurs modules respectifs.



\### 4.3. `Import-MWProfile` – état actuel



Signature actuelle :



```powershell

function Import-MWProfile {

&nbsp;   \[CmdletBinding()]

&nbsp;   param(

&nbsp;       \[Parameter(Mandatory = $true)]

&nbsp;       \[string]$SourceFolder,



&nbsp;       \[bool]$IncludeUserData           = $true,

&nbsp;       \[bool]$IncludeWifi               = $true,

&nbsp;       \[bool]$IncludePrinters           = $true,

&nbsp;       \[bool]$IncludeNetworkDrives      = $true,

&nbsp;       \[bool]$IncludeRdp                = $true,

&nbsp;       \[bool]$IncludeBrowsers           = $true,

&nbsp;       \[bool]$IncludeOutlook            = $true,

&nbsp;       \[bool]$IncludeWallpaper          = $true,

&nbsp;       \[bool]$IncludeDesktopLayout      = $true,

&nbsp;       \[bool]$IncludeTaskbarStart       = $true,

&nbsp;       \[bool]$UseDataFoldersManifest    = $false

&nbsp;   )

}

```



Bloc \*\*données utilisateur\*\* :



\* Si `IncludeUserData = $true` \*\*et\*\* `UseDataFoldersManifest = $true` :



&nbsp; \* on construit ` $manifestPath = Join-Path $SourceFolder 'DataFolders.manifest.json'`,

&nbsp; \* on logge le mode avancé,

&nbsp; \* on appelle `Show-MWDataFoldersImportPlan -ManifestPath $manifestPath -SourceRoot $SourceFolder`.



\* Sinon :



&nbsp; \* on revient au comportement historique : `Import-MWUserData -SourceFolder $SourceFolder`.



Les blocs pour Wifi / Imprimantes / etc. sont structurés de la même manière qu’à l’export, mais les détails restent à implémenter dans les modules Features.



\### 4.4. Gestion des erreurs globales



\* Les deux fonctions sont entourées d’un \*\*try/catch global\*\* avec :



&nbsp; \* `Write-MWLogError "Export-MWProfile (global) : ..."`

&nbsp; \* `Write-MWLogError "Import-MWProfile (global) : ..."`

\* En cas de plantage interne, l’erreur est loggée proprement.



---



\## 5. Tests globaux déjà effectués



\### 5.1. Session type



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging



Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking



$dest = "C:\\Temp\\MigrationTest"

```



\### 5.2. Export profil – uniquement données utilisateur via DataFolders



```powershell

Export-MWProfile `

&nbsp;   -DestinationFolder      $dest `

&nbsp;   -UseDataFoldersManifest $true `

&nbsp;   -IncludeWifi            $false `

&nbsp;   -IncludePrinters        $false `

&nbsp;   -IncludeNetworkDrives   $false `

&nbsp;   -IncludeRdp             $false `

&nbsp;   -IncludeBrowsers        $false `

&nbsp;   -IncludeOutlook         $false `

&nbsp;   -IncludeWallpaper       $false `

&nbsp;   -IncludeDesktopLayout   $false `

&nbsp;   -IncludeTaskbarStart    $false

```



Résultat :



\* Ouverture d’une fenêtre `Out-GridView` pour choisir les dossiers,

\* Création d’un `DataFolders.manifest.json` dans le dossier d’export,

\* Copie des dossiers sélectionnés vers le dossier `Profile\\…` de l’export.



\### 5.3. Import profil – uniquement données utilisateur via DataFolders



```powershell

Import-MWProfile `

&nbsp;   -SourceFolder           $dest `

&nbsp;   -UseDataFoldersManifest $true `

&nbsp;   -IncludeWifi            $false `

&nbsp;   -IncludePrinters        $false `

&nbsp;   -IncludeNetworkDrives   $false `

&nbsp;   -IncludeRdp             $false `

&nbsp;   -IncludeBrowsers        $false `

&nbsp;   -IncludeOutlook         $false `

&nbsp;   -IncludeWallpaper       $false `

&nbsp;   -IncludeDesktopLayout   $false `

&nbsp;   -IncludeTaskbarStart    $false

```



Résultat :



\* Relecture du même `DataFolders.manifest.json`,

\* Calcul des chemins de destination pour le profil courant,

\* Préparation des copies avec `robocopy` (et logs détaillés).



---



\## 6. Limitations actuelles (rapidement, en attendant le fichier TODO)



\* Modules Features (Wifi, Imprimantes, RDP, Navigateurs, Outlook, Wallpaper, Layout, Taskbar) :



&nbsp; \* structure prévue / imaginée,

&nbsp; \* mais implémentation complète encore à faire ou à reprendre proprement.



\* UI WPF / EXE :



&nbsp; \* toute la partie interface graphique et “mode EXE” n’est pas encore reconnectée au nouveau cœur modulaire,

&nbsp; \* pour l’instant, les tests se font en console PowerShell.



Un fichier séparé décrira \*\*tout ce qu’il reste à faire\*\* (roadmap détaillée, par module).



---



```



