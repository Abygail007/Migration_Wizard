



\## 2. Contenu à coller dans `MW-Collaboration-Guidelines.md`



````markdown

\# MigrationWizard – Règles de collaboration avec l’assistant



Ce document décrit \*\*comment l’assistant doit répondre\*\* pour ce projet MigrationWizard, afin que tout soit :

\- reproductible,

\- précis,

\- facile à suivre dans l’historique GitHub.



---



\## 1. Règles générales



\- Langue des réponses : \*\*français\*\*.

\- Ton : \*\*décontracté mais pas familier\*\*, clair et direct.

\- Objectif : toujours donner des réponses \*\*prêtes à copier-coller\*\* (scripts, commandes, contenu de fichiers, etc.).

\- Ne pas “inventer” l’architecture : respecter en priorité \*\*l’arborescence actuelle du repo\*\*.



---



\## 2. Règles pour les fichiers code / .psm1 / .ps1



\### 2.1. Toujours donner les commandes `notepad` (et `New-Item` si besoin)



Pour \*\*chaque fichier modifié ou créé\*\*, l’assistant doit d’abord donner les commandes PowerShell pour ouvrir le fichier, par exemple :



\- Pour un fichier déjà existant :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

notepad .\\src\\Core\\Profile.psm1

````



\* Pour un \*\*nouveau fichier\*\* :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

New-Item -ItemType File -Path .\\src\\Core\\NouveauModule.psm1 -Force | Out-Null

notepad .\\src\\Core\\NouveauModule.psm1

```



Ensuite seulement, l’assistant donne le \*\*contenu à coller\*\* dans le fichier.



---



\### 2.2. Format des modifications : blocs ANCIEN / NOUVEAU



Quand on modifie du code existant, l’assistant doit \*\*toujours\*\* fournir des \*\*patchs précis\*\*, sous la forme :



\* Un bloc `ANCIEN` avec \*\*1 à 5 lignes d’ancrage\*\* (pas besoin du fichier complet).

\* Un bloc `NOUVEAU` qui remplace exactement ce bloc.



Exemple attendu :



```text

ANCIEN (Profile.psm1 – début de Export-MWProfile)



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

&nbsp;       \[bool]$IncludeTaskbarStart       = $true

&nbsp;   )

```



```text

NOUVEAU (Profile.psm1 – début de Export-MWProfile)



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

```



\*\*Important :\*\*



\* Pas de “à peu près” : le bloc `NOUVEAU` doit être \*\*copiable tel quel\*\*.

\* Ne pas mélanger plusieurs zones du fichier dans un seul patch si ce n’est pas nécessaire : 1 changement = 1 paire ANCIEN/NOUVEAU.



---



\### 2.3. Pas de fichier complet sauf demande explicite



\* Par défaut, l’assistant \*\*évite d’envoyer tout un fichier complet\*\*.

\* Il envoie uniquement :



&nbsp; \* les blocs \*\*ANCIEN / NOUVEAU\*\*,

&nbsp; \* ou le \*\*contenu complet d’un nouveau fichier\*\*.



Si Jean-Mickaël demande explicitement “donne-moi le fichier complet”, alors l’assistant peut le faire.



---



\### 2.4. Compatibilité PowerShell 5.1



Le projet doit rester \*\*100% compatible PowerShell 5.1\*\*.



L’assistant doit donc \*\*éviter\*\* :



\* L’opérateur ternaire : `? :`

\* Les nouveautés PS7+ :



&nbsp; \* opérateur `??`,

&nbsp; \* `.|` et autres opérateurs de pipeline avancés,

&nbsp; \* tout ce qui n’est pas supporté par Windows PowerShell 5.1.

\* Des syntaxes ambiguës du type `"$i:"` dans des chaînes interpolées.



Rappels :



\* Utiliser des `if` classiques.

\* Rester sur du PowerShell “classique” (PS 5.1).



---



\## 3. Règles pour les fichiers Markdown (.md)



Pour chaque nouveau `.md` :



1\. Donner les commandes pour créer / ouvrir le fichier :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

New-Item -ItemType File -Path .\\docs\\NomDuFichier.md -Force | Out-Null

notepad .\\docs\\NomDuFichier.md

```



2\. Ensuite, fournir un \*\*bloc unique\*\* :



````markdown

```markdown

\# Titre du document



Contenu...

````



````



(Jean-Mickaël copie-colle \*\*tout l’intérieur\*\* dans le fichier ouvert avec `notepad`.)



---



\## 4. Règles pour les commandes Git



Quand l’assistant propose des commandes Git, il doit :



\- \*\*Ne pas mettre de prompt\*\* style `PS C:\\...>` devant.

\- Donner uniquement les commandes, par exemple :



```powershell

cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"



git status

git add .

git commit -m "Message de commit clair"

git push

````



---



\## 5. Règles pour les tests / scénarios d’exécution



Quand l’assistant donne des commandes de test, il doit :



\* Partir du `cd` vers le repo :



&nbsp; ```powershell

&nbsp; cd "C:\\Users\\jmthomas\\Documents\\Creation\\MigrationWizard\\Github"

&nbsp; ```



\* Importer explicitement les modules nécessaires, par exemple :



&nbsp; ```powershell

&nbsp; Import-Module .\\src\\Modules\\MW.Logging.psm1   -Force -DisableNameChecking

&nbsp; Initialize-MWLogging



&nbsp; Import-Module .\\src\\Core\\DataFolders.psm1     -Force -DisableNameChecking

&nbsp; Import-Module .\\src\\Core\\Profile.psm1         -Force -DisableNameChecking

&nbsp; ```



\* Puis donner \*\*les commandes de test complètes\*\*, sans rien sous-entendre.



Exemple :



```powershell

$dest = 'C:\\Temp\\MigrationTest'



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



---



\## 6. En cas de divergence / incohérence



Si un futur chat propose des changements qui ne respectent pas ce document :



\* Ce document fait foi pour ce projet.

\* L’assistant doit \*\*s’aligner sur ces règles\*\*, même si un autre chat a dit autre chose.





