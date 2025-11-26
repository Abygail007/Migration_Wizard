

\## 1) Commandes PowerShell pour créer / ouvrir le fichier



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



New-Item -ItemType Directory -Path .\\docs -Force | Out-Null

New-Item -ItemType File      -Path .\\docs\\MW-Dev-Env-And-Tests.md -Force | Out-Null



notepad .\\docs\\MW-Dev-Env-And-Tests.md

```



Ensuite tu colles le contenu ci-dessous dans `MW-Dev-Env-And-Tests.md`.



---



\## 2) Contenu à coller dans `MW-Dev-Env-And-Tests.md`



````markdown

\# MigrationWizard – Environnement de dev \& commandes de test



Ce fichier explique comment :

\- lancer une \*\*session PowerShell de dev propre\*\*,

\- charger les modules nécessaires,

\- tester les \*\*snapshots\*\*, les \*\*DataFolders\*\* et le \*\*Profile\*\*,

\- gérer quelques \*\*pièges connus\*\* (logs verrouillés, modules non chargés, etc.).



---



\## 1. Pré-requis de base



\### 1.1. Version PowerShell



\- Cible principale : \*\*Windows PowerShell 5.1\*\*

&nbsp; - Compatibilité obligatoire (pas d’opérateur ternaire, pas de syntaxe exotique PS7).

\- PowerShell 7 peut être utilisé pour dev, mais le code doit rester exécutable en 5.1.



\### 1.2. Structure du repo (simplifiée)



Quelques dossiers importants :



\- `src\\Core\\`

&nbsp; - `Export.psm1` : snapshot, chemins, logique d’export global.

&nbsp; - `Profile.psm1` : orchestration export/import du profil (toutes briques).

&nbsp; - `DataFolders.psm1` : manifest des dossiers utilisateur, export/import interactifs.

\- `src\\Modules\\`

&nbsp; - `MW.Logging.psm1` : logging centralisé.

&nbsp; - (à compléter plus tard avec d’autres modules cross-cutting si besoin)

\- `src\\Features\\`

&nbsp; - Wifi, Imprimantes, RDP, etc. (à développer / refactoriser proprement).



---



\## 2. Démarrer une session de dev propre



Depuis une console PowerShell (en admin conseillé) :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

````



\### 2.1. Charger le logging + initialisation



```powershell

Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging

```



> `Initialize-MWLogging` crée le dossier `.\\Logs` (si besoin) et le fichier log du jour

> `Logs\\MigrationWizard\_YYYY-MM-DD.log`.



\### 2.2. Charger les modules Core indispensables



Pour travailler sur snapshot / DataFolders / Profile :



```powershell

Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking

```



Plus tard, quand les modules Features existeront, on ajoutera par exemple :



```powershell

Import-Module .\\src\\Features\\Wifi.psm1        -Force -DisableNameChecking

Import-Module .\\src\\Features\\Printers.psm1    -Force -DisableNameChecking

Import-Module .\\src\\Features\\NetworkDrives.psm1 -Force -DisableNameChecking

\# etc.

```



---



\## 3. Tests – Snapshots \& DataFolders



\### 3.1. Générer un snapshot d’export



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



$exportPath = ".\\Logs\\test\_export\_snapshot\_rz.json"



Save-MWExportSnapshot -Path $exportPath



$snap = Import-MWExportSnapshot -Path $exportPath

$snap.Paths | Format-List \*

```



On vérifie que les chemins clés sont bien remplis, par ex. :



\* `ExportRoot`

\* `UserDataRoot`

\* `DataFoldersManifestPath`

\* `ApplicationsManifestPath`

\* etc.



\### 3.2. Générer le manifest des dossiers utilisateur



```powershell

$manifestPath = $snap.Paths.DataFoldersManifestPath

$userDataRoot = $snap.Paths.UserDataRoot



Save-MWDataFoldersManifest -ManifestPath $manifestPath

```



Optionnel : ouvrir le fichier pour vérifier son contenu.



```powershell

notepad $manifestPath

```



On doit y voir un tableau JSON du type :



\* `Desktop`, `Documents`, `Downloads`, `Pictures`, `Music`, `Videos`, `Favorites`, `Links`, `Contacts`

\* avec les champs `Key`, `Label`, `RelativePath`, `SourcePath`, `Exists`, `Include`.



