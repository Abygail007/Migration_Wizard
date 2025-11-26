

---

## 1) Commandes PowerShell pour créer / ouvrir le fichier

Dans ton repo :

```powershell
cd "C:\Users\jmthomas\Documents\Creation\MigrationWizard\Github"

New-Item -ItemType Directory -Path .\docs -Force | Out-Null
New-Item -ItemType File      -Path .\docs\MW-Implemented-Features.md -Force | Out-Null

notepad .\docs\MW-Implemented-Features.md
```

Colle le contenu ci-dessous dans `MW-Implemented-Features.md`.

---

## 2) Contenu à coller dans `MW-Implemented-Features.md`

````markdown
# MigrationWizard – Fonctionnalités déjà implémentées

Ce fichier décrit **l’état actuel** du projet MigrationWizard, en se basant sur :
- le script historique (~3000 lignes),
- les refactorings en modules,
- les ajouts / améliorations faits récemment (Logging, Export snapshot, DataFolders, Profile, etc.).

L’idée : avoir une **photo claire de ce qui existe déjà**, avant de lister ce qu’il reste à faire.

---

## 1. Architecture actuelle (haute niveau)

### 1.1. Découpage en modules

Le projet est désormais structuré en plusieurs modules PowerShell sous `src\` :

- `src\Modules\MW.Logging.psm1`  
  Gestion centralisée des logs de l’outil.

- `src\Core\Export.psm1`  
  Cœur de la logique d’export : creation d’un “snapshot” JSON de ce qui va être fait.

- `src\Core\Applications.psm1`  
  Recensement des applications installées + filtrage pour l’export.

- `src\Core\DataFolders.psm1`  
  Gestion des **dossiers utilisateurs classiques** (Bureau, Documents, Images, etc.) via un **manifest** JSON + export/import.

- `src\Core\Profile.psm1`  
  Orchestration haut niveau : `Export-MWProfile` et `Import-MWProfile` qui appellent les fonctions Core/Features.

D’autres modules “Features” historiques existent (Wifi, Imprimantes, RDP, etc.), mais ils n’ont pas encore tous été complètement migrés dans la nouvelle architecture.

---

## 2. Logging – `MW.Logging.psm1`

### 2.1. Résumé fonctionnel

Le module de logging fournit :

- `Initialize-MWLogging`  
  - Crée le dossier `.\Logs` s’il n’existe pas.  
  - Crée un fichier de log daté : `MigrationWizard_YYYY-MM-DD.log`.  
  - Stocke le chemin dans une variable globale (via `$script:`).

- `Write-MWLog`  
  - Écrit une ligne dans le fichier de log avec :
    - horodatage,
    - niveau (`INFO`, `WARN`, `ERROR`, `DEBUG`),
    - message.
  - Utilise `Add-Content` pour ajouter les lignes.

- Helpers :  
  - `Write-MWLogInfo`, `Write-MWLogWarn`, `Write-MWLogError`, `Write-MWLogDebug`.

### 2.2. Robustesse / erreurs connues

- Si le module Logging n’est pas chargé, certains Core (Applications, DataFolders…) utilisent un helper `Test-MWLogAvailable` + `Write-MWLogSafe` pour **ne jamais casser le script juste à cause du log**.
- Cas connu :  
  Si le fichier de log est verrouillé (Notepad ouvert, antivirus, etc.), `Add-Content` peut lever une `IOException`.  
  → L’export/import continue quand même, mais des erreurs de log peuvent apparaître dans la console.  
  C’est **un point à améliorer plus tard** (gestion de file lock, fallback sur un fichier secondaire, etc.).

---

## 3. Export snapshot – `Export.psm1`

### 3.1. Objectif

Mettre en place une **métadonnée centrale** de l’export sous forme d’un fichier JSON (le “snapshot”), qui décrit :

- les chemins utilisés par l’export,
- les éléments détectés (applications, données, etc.),
- le contexte de la machine / utilisateur.

Le snapshot sert de **référence unique** pour l’interface graphique et pour l’import.

### 3.2. Fonctions principales

- `Save-MWExportSnapshot -Path <fichier.json>`  
  - Analyse la machine / profil, construit un objet avec :
    - `MachineName`, `UserName`, `UserProfilePath`, etc.
    - `Timestamp` de génération.
    - `Applications` : liste des applications retournées par `Get-MWApplicationsForExport`.
    - `Paths` : sous-objet contenant tous les chemins importants.
  - Sérialise cet objet en JSON dans le fichier donné.

- `Import-MWExportSnapshot -Path <fichier.json>`  
  - Recharge le snapshot JSON depuis le disque et le renvoie sous forme d’objet PowerShell.

### 3.3. Structure actuelle du snapshot

Le snapshot contient notamment une section `Paths` (récente) :

- `ExportRoot`  
  Racine logique de l’export (par exemple `.\Logs` ou le dossier choisi par l’utilisateur).

- `SnapshotPath`  
  Chemin du fichier snapshot lui-même (auto-référence pratique).

- `ApplicationsManifestPath`  
  Chemin préparé pour un futur manifest des applications  
  (exemple : `.\Logs\Applications\applications.json`).

- `UserDataRoot`  
  Dossier racine où seront exportées les données utilisateur  
  (exemple : `.\Logs\UserData`).

- `DataFoldersManifestPath`  
  Chemin du manifest JSON décrivant les dossiers utilisateur  
  (exemple : `.\Logs\UserData\DataFolders.manifest.json`).

Ces chemins sont **déjà présents dans le snapshot** et utilisés par `DataFolders.psm1`.

---

## 4. Applications – `Applications.psm1`

### 4.1. Rôle

Ce module gère la partie **applications installées** sur le poste, avec une logique de filtrage pour obtenir une liste propre à afficher à l’utilisateur ou à exploiter pour un futur match RuckZuck.

### 4.2. Fonctions existantes

- `Get-MWInstalledApplications`  
  - Parcourt les clés Registre habituelles (Uninstall 32 bits / 64 bits).  
  - Construit une liste d’applications avec :  
    `Name`, `Version`, `Publisher`, `InstallLocation`, `UninstallString`, etc.

- `Get-MWApplicationsForExport`  
  - Part de la liste brute,
  - Filtre :
    - les entrées vides / corrompues,
    - les composants système (`SystemComponent`),
    - les mises à jour / hotfix,
  - Évite les doublons (Name + Version),
  - Retourne une liste “propre” destinée à être stockée dans le snapshot.

- `Get-MWMissingApplicationsFromExport`  
  - Compare une export list d’applications (ex: provenant d’un autre poste) avec les applis présentes localement,  
  - Retourne la liste des applis manquantes, pour aider à la phase “réinstallation”.

### 4.3. Intégration avec le snapshot

- `Save-MWExportSnapshot` appelle déjà `Get-MWApplicationsForExport` et stocke la liste dans la propriété `Applications` du snapshot.
- Un chemin `ApplicationsManifestPath` est prévu dans `Paths` pour, plus tard, éventuellement écrire un fichier JSON séparé pour les applications.  
  → La mécanique de base est prête, il restera à brancher le manifest d’applications si on le décide.

---

## 5. Données utilisateur – `DataFolders.psm1`

Ce module remplace progressivement le code brut de l’ancien script pour tout ce qui est **Bureau / Documents / Images / etc.**

### 5.1. Dossiers gérés

La liste par défaut (fonction `Get-MWDefaultDataFolders`) contient :

- `Desktop`    → Bureau  
- `Documents`  → Documents  
- `Downloads`  → Téléchargements  
- `Pictures`   → Images  
- `Music`      → Musique  
- `Videos`     → Vidéos  
- `Favorites`  → Favoris  
- `Links`      → Liens  
- `Contacts`   → Contacts  

Pour chaque entrée :

- `Key` : identifiant logique (ex: `Desktop`)  
- `RelativePath` : nom du sous-dossier dans le profil (ex: `Desktop`)  
- `Label` : libellé lisible (ex: `Bureau`)  
- `Include` : booléen “inclus par défaut”.

### 5.2. Manifest des dossiers – construction et sauvegarde

Fonctions :

- `New-MWDataFoldersManifest`  
  - Part du profil utilisateur (par défaut `$env:USERPROFILE`).  
  - Pour chaque dossier par défaut :
    - calcule `SourcePath` (ex: `C:\Users\jmthomas\Desktop`),
    - teste s’il existe vraiment (`Exists`),
    - construit un objet avec :  
      `Key`, `Label`, `RelativePath`, `SourcePath`, `Exists`, `Include`.

- `Save-MWDataFoldersManifest -ManifestPath ...`  
  - Construit le manifest via `New-MWDataFoldersManifest`.  
  - Crée le dossier cible si besoin.  
  - Sérialise le manifest en JSON (`UTF8`) dans  
    `DataFolders.manifest.json` (ou autre chemin donné).

- `Get-MWDataFoldersManifest -ManifestPath ...`  
  - Relit le JSON, gère les erreurs de parsing,  
  - Renvoie un tableau d’objets manifest.

Ce manifest est destiné à être stocké au chemin indiqué par `Paths.DataFoldersManifestPath` dans le snapshot.

### 5.3. Export des données – `Export-MWDataFolders`

- Paramètres :
  - `ManifestPath` : JSON créé par `Save-MWDataFoldersManifest`.  
  - `DestinationRoot` : racine d’export (ex: `.\Logs\UserData`).

- Comportement :
  - Charge le manifest.
  - Pour chaque dossier :
    - ignore si `Include = $false`,
    - ignore si `SourcePath` vide ou inexistant,
    - crée le dossier destination (ex: `.\Logs\UserData\Desktop`),
    - lance `robocopy` avec :
      - `/E` (sous-dossiers, y compris vides),
      - `/COPY:DAT` (données + attributs + timestamps, sans ACL),
      - retries `/R:2`, `/W:5`,
      - options silencieuses (`/NFL /NDL /NP /NJH /NJS`).

- Intègre la gestion `SupportsShouldProcess` → possibilité d’utiliser `-WhatIf` pour simuler.

### 5.4. Import des données – `Import-MWDataFolders`

- Paramètres :
  - `ManifestPath` : le même manifest.  
  - `SourceRoot` : racine de l’export (ex: `.\Logs\UserData`).

- Comportement :
  - Vérifie que `SourceRoot` existe.
  - Recharge le manifest.
  - Reconstruit un manifest pour le **profil courant** afin d’avoir les bons chemins cibles (en utilisant `New-MWDataFoldersManifest`).
  - Mappe les dossiers par `Key` (Desktop, Documents, etc.).
  - Pour chaque entrée incluse :
    - source = `SourceRoot\RelativePath` (ex: `.\Logs\UserData\Desktop`),
    - destination = chemin réel du profil courant (ex: `C:\Users\nouvel.utilisateur\Desktop`),
    - crée le dossier cible si nécessaire,
    - lance `robocopy` avec les mêmes options que pour l’export.

- Supporte aussi `-WhatIf` via `SupportsShouldProcess`.

### 5.5. Sélection interactive – `Show-MWDataFoldersExportPlan`

Fonction dédiée au mode “je choisis ce que j’exporte” :

- Paramètres :
  - `ManifestPath`
  - `DestinationRoot`

- Étapes :
  1. Si le manifest n’existe pas, il est généré via `Save-MWDataFoldersManifest`.
  2. Charge le manifest.
  3. Affiche les dossiers dans un `Out-GridView` (Key, Label, SourcePath, RelativePath, Exists, Include).
  4. L’utilisateur sélectionne les dossiers à exporter.
  5. La propriété `Include` est mise à jour en fonction de la sélection.
  6. Le manifest est resauvegardé.
  7. L’export réel est lancé via `Export-MWDataFolders` (sans `-WhatIf`).

Une fonction symétrique `Show-MWDataFoldersImportPlan` est prévue / en cours pour l’import (même logique de vue interactive).

---

## 6. Profile – `Profile.psm1`

Ce module vise à remplacer le “gros script” en apportant une **orchestration claire** de l’export/import de profil.

### 6.1. Export du profil – `Export-MWProfile`

Signature actuelle :

```powershell
Export-MWProfile `
    -DestinationFolder <string> `
    -IncludeUserData        $true `
    -IncludeWifi            $true `
    -IncludePrinters        $true `
    -IncludeNetworkDrives   $true `
    -IncludeRdp             $true `
    -IncludeBrowsers        $true `
    -IncludeOutlook         $true `
    -IncludeWallpaper       $true `
    -IncludeDesktopLayout   $true `
    -IncludeTaskbarStart    $true `
    -UseDataFoldersManifest $false
