\# MigrationWizard – Vue d’ensemble du projet



\## 1. Contexte et objectif général



MigrationWizard est l’évolution propre et modulaire de mon ancien script PowerShell d’environ 3000 lignes, utilisé pour préparer et réaliser les migrations de postes (principalement vers Windows 10/11).



Objectif :  

– simplifier la migration du profil utilisateur et de son environnement (données, paramètres, applis, etc.)  

– limiter au maximum les manips manuelles pendant un changement de PC  

– avoir des exports/imports \*\*traçables\*\*, \*\*reproductibles\*\* et \*\*sécurisés\*\*  

– pouvoir être emballé ensuite dans un EXE avec une interface (WPF) pour utilisation par des techniciens.



Le projet est découpé en modules (Core, Features…), afin d’être plus structuré que le gros script d’origine.



---



\## 2. Fonctionnement global



MigrationWizard fonctionne autour de deux opérations principales :



1\. \*\*Export de profil\*\*  

&nbsp;  – On lance un export depuis l’ancien poste (ou le poste à remplacer).  

&nbsp;  – On choisit un dossier d’export (clé USB, disque externe, partage réseau…).  

&nbsp;  – Le script collecte les informations/données selon les options choisies.  

&nbsp;  – Le résultat est un dossier d’export structuré (profil, applis, config…), plus un snapshot JSON décrivant ce qui a été fait.



2\. \*\*Import de profil\*\*  

&nbsp;  – On lance l’import sur le nouveau poste, en pointant vers le dossier d’export.  

&nbsp;  – Le script restaure les données et la configuration pour \*\*l’utilisateur actuellement connecté\*\* (pas l’Administrator par défaut).  

&nbsp;  – L’import s’adapte : dossiers manquants, imprimantes non disponibles, lecteurs réseau invalides, etc. doivent être gérés proprement.



Toutes les actions importantes sont loguées dans un fichier de log avec timestamp, pour pouvoir diagnostiquer et rejouer en cas de problème.



---



\## 3. Export – ce que l’outil doit savoir sauvegarder



L’export est piloté principalement par la fonction `Export-MWProfile` avec plusieurs drapeaux (`IncludeUserData`, `IncludeWifi`, etc.).  

Le but final est d’avoir un \*\*profil d’export configurable\*\* : on coche/décoche ce qu’on veut emporter.



\### 3.1 Données utilisateur (profil)



But : sauvegarder les dossiers “classiques” du profil utilisateur.



Dossiers concernés (version actuelle du design) :

\- Bureau (`Desktop`)

\- Documents

\- Téléchargements (`Downloads`)

\- Images (`Pictures`)

\- Musique (`Music`)

\- Vidéos (`Videos`)

\- Favoris (`Favorites`)

\- Liens (`Links`)

\- Contacts (`Contacts`)



Deux modes sont prévus :



1\. \*\*Mode historique (legacy)\*\*  

&nbsp;  – Comportement du vieux script : export “brut” des dossiers du profil via `Export-MWUserData`.  

&nbsp;  – Pas de sélection fine dossier par dossier.  

&nbsp;  – Utilisé quand `UseDataFoldersManifest = $false`.



2\. \*\*Mode avancé “DataFolders” (nouveauté)\*\*  

&nbsp;  – Utilisation d’un manifest JSON décrivant chaque dossier (clé, label, chemin source, chemin relatif, Include, Exists...).  

&nbsp;  – Sélection interactive des dossiers à exporter via une grille (Out-GridView) : `Show-MWDataFoldersExportPlan`.  

&nbsp;  – Export réel ensuite via `Export-MWDataFolders` (robocopy) vers un sous-dossier de l’export (par ex. `Profile\\Desktop`, `Profile\\Documents`, etc.).  

&nbsp;  – Le manifest (`DataFolders.manifest.json`) pourra être réutilisé pour l’import, et plus tard par une UI WPF.  

&nbsp;  – Activé via le paramètre `UseDataFoldersManifest = $true` dans `Export-MWProfile`.



Ce mode avancé permet d’avoir un export \*\*plus propre et contrôlé\*\*, tout en conservant la compatibilité avec l’ancien comportement.



\### 3.2 Profils Wi-Fi



But : sauvegarder les profils Wi-Fi de la machine (SSID, type de sécurité, clé, etc.), dans la mesure du possible.



\- Export des profils Wi-Fi (type `netsh wlan show profile` ou équivalent).  

\- Stockage dans un format exploitable (XML / JSON).  

