

---



\## 2) Contenu à coller dans `MW-Test-Scenarios.md`



````markdown

\# MigrationWizard – Scénarios de test



Ce document décrit des \*\*scénarios de test concrets\*\* pour valider pas à pas MigrationWizard :



\- d’abord le \*\*cœur\*\* (logging, snapshot, DataFolders),

\- ensuite les \*\*features\*\* (Wifi, imprimantes, etc.) au fur et à mesure qu’elles seront recodées,

\- et enfin les tests de bout en bout \*\*ancien PC → nouveau PC\*\*.



L’idée : chaque fois que tu modifies le code, tu peux piocher ici un scénario rapide pour vérifier que tout tient la route.



---



\## 1. Préparation commune pour les tests en PowerShell



Tous les scénarios qui suivent partent du principe que tu es dans le repo GitHub, et que tu travailles \*\*en ligne de commande\*\*.



\### 1.1. Se placer dans le dossier du projet



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

````



\### 1.2. Charger le logging + initialiser



```powershell

Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging

```



\### 1.3. Charger les modules nécessaires



Pour tester le cœur export/profil + dossiers utilisateur :



```powershell

Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking

```



Plus tard, quand les features seront recodées, on ajoutera :



```powershell

\# Exemple plus tard :

\# Import-Module .\\src\\Features\\Wifi.psm1       -Force -DisableNameChecking

\# Import-Module .\\src\\Features\\Printers.psm1   -Force -DisableNameChecking

\# Import-Module .\\src\\Features\\NetworkDrives.psm1 -Force -DisableNameChecking

\# ...

```



---



\## 2. Scénario A – Test basique des DataFolders (export/import local)



\*\*Objectif :\*\* vérifier que :



\* le manifest DataFolders est généré,

\* la sélection via la grille fonctionne,

\* l’export et l’import tournent bien sur la même machine.



\### 2.1. Choisir un répertoire d’export de test



```powershell

$dest = 'C:\\Temp\\MigrationTest'

```



\### 2.2. Export profil – mode DataFolders, uniquement données utilisateur



On désactive toutes les features non encore recodées, et on teste juste DataFolders :



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



Attendu :



\* Une fenêtre \*\*Out-GridView\*\* s’ouvre avec les dossiers (Bureau, Documents, etc.).

\* Tu coches ceux que tu veux exporter, valides.

\* Dans `$dest`, tu dois retrouver :



&nbsp; \* un manifest `DataFolders.manifest.json`,

&nbsp; \* un sous-dossier `Profile\\Desktop`, `Profile\\Documents`, etc. selon ta sélection.



\### 2.3. Import profil – mode DataFolders sur la même machine



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



Attendu :



\* Les fichiers présents dans `Profile\\Desktop` doivent se retrouver sur le \*\*Bureau\*\* actuel,

\* Même chose pour `Documents`, `Images`, etc. selon ta sélection,

\* Les logs (`Logs\\MigrationWizard\_YYYY-MM-DD.log`) doivent montrer les copies `Export-MWDataFolders` / `Import-MWDataFolders` et les dossiers concernés.



---



\## 3. Scénario B – Validation du snapshot d’export



\*\*Objectif :\*\* confirmer que `Save-MWExportSnapshot` et `Import-MWExportSnapshot` fonctionnent bien, et que les chemins utilisés par DataFolders passent bien par ce snapshot.



\### 3.1. Générer un snapshot de test



```powershell

$exportPath = ".\\Logs\\test\_export\_snapshot.json"



Save-MWExportSnapshot -Path $exportPath



$snap = Import-MWExportSnapshot -Path $exportPath

$snap.Paths

```



Attendu :



\* `$snap.Paths` contient au moins :



&nbsp; \* `ExportRoot`

&nbsp; \* `UserDataRoot`

&nbsp; \* `DataFoldersManifestPath`

&nbsp; \* `ApplicationsManifestPath` (et autres champs selon l’implémentation).



\### 3.2. Utiliser le snapshot avec DataFolders



```powershell

$manifestPath = $snap.Paths.DataFoldersManifestPath

$userDataRoot = $snap.Paths.UserDataRoot



\# 1) Générer le manifest DataFolders

Save-MWDataFoldersManifest -ManifestPath $manifestPath



\# 2) Export en simulation (WhatIf)

Export-MWDataFolders -ManifestPath $manifestPath -DestinationRoot $userDataRoot -WhatIf



\# 3) Import en simulation (WhatIf)

Import-MWDataFolders -ManifestPath $manifestPath -SourceRoot $userDataRoot -WhatIf

```



Attendu :



\* `WhatIf` affiche les opérations qui \*\*seraient\*\* faites (création dossiers + copies),

\* Aucun fichier n’est réellement copié,