````

* Chaque `IncludeXxx` permet d’activer/désactiver une brique (comme dans le script historique).
* **Nouveau :** `UseDataFoldersManifest` choisit le mode de gestion des données utilisateur :

#### Bloc données utilisateur (nouvelle version)

* Si `IncludeUserData = $true` :

  * si `UseDataFoldersManifest = $true` :

    * `Profile\` devient la racine des données utilisateur exportées.
    * `DataFolders.manifest.json` est utilisé pour piloter les copies.
    * Appel de `Show-MWDataFoldersExportPlan` → sélection interactive des dossiers, puis export.
  * sinon :

    * Comportement historique : appel de `Export-MWUserData -DestinationFolder $DestinationFolder`.

Le reste de `Export-MWProfile` (Wifi, Imprimantes, etc.) suit encore la logique du script d’origine, mais progressivement l’idée est de rediriger ces parties vers les modules dédiés (Wifi, Printers, etc.).

### 6.2. Import du profil – `Import-MWProfile`

Signature actuelle :

```powershell
Import-MWProfile `
    -SourceFolder <string> `
    -IncludeUserData        $true `
    -IncludeWifi            $true `
    -IncludePrinters        $true `
    -IncludeNetworkDrives   $true `
    -IncludeRdp             $true `
    -IncludeBrowsers        $true `
    -IncludeOutlook         $true `
    -IncludeWallpaper       $true `
    -IncludeDesktopLayout   $true `
    -IncludeTaskbarStart    $true `
    -UseDataFoldersManifest $false