\- Option d’export activable via `IncludeWifi`.  

\- À la restauration, il faudra recréer les profils sur le nouveau poste.



\### 3.3 Imprimantes



But : éviter de recréer toutes les imprimantes à la main.



\- Inventaire des imprimantes installées pour l’utilisateur (et/ou le système).  

\- Sauvegarde du nom, type, pilote, port utilisé, imprimante par défaut.  

\- Option d’export `IncludePrinters`.  

\- À l’import : tentative de recréation des imprimantes (avec gestion des cas où le pilote n’est pas présent).



\### 3.4 Lecteurs réseau (mapping de lecteurs)



But : restaurer les lecteurs réseau de l’utilisateur.



\- Export de la liste des lecteurs réseau mappés (lettre, chemin UNC, options de reconnexion).  

\- Option `IncludeNetworkDrives`.  

\- À l’import : re-mappage des lecteurs, avec gestion des erreurs (chemin introuvable, credentials nécessaires, etc.).



\### 3.5 Connexions RDP



But : ne pas perdre les raccourcis / connexions RDP de l’utilisateur.



\- Export des fichiers RDP et/ou des connexions stockées (emplacements classiques dans le profil).  

\- Option `IncludeRdp`.  

\- À l’import : restauration des fichiers RDP au bon endroit.



\### 3.6 Navigateurs (favoris et configuration principale)



But : migrer les éléments essentiels de navigation.



\- Cibles principales : Edge, Chrome, Firefox (selon ce qui est installé).  