\### 3.3. Tester l’export des DataFolders (mode simulation)



```powershell

Export-MWDataFolders -ManifestPath $manifestPath -DestinationRoot $userDataRoot -WhatIf

```



On doit voir des lignes type :



\* `WhatIf : Opération "Créer un répertoire"...`

\* `WhatIf : Opération "Copie des données (export)" en cours sur la cible "C:\\Users\\xxx\\Desktop -> .\\Logs\\UserData\\Desktop".`



Rien n’est réellement copié grâce à `-WhatIf`.



\### 3.4. Tester l’import des DataFolders (mode simulation)



```powershell

Import-MWDataFolders -ManifestPath $manifestPath -SourceRoot $userDataRoot -WhatIf

```



On doit voir des lignes indiquant la copie \*\*source -> profil courant\*\* (toujours en mode simulé).



---



\## 4. Tests – Export / Import de profil avec DataFolders



Ces tests utilisent `Export-MWProfile` / `Import-MWProfile` avec le nouveau paramètre `UseDataFoldersManifest`.



\### 4.1. Export de profil – mode DataFolders, uniquement données utilisateur



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging



Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking



$dest = "C:\\Temp\\MigrationTest"



Export-MWProfile `

&nbsp;   -DestinationFolder      $dest `

&nbsp;   -UseDataFoldersManifest $true `

&nbsp;   -IncludeWifi            $false `

&nbsp;   -IncludePrinters        $false `

NOUVEAU :

&nbsp;   -IncludeNetworkDrives   $false `

&nbsp;   -IncludeRdp             $false `

&nbsp;   -IncludeBrowsers        $false `

&nbsp;   -IncludeOutlook         $false `

&nbsp;   -IncludeWallpaper       $false `

&nbsp;   -IncludeDesktopLayout   $false `

&nbsp;   -IncludeTaskbarStart    $false

```

## 5. Lancer l’UI WPF en environnement de dev

Cette section décrit **comment tester l’interface graphique** de MigrationWizard  
avec le nouveau système de logging + les options UserData / DataFolders.

### 5.1. Commande de lancement (avec logging)

Depuis une console PowerShell :

```powershell
cd "C:\Users\jmthomas\Documents\Creation\MigrationWizard\Github"

# 1) Logging
Import-Module .\src\Modules\MW.Logging.psm1 -Force -DisableNameChecking
Initialize-MWLogging

# 2) Lancer le point d’entrée principal (qui charge l’UI)
.\MigrationWizard.Main.ps1
```

Remarques :

- `Initialize-MWLogging` crée/alimente le fichier log sous `.\\Logs`.
- Tu peux ajouter un paramètre de type `-VerboseLog` si ton `Main` le supporte
  (pour voir davantage de traces pendant tes tests).

### 5.2. Utiliser l’UI pour tester UserData + DataFolders

Ce scénario complète les tests CLI décrits plus haut.

1. Créer un dossier d’export test, par exemple :  
   `C:\Temp\MigrationTest-UI`.
2. Lancer l’UI comme indiqué en 5.1.
3. Dans “Dossier d’export / import du profil”, choisir ce dossier.
4. Dans les cases à cocher :
   - cocher **“Données utilisateur (Documents / Bureau…)”**,
   - cocher **“Mode avancé dossiers (DataFolders)”**,
   - décocher les autres options (Wifi, imprimantes, etc.) pour se concentrer sur les données.
5. Cliquer sur **“Exporter le profil”** :  
   une fenêtre liée à DataFolders doit proposer la sélection des dossiers.
6. Après export, vérifier dans `C:\Temp\MigrationTest-UI` :
   - présence de `DataFolders.manifest.json`,
   - présence d’un dossier `Profile` avec les sous-dossiers (Desktop, Documents, …),
   - absence d’erreurs dans les logs.
7. Modifier quelques fichiers sur le Bureau / dans Documents (ou tester sur un autre poste).
8. Relancer l’UI, sélectionner le même dossier, cocher à nouveau UserData + DataFolders.
9. Cliquer sur **“Importer le profil”** et valider le plan d’import.

Effet attendu : les dossiers/fichiers sont restaurés correctement à partir du contenu exporté,  
et le log montre le passage par le mode DataFolders (Export + Import) sans erreur critique.