```

* Même logique :

  * chaque `IncludeXxx` contrôle une brique,
  * `UseDataFoldersManifest` choisit d’utiliser ou non la mécanique `DataFolders`.

#### Bloc données utilisateur (nouvelle version)

* Si `IncludeUserData = $true` :

  * si `UseDataFoldersManifest = $true` :

    * `DataFolders.manifest.json` dans le dossier source est chargé.
    * Appel de `Show-MWDataFoldersImportPlan` (vue interactive source → cible), puis import réel via `Import-MWDataFolders`.
  * sinon :

    * appel de `Import-MWUserData -SourceFolder $SourceFolder` (comportement historique).

Cette brique a déjà été testée :

* en “mode DataFolders only” (tout le reste désactivé),
* avec export + import sur la même machine,
* en utilisant `Out-GridView` pour sélectionner les dossiers lors de l’export.

---

## 7. Tests déjà réalisés

Quelques scénarios déjà joués à la main (sans UI WPF) :

1. **Test du snapshot seul**

   * `Save-MWExportSnapshot -Path .\Logs\test_export_snapshot.json`
   * `Import-MWExportSnapshot -Path .\Logs\test_export_snapshot.json`
   * Vérification de :

     * `Paths.ExportRoot`, `Paths.UserDataRoot`, `Paths.DataFoldersManifestPath`,
     * contenus de `Applications`.

2. **Test DataFolders (ligne de commande)**

   * Génération manifest :

     * `Save-MWDataFoldersManifest -ManifestPath .\Logs\UserData\DataFolders.manifest.json`
   * Simulation d’export :

     * `Export-MWDataFolders -ManifestPath ... -DestinationRoot ... -WhatIf`
   * Simulation d’import :

     * `Import-MWDataFolders -ManifestPath ... -SourceRoot ... -WhatIf`

3. **Test DataFolders interactif (sans passer par Profile)**

   * `Show-MWDataFoldersExportPlan -ManifestPath ... -DestinationRoot ...`
   * `Import-MWDataFolders -ManifestPath ... -SourceRoot ... -WhatIf`

4. **Test Profile “UserData only” avec DataFolders**

   * Modules chargés :

     * `MW.Logging.psm1`, `DataFolders.psm1`, `Profile.psm1`.

   * Export :

     ```powershell
     Export-MWProfile `
         -DestinationFolder      'C:\Temp\MigrationTest' `
         -UseDataFoldersManifest $true `
         -IncludeWifi            $false `
         -IncludePrinters        $false `
         -IncludeNetworkDrives   $false `
         -IncludeRdp             $false `
         -IncludeBrowsers        $false `
         -IncludeOutlook         $false `
         -IncludeWallpaper       $false `
         -IncludeDesktopLayout   $false `
         -IncludeTaskbarStart    $false
     ```

   * Import :

     ```powershell
     Import-MWProfile `
         -SourceFolder           'C:\Temp\MigrationTest' `
         -UseDataFoldersManifest $true `
         -IncludeWifi            $false `
         -IncludePrinters        $false `
         -IncludeNetworkDrives   $false `
         -IncludeRdp             $false `
         -IncludeBrowsers        $false `
         -IncludeOutlook         $false `
         -IncludeWallpaper       $false `
         -IncludeDesktopLayout   $false `
         -IncludeTaskbarStart    $false
     ```

   * Résultat :

     * La mécanique DataFolders (manifest + export/import) est fonctionnelle.
     * Les erreurs restantes observées dans certains essais étaient liées :

       * soit au module Logging (fichier de log verrouillé),
       * soit à des Features non chargées (Wifi, Imprimantes…) lorsqu’on n’avait pas mis les `IncludeXxx` à `$false`.

---

## 8. Résumé rapide de l’avancement

* ✅ **Logging centralisé** – en place, utilisé par les nouveaux modules (avec helpers “Safe”).
* ✅ **Snapshot d’export** – existe, avec section `Paths` structurée, liste d’applications, métadonnées machine/utilisateur.
* ✅ **Module Applications** – collecte propre des applis, prêt pour intégration UI / RuckZuck.
* ✅ **Module DataFolders** – manifest JSON, export/import via `robocopy`, sélection interactive avec `Out-GridView`.
* ✅ **Profile (UserData)** – branché sur DataFolders via `UseDataFoldersManifest`.
* 🔁 **Autres Features (Wifi, Imprimantes, RDP, etc.)** – encore partiellement liées au code historique, à refondre / reconnecter proprement à la nouvelle architecture.
* 🔁 **UI WPF** – non encore réintégrée dans cette nouvelle structure modulaire, à reprendre proprement.

Ce document sert de base de vérité pour le **“déjà fait”**.
Les prochains fichiers `.md` détailleront :

* ce qu’il reste à migrer depuis l’ancien script,
* le backlog des features,
* la roadmap de refonte (Core, Features, UI).

```

---