\* Les logs tracent les actions avec le flag “WhatIf” / ShouldProcess.



---



\## 4. Scénario C – Migrations réelles entre deux comptes sur la même machine



\*\*Objectif :\*\* simuler une “migration PC → PC” en restant sur la même machine :



1\. Tu te connectes avec un premier utilisateur (UserA),

2\. Tu fais un export,

3\. Tu te connectes avec un autre utilisateur (UserB),

4\. Tu fais l’import.



\### 4.1. Depuis le profil source (UserA)



\* Crée quelques fichiers tests :



&nbsp; \* sur le Bureau : `Test\_A\_Bureau.txt`,

&nbsp; \* dans Documents : `Test\_A\_Documents.txt`.



\* Ensuite, lance l’export :



```powershell

$dest = 'C:\\Temp\\MigrationTest-UserA'



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



\* Coche au moins \*\*Bureau\*\* et \*\*Documents\*\* dans la grille.



\### 4.2. Depuis le profil cible (UserB)



\* Ouvre une session avec \*\*un autre utilisateur\*\* (vrai autre profil).

\* Copie le dossier d’export si besoin (ou garde le même chemin si commun).



Puis :



```powershell

cd "C:\\Users\\<UserB>\\Documents\\Creation\\MigrationWizard\\Github"   # adapter si besoin



Import-Module .\\src\\Modules\\MW.Logging.psm1 -Force -DisableNameChecking

Initialize-MWLogging

Import-Module .\\src\\Core\\Export.psm1      -Force -DisableNameChecking

Import-Module .\\src\\Core\\DataFolders.psm1 -Force -DisableNameChecking

Import-Module .\\src\\Core\\Profile.psm1     -Force -DisableNameChecking



$dest = 'C:\\Temp\\MigrationTest-UserA'   # même dossier d’export que précédemment



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



Attendu :



\* Sur le \*\*Bureau\*\* de UserB, tu retrouves `Test\_A\_Bureau.txt`,

\* Dans \*\*Documents\*\* de UserB : `Test\_A\_Documents.txt`,

\* Le tout sans écraser autre chose que ce que tu as décidé.



---



\## 5. Scénarios futurs pour les modules “Features”



> À remplir au fur et à mesure du recodage des modules Wifi, Imprimantes, etc.



\### 5.1. Wifi – scénario de base (à écrire quand le module sera prêt)



Objectif :



\* Tester l’export/import de profils Wifi simples.



Esquisse de scénario :



\* Créer un profil Wifi test sur la machine (SSID dédié),

\* Exporter le profil avec `IncludeWifi = $true`,

\* Supprimer le profil Wifi,

\* Réimporter via `Import-MWProfile`,

\* Vérifier que le réseau Wifi est de nouveau présent et connectable.



\### 5.2. Imprimantes – scénario de base



Objectif :



\* Exporter les imprimantes + imprimante par défaut, puis les restaurer.



Esquisse :



\* Installer 2–3 imprimantes logiques, en mettre une en défaut,

\* Exporter `IncludePrinters = $true`,

\* Supprimer les imprimantes,

\* Réimporter,

\* Vérifier que :



&nbsp; \* les imprimantes sont recréées,

&nbsp; \* la bonne imprimante est par défaut.



\### 5.3. Lecteurs réseaux / RDP / Navigateurs / Outlook



Pour chaque module :



\* Définir un \*\*jeu de données simple\*\* (1 ou 2 entrées),

\* Faire un scénario “export → suppression → import → vérification”,

\* Documenter ici les chemins, commandes et points à vérifier.



---



\## 6. Tests “de bout en bout” (PC source → PC cible)



Quand les features principales seront recodées, prévoir un gros test :



1\. \*\*PC source\*\* (ancien poste utilisateur) :



&nbsp;  \* Lancer un export complet avec un preset (ex : tout sauf trucs lourds),

&nbsp;  \* Sauvegarder l’export sur un support externe (USB, partage réseau…).



2\. \*\*PC cible\*\* (nouveau poste) :



&nbsp;  \* Lancer l’import complet,

&nbsp;  \* Vérifier :



&nbsp;    \* données utilisateur,

&nbsp;    \* Wifi,

&nbsp;    \* lecteurs réseaux,

&nbsp;    \* imprimantes,

&nbsp;    \* RDP,

&nbsp;    \* navigateurs,

&nbsp;    \* Outlook,

&nbsp;    \* apparence (si activée),

&nbsp;    \* éventuelles apps spécifiques.



3\. Noter :



&nbsp;  \* ce qui fonctionne nickel,

&nbsp;  \* ce qui casse / manque,

&nbsp;  \* ce qui doit être amélioré (perf, UX, logs…).



Ce test pourra faire l’objet d’un compte-rendu séparé (ou d’une section dans ce fichier).



---



```



---