\* Création du manifest `DataFolders.manifest.json` dans le dossier d’export.

\* Affichage d’une fenêtre \*\*Out-GridView\*\* pour choisir les dossiers à inclure.

\* Copie des dossiers sélectionnés vers un sous-dossier (ex. `Profile\\Desktop`, `Profile\\Documents`, etc.) via `Export-MWDataFolders`.



\### 4.2. Import de profil – mode DataFolders, uniquement données utilisateur



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



Effet attendu :



\* Utilisation du même `DataFolders.manifest.json` pour savoir quoi importer.

\* Reconstruction des chemins cibles du profil courant (Desktop, Documents, etc.) via `New-MWDataFoldersManifest`.

\* Copie des données depuis l’export vers ces dossiers.



> Note : tant que les modules Features (Wifi, Imprimantes, etc.) ne sont pas implémentés/importés, il est recommandé de \*\*laisser leurs flags à `$false`\*\* pour éviter les erreurs “fonction introuvable”.



---



\## 5. Problèmes connus / Tips



\### 5.1. Fichier de log verrouillé



Symptôme :



\* Erreurs répétées :

&nbsp; `Le processus ne peut pas accéder au fichier '...\\Logs\\MigrationWizard\_YYYY-MM-DD.log', car il est en cours d'utilisation par un autre processus.`



Causes possibles :



\* Le fichier est ouvert dans un éditeur qui locke en écriture (certains éditeurs peuvent le faire).

\* Une autre session PowerShell est en train d’écrire dans le même log.



Contournement rapide :



\* Fermer les éditeurs qui ont le log ouvert.

\* Éviter de lancer plusieurs sessions dev en parallèle qui loggent toutes au même endroit.

\* En cas de doute, supprimer/renommer le fichier log (il sera recréé) :



&nbsp; ```powershell

&nbsp; Remove-Item .\\Logs\\MigrationWizard\_\*.log

&nbsp; Initialize-MWLogging

&nbsp; ```



\### 5.2. Erreurs “Write-MWLogError non reconnu”



Symptôme :



\* `Write-MWLogError : Le terme «Write-MWLogError» n'est pas reconnu...`



Solution :



\* S’assurer que le module `MW.Logging.psm1` est bien importé \*\*avant\*\* `Profile.psm1` :



&nbsp; ```powershell

&nbsp; Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

&nbsp; Initialize-MWLogging



&nbsp; Import-Module .\\src\\Core\\Profile.psm1 -Force -DisableNameChecking

&nbsp; ```



\### 5.3. Erreurs sur les features non implémentées



Symptôme :



\* Messages du type :

&nbsp; `Le terme 'Export-MWWifiProfiles' n'est pas reconnu...`



Ca veut simplement dire que le module correspondant (Wifi, Printers, etc.) n’est pas encore en place/importé.



Contournement :



\* Laisser les options correspondantes à `$false` :



&nbsp; \* `-IncludeWifi $false`

&nbsp; \* `-IncludePrinters $false`

&nbsp; \* `-IncludeNetworkDrives $false`

&nbsp; \* `-IncludeRdp $false`

&nbsp; \* `-IncludeBrowsers $false`

&nbsp; \* `-IncludeOutlook $false`



---



\## 6. Routine type pour une nouvelle session de dev



Petit mémo pour repartir rapidement sur une session propre :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



\# 1) Logging

Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging



\# 2) Core

Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking



\# 3) (plus tard) Features

\# Import-Module .\\src\\Features\\Wifi.psm1        -Force -DisableNameChecking

\# Import-Module .\\src\\Features\\Printers.psm1    -Force -DisableNameChecking

\# etc.



\# 4) Dossier d’export de test

$dest = "C:\\Temp\\MigrationTest"



\# 5) Test export / import profil (mode DataFolders, seulement user data)

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




## 6. Mode CLI (sans UI) – Export / Import direct

En plus de l'interface graphique, MigrationWizard peut être lancé en **mode ligne de commande**  
pour faire un export ou un import complet sans ouvrir la WPF.

### 6.1. Export simple

```powershell
cd "C:\Users\jmthomas\Documents\Creation\MigrationWizard\Github"

.\MigrationWizard.Main.ps1 -ExportPath "C:\Temp\MigrationTestCLI"





