\# MigrationWizard – Roadmap \& TODO



Ce document liste \*\*ce qu’il reste à faire\*\* pour arriver à une version complète de MigrationWizard, en partant :

\- du script historique (gros script ~3000 lignes),

\- de la nouvelle architecture modulaire déjà en place,

\- des modules déjà implémentés (Logging, Export snapshot, DataFolders, Profile).



Les éléments \*\*déjà faits\*\* sont décrits en détail dans :  

`docs/MW-Work-Done.md`.



---



\## 0. Rappel très rapide de l’objectif global



MigrationWizard doit :



\- Permettre un \*\*export complet\*\* du profil utilisateur sur l’ancien PC :

&nbsp; - données classiques (Bureau, Documents, …) avec sélection fine,

&nbsp; - Wifi, imprimantes, lecteurs réseaux, RDP,

&nbsp; - navigateurs, Outlook, fond d’écran, disposition du bureau, barre des tâches,

&nbsp; - éventuellement quelques apps ciblées (signatures Outlook, profils logiciels, etc.).

\- Puis un \*\*import contrôlé\*\* sur le nouveau PC :

&nbsp; - en s’adaptant au login de l’utilisateur,

&nbsp; - sans se reposer sur OneDrive connecté,

&nbsp; - en évitant de pourrir le nouveau profil (sécurisé, propre).



La nouvelle version doit :

\- être \*\*modulaire\*\* (Core + Features),

\- être \*\*loggée\*\* proprement,

\- être \*\*testable en PowerShell\*\* et ensuite pilotée par une \*\*UI\*\* (WPF → EXE).



---



\## 1. Noyau / Core – Stabilisation et petites améliorations



\### 1.1. Logging (MW.Logging)



\- \[x] Logging centralisé `Initialize-MWLogging`, `Write-MWLog\*`.

\- \[ ] Améliorer la gestion des fichiers verrouillés :

&nbsp; - \[ ] Si le log du jour est verrouillé, basculer sur un fichier `MigrationWizard\_YYYY-MM-DD\_2.log` (ou similaire),

&nbsp; - \[ ] Ajouter un retry léger (1–2 tentatives) avant d’abandonner l’écriture.

\- \[ ] Ajouter un niveau de log configurable (par ex. via un paramètre global / fichier de config) :

&nbsp; - \[ ] Mode normal = INFO/WARN/ERROR,

&nbsp; - \[ ] Mode debug = tout (DEBUG inclus).



\### 1.2. Snapshots d’export (Export.psm1)



\- \[x] Génération / lecture d’un snapshot export (`Save-MWExportSnapshot`, `Import-MWExportSnapshot`).

\- \[ ] Compléter / valider la liste des chemins dans `$snap.Paths` :

&nbsp; - \[ ] Chemins dédiés pour chaque feature (Wifi, Printers, Outlook…),

&nbsp; - \[ ] Vérifier que tous les modules futurs utilisent ces chemins, \*\*pas\*\* des concat en dur.

\- \[ ] Prévoir une version “snapshot d’import” si besoin (ou réutiliser proprement la même structure).



---



\## 2. Données utilisateur – Aller plus loin que les dossiers classiques



Le module `DataFolders` gère déjà les dossiers classiques (Desktop, Documents, etc.).



\### 2.1. Étendre la logique DataFolders



\- \[ ] Ajouter des dossiers “spéciaux” ciblés, par exemple :

&nbsp; - \[ ] Une zone pour certains répertoires d’applications (ex : `AppData\\Roaming\\...` pour quelques applis sûres),

&nbsp; - \[ ] Des sous-répertoires spécifiques pour éviter d’aspirer un AppData monstrueux.

\- \[ ] Permettre un marquage "Avancé" / "Basique" dans le manifest (si utile pour l’UI).



\### 2.2. Gestion OneDrive / Redirection



\- \[ ] Réintégrer l’intelligence “anti-OneDrive” du script original :

&nbsp; - \[ ] Si le Bureau / Documents / Images du PC source sont sous OneDrive (`C:\\Users\\xxx\\OneDrive\\...`),

&nbsp; - \[ ] alors, à l’import, recoller les fichiers dans les dossiers classiques du nouvel utilisateur (`C:\\Users\\xxx\\Desktop`),

&nbsp; - \[ ] sans dépendre de la connexion OneDrive.

\- \[ ] Tracer clairement ces décisions dans les logs (source sous OneDrive, cible locale, etc.).



---



\## 3. Modules “Features” à reconstruire / finaliser



Ces modules existaient “en vrac” dans le script de 3000 lignes.  

Dans la nouvelle archi, ils devront être des modules séparés dans `src\\Features\\...`.



\### 3.1. Wifi



Objectif :

\- Exporter les profils Wifi de l’ancien PC,  

\- Les réimporter sur le nouveau.



Tâches :

\- \[ ] Créer un module `src\\Features\\Wifi.psm1`.

\- \[ ] Implémenter `Export-MWWifiProfiles` :

&nbsp; - \[ ] Appui sur `netsh wlan export profile` ou équivalent moderne,