\- Export des favoris/marque-pages (et éventuellement d’autres éléments raisonnables : moteurs de recherche, page d’accueil, etc. – \*\*pas\*\* les mots de passe stockés ou alors sil y a un solution pour automatiser l'export des mot de passe de chaque navigateur a explorer).  

\- Option `IncludeBrowsers`.  

\- À l’import : injection/restauration des favoris à l’endroit attendu par chaque navigateur.



\### 3.7 Outlook



But : limiter la galère de configuration Outlook après migration.



\- Export des éléments suivants (en fonction de ce qui est techniquement faisable) :

&nbsp; - Profils Outlook (nom du profil, comptes associés).

&nbsp; - Signatures.

&nbsp; - Raccourcis/dossiers locaux utiles.

\- Option `IncludeOutlook`.  

\- À l’import : recréation du profil ou au minimum restauration des signatures et éléments configurables.



\### 3.8 Fond d’écran (wallpaper)



But : retrouver l’ambiance visuelle.



\- Export du chemin du fond d’écran et copie du fichier si besoin.  

\- Option `IncludeWallpaper`.  

\- À l’import : appliquer à nouveau le fond d’écran pour l’utilisateur courant.



\### 3.9 Disposition du bureau (icônes)



But : restaurer la disposition des icônes sur le Bureau.



\- Export de la disposition des icônes (position, taille, etc.) via la méthode que tu avais dans le script d’origine.  

\- Option `IncludeDesktopLayout`.  

\- À l’import : tentative de reconstitution de la disposition.



\### 3.10 Barre des tâches / menu Démarrer



But : retrouver les raccourcis importants.



\- Export de la configuration de la barre des tâches (applications épinglées, etc.).  

\- Export des épingles du menu Démarrer si possible.  

\- Option `IncludeTaskbarStart`.  

\- À l’import : tentative de restauration équivalente (en tenant compte des limitations Windows 10/11).



\### 3.11 Inventaire des applications installées



But : fournir un listing exploitable pour réinstaller les logiciels nécessaires.



\- Export de la liste des applications installées (Nom, Version, Publisher, type MSI/Store, etc.).  

\- Sauvegarde dans un manifest (JSON) dédié, par exemple `Applications\\applications.json`.  

\- Cet inventaire n’est pas “restauré” automatiquement mais sert de base pour le technicien (ou des automatisations futures).



---



\## 4. Import – principes généraux



L’import est piloté par `Import-MWProfile`, avec les mêmes drapeaux que l’export, plus `UseDataFoldersManifest`.



Principes :



\- L’import se fait \*\*toujours pour l’utilisateur courant\*\* (pas pour un profil arbitraire).  

\- Le script doit savoir s’adapter :  

&nbsp; - si un dossier exporté n’existe pas dans le manifest de l’utilisateur courant → log + skip, pas de crash ;  

&nbsp; - si une imprimante n’est plus disponible → log + skip ;  

&nbsp; - si un lecteur réseau est inaccessible → log + skip…  

\- Tout doit être \*\*idempotent\*\* autant que possible : relancer un import ne doit pas massacrer la machine.



Sur la partie données utilisateur :



\- Si `UseDataFoldersManifest = $true` :  

&nbsp; - lecture de `DataFolders.manifest.json` produit à l’export ;  

&nbsp; - correspondance des clés (Desktop, Documents, etc.) avec le manifest du profil courant ;  

&nbsp; - import sélectif via `Show-MWDataFoldersImportPlan` (sélection interactive) + `Import-MWDataFolders`.  



\- Si `UseDataFoldersManifest = $false` :  

&nbsp; - utilisation du comportement historique `Import-MWUserData`.



---



\## 5. Logs et traçabilité



Le module `MW.Logging` fournit un mécanisme centralisé de log :



\- Initialisation via `Initialize-MWLogging`.  

\- Écriture de messages `INFO / WARN / ERROR / DEBUG` via `Write-MWLog` (ou des wrappers).  

\- Les logs sont écrits dans un fichier du type :  

&nbsp; `.\\Logs\\MigrationWizard\_YYYY-MM-DD.log`



Objectifs :



\- avoir une trace claire de chaque export/import (date, options, erreurs) ;  

\- faciliter le debug quand quelque chose ne se passe pas comme prévu ;  

\- permettre d’attacher le log dans un ticket pour un client.



Le code de log est conçu pour ne \*\*pas casser le script\*\* si le fichier de log est verrouillé ou inaccessible (gestion via `try/catch`).



---



\## 6. Architecture du projet (haut niveau)



Organisation globale visée :



\- `src\\Core\\`

&nbsp; - `Export.psm1` : fonctions génériques liées aux exports, snapshots, chemins, etc.

&nbsp; - `Profile.psm1` : fonctions haut niveau `Export-MWProfile` / `Import-MWProfile`.

&nbsp; - `DataFolders.psm1` : gestion des dossiers utilisateur (manifest, export/import, sélection interactive).

\- `src\\Modules\\`

&nbsp; - `MW.Logging.psm1` : système de log centralisé.

&nbsp; - (éventuellement, d’autres modules transverses : config, outils communs...)

\- `src\\Features\\`

&nbsp; - `Wifi.psm1`

&nbsp; - `Printers.psm1`

&nbsp; - `NetworkDrives.psm1`

&nbsp; - `Rdp.psm1`

&nbsp; - `Browsers.psm1`

&nbsp; - `Outlook.psm1`

&nbsp; - `Wallpaper.psm1`

&nbsp; - `DesktopLayout.psm1`

&nbsp; - `TaskbarStart.psm1`

&nbsp; - etc.



Plus tard :



\- un script principal (ou EXE) jouera le rôle de \*\*front-end\*\* (WPF / interface graphique), en appelant ces fonctions Core/Features.  

\- la même logique devra fonctionner en \*\*mode “full auto”\*\* (sans interface) pour des scénarios batch.



---



\## 7. Nouveautés par rapport au script d’origine



Par rapport au gros script de ~3000 lignes :



\- Découpage en \*\*modules clairs\*\* (Core, Features, Logging, DataFolders…).  

\- Ajout d’un \*\*système de manifest pour les dossiers utilisateur\*\* :

&nbsp; - description des dossiers sous forme d’objets,

&nbsp; - export/import via robocopy,

&nbsp; - sélection interactive avant l’export/import,

&nbsp; - séparation propre entre “ce que l’on pourrait exporter” et “ce que l’on choisit réellement d’exporter”.

\- Ajout des paramètres `UseDataFoldersManifest` dans `Export-MWProfile` et `Import-MWProfile`, permettant :

&nbsp; - soit de garder le comportement historique,

&nbsp; - soit d’activer le mode avancé DataFolders sans tout casser.

\- Mise en place d’un \*\*système de logs plus robuste\*\*, capable de tracer chaque étape sans interrompre l’exécution en cas de souci sur le fichier de log.

\- Préparation du terrain pour une \*\*future UI WPF / EXE\*\*, qui viendra piloter ces fonctionnalités plutôt qu’embarquer toute la logique dans un seul gros script monolithique.



Ce document sert de référence globale pour ce que MigrationWizard doit faire au final.  

Les autres fichiers de documentation détailleront :

\- ce qui est déjà implémenté,  

\- ce qui reste à faire,  

\- et la feuille de route par phases.