&nbsp; - \[ ] Stockage des profils dans un dossier dédié (défini dans le snapshot).

\- \[ ] Implémenter `Import-MWWifiProfiles` :

&nbsp; - \[ ] Réimporter les profils,

&nbsp; - \[ ] Gérer les erreurs (droits admin, profils déjà présents…).

\- \[ ] Intégration dans `Export-MWProfile` / `Import-MWProfile` via les flags `IncludeWifi`.



\### 3.2. Imprimantes



Objectif :

\- Reprendre ce que faisait le script original (imprimantes utilisateur / machine), mais proprement.



Tâches :

\- \[ ] Créer `src\\Features\\Printers.psm1`.

\- \[ ] Implémenter `Export-MWPrinters` :

&nbsp; - \[ ] Lister les imprimantes, capturer la valeur par défaut,

&nbsp; - \[ ] Sauvegarder un manifest (nom, port, driver, défaut ou pas).

\- \[ ] Implémenter `Import-MWPrinters` :

&nbsp; - \[ ] Recréer les imprimantes logiques,

&nbsp; - \[ ] Restaurer l’imprimante par défaut,

&nbsp; - \[ ] Gérer les cas où les drivers ne sont pas dispo.

\- \[ ] Intégration dans `Export-MWProfile` / `Import-MWProfile` via `IncludePrinters`.



\### 3.3. Lecteurs réseaux



Objectif :

\- Exporter / importer les mappages de lecteurs réseaux.



Tâches :

\- \[ ] Créer `src\\Features\\NetworkDrives.psm1`.

\- \[ ] Implémenter `Export-MWNetworkDrives` :

&nbsp; - \[ ] Lister les mappages (lettre, chemin UNC, reconnect at logon…),

&nbsp; - \[ ] Sauvegarder un manifest JSON.

\- \[ ] Implémenter `Import-MWNetworkDrives` :

&nbsp; - \[ ] Remapper les lecteurs sur le nouveau PC,

&nbsp; - \[ ] Gérer les cas où le serveur n’est pas accessible au moment de l’import.

\- \[ ] Intégration via `IncludeNetworkDrives`.



\### 3.4. RDP / Connexions Bureau à distance



Objectif :

\- Exporter les `.rdp` / raccourcis RDP utilisés par l’utilisateur.



Tâches :

\- \[ ] Créer `src\\Features\\Rdp.psm1`.

\- \[ ] Implémenter `Export-MWRdpFiles` :

&nbsp; - \[ ] Localiser les `.rdp` dans les chemins standards / historiques (ex : Desktop, Documents\\RDP, etc.),

&nbsp; - \[ ] Copier / inventorier ces fichiers.

\- \[ ] Implémenter `Import-MWRdpFiles` :

&nbsp; - \[ ] Recoller ces `.rdp` dans les bons dossiers du nouveau profil.

\- \[ ] Intégration via `IncludeRdp`.



\### 3.5. Navigateurs



Objectif :

\- Gérer ce que faisait le script original coté navigateurs (au minimum :

&nbsp; favoris / profils de base).



Tâches (à ajuster selon ce que faisait exactement le script historique) :

\- \[ ] Créer `src\\Features\\Browsers.psm1`.

\- \[ ] Gérer au minimum :

&nbsp; - \[ ] Chrome,

&nbsp; - \[ ] Edge,

&nbsp; - \[ ] (éventuellement Firefox).

\- \[ ] Export :

&nbsp; - \[ ] Copier les profils / favoris dans un dossier d’export,

&nbsp; - \[ ] Éviter de copier des caches monstrueux si possible.

\- \[ ] Import :

&nbsp; - \[ ] Recréation des profils / recopie ciblée,

&nbsp; - \[ ] S’assurer que les droits / chemins sont propres.

\- \[ ] Intégration via `IncludeBrowsers`.



\### 3.6. Outlook



Objectif :

\- Reprendre ce que faisait le script original autour d’Outlook :

&nbsp; - signatures,

&nbsp; - profils / config,

&nbsp; - éventuellement PST selon ta stratégie.



Tâches :

\- \[ ] Créer `src\\Features\\Outlook.psm1`.

\- \[ ] Export :

&nbsp; - \[ ] Réutiliser si possible la logique du script de signatures que tu avais déjà,

&nbsp; - \[ ] Sauvegarder signatures + éventuels fichiers liés,

&nbsp; - \[ ] Sauvegarder un manifest avec l’info utile (compte principal, etc. si géré).

\- \[ ] Import :

&nbsp; - \[ ] Recoller les signatures dans le bon profil utilisateur,

&nbsp; - \[ ] Gérer les chemins de version Office (Office 16, 365, etc.).

\- \[ ] Intégration via `IncludeOutlook`.



\### 3.7. Fond d’écran, disposition du bureau, barre des tâches



Ce sont trois features séparées mais liées à l’apparence.



Tâches :

\- \[ ] Créer un module `src\\Features\\ShellLayout.psm1` (ou plusieurs si tu préfères séparer).

\- \[ ] Export :

&nbsp; - \[ ] Fond d’écran :

&nbsp;   - \[ ] Copier le fichier image en cours (et pas juste une clé registre).

&nbsp; - \[ ] Disposition du bureau :

&nbsp;   - \[ ] Reprendre ce que faisait le script historique (clés ShellBags, layout, etc.),

&nbsp;   - \[ ] Sauvegarder dans un manifest ou des exports .reg.

&nbsp; - \[ ] Barre des tâches / menu Démarrer :

&nbsp;   - \[ ] Exporter les pins / layout si possible (selon version Windows).

\- \[ ] Import :

&nbsp; - \[ ] Restaurer ces éléments dans le nouveau profil,

&nbsp; - \[ ] Adapter si la version de Windows est différente (Win10 vs Win11).

\- \[ ] Intégration via `IncludeWallpaper`, `IncludeDesktopLayout`, `IncludeTaskbarStart`.



---



\## 4. UI / WPF / EXE



\### 4.1. UI WPF



Objectif :

\- Retrouver la logique de ton EXE actuel, mais branchée sur les nouveaux modules.



Tâches :

\- \[ ] Reprendre ton projet WPF (ou en créer un nouveau) dans un dossier `src\\UI\\...`.

\- \[ ] Créer une couche d’appel :

&nbsp; - \[ ] Un module “front” qui appelle `Export-MWProfile` et `Import-MWProfile` avec les bons paramètres.

\- \[ ] Gérer dans l’UI :

&nbsp; - \[ ] Choix du mode d’export (simple vs avancé `UseDataFoldersManifest`),

&nbsp; - \[ ] Choix des features via des cases à cocher (Wifi, Imprimantes, etc.),

&nbsp; - \[ ] Affichage de l’avancement / des logs.



\### 4.2. Intégration DataFolders dans l’UI



Actuellement :

\- la sélection des dossiers se fait via `Out-GridView`.



Plus tard :

\- \[ ] Reprendre cette sélection dans l’UI WPF :

&nbsp; - \[ ] Charger le manifest,

&nbsp; - \[ ] Afficher une grille dans la fenêtre,

&nbsp; - \[ ] Modifier `Include` en fonction des cases cochées,

&nbsp; - \[ ] Sauvegarder le manifest puis lancer `Export-MWDataFolders`.



\### 4.3. Packaging EXE



\- \[ ] Reprendre le pipeline PS2EXE (ou outil équivalent) pour :

&nbsp; - \[ ] Compiler le script “lanceur” (qui charge les modules et l’UI),

&nbsp; - \[ ] Générer un EXE standalone pour déploiement chez les clients.



---



\## 5. Configuration \& Presets



Objectif :

\- Pouvoir \*\*préconfigurer\*\* MigrationWizard pour différents scénarios.



Tâches :

\- \[ ] Introduire un fichier de config (JSON ou autre) pour :

&nbsp; - \[ ] Valeurs par défaut des flags (Inclure Wifi, etc.),

&nbsp; - \[ ] Mode test vs mode prod,

&nbsp; - \[ ] Répertoires par défaut (si différents).

\- \[ ] Ajouter une logique de \*presets\* :

&nbsp; - \[ ] Preset “rapide” (données + lecteurs réseaux),

&nbsp; - \[ ] Preset “complet” (tout sauf trucs trop lourds),

&nbsp; - \[ ] Preset “minimal” (juste Documents + Bureau).



---



\## 6. Qualité / Tests / Docs



\### 6.1. Tests manuels



\- \[ ] Définir un scénario de test complet (ancien PC → nouveau PC) avec :

&nbsp; - \[ ] Profil simple (peu de données),

&nbsp; - \[ ] Profil “chargé” (Docs, OneDrive, navigateurs, etc.),

&nbsp; - \[ ] Profil avec contraintes (réseau limité, pas de droits admin complets…).

\- \[ ] Documenter les commandes de test dans un autre fichier (`MW-Test-Scenarios.md`).



\### 6.2. Documentation



\- \[ ] Compléter / maintenir :

&nbsp; - \[ ] `MW-Overview.md` (vision globale),

&nbsp; - \[ ] `MW-Work-Done.md` (état actuel),

&nbsp; - \[ ] Ce fichier (`MW-Roadmap-TODO.md`),

&nbsp; - \[ ] Un futur `MW-Test-Scenarios.md` si besoin.



---



\## 7. Priorisation suggérée



Ordre conseillé pour la suite :



1\. \*\*Stabiliser Noyau + DataFolders + OneDrive\*\*  

2\. Refaire \*\*Wifi\*\* et \*\*Lecteurs réseaux\*\* (très utiles pour les migrations).

3\. Reprendre \*\*Imprimantes\*\* et \*\*RDP\*\*.

4\. S’attaquer aux \*\*navigateurs\*\*.

5\. Rebrancher \*\*Outlook\*\* (signatures au minimum).

6\. Gérer \*\*Wallpaper / Desktop / Taskbar\*\* si toujours pertinent.

7\. Rebrancher l’\*\*UI WPF\*\* et l’EXE.

8\. Finaliser avec config / presets / doc / tests.



---



