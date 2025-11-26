\# MigrationWizard – Backlog \& Roadmap



Ce fichier liste \*\*ce qu’il reste à faire\*\* pour aller d’un gros script unique (~3000 lignes) vers :

\- une architecture modulaire propre,

\- une UX claire (WPF),

\- un outil packagé et exploitable en prod (EXE / signature / doc).



Les points sont organisés par thèmes + une petite roadmap par phases.



---



\## 1. Cœur technique / Core



\### 1.1. Snapshot d’export



\- \[ ] Finaliser la structure du snapshot :

&nbsp; - \[ ] Valider les propriétés obligatoires (MachineName, UserName, UserProfilePath, Timestamp, Applications, Paths, etc.).

&nbsp; - \[ ] Ajouter un champ de \*\*version de schéma\*\* (ex: `SnapshotSchemaVersion`) pour gérer les futures évolutions.

\- \[ ] Décider si certains manifests (Applications, DataFolders, autres) doivent être :

&nbsp; - \[ ] intégrés \*\*dans\*\* le snapshot,

&nbsp; - \[ ] ou stockés dans des fichiers JSON séparés, avec seulement les chemins dans `Paths`.



\### 1.2. Centralisation des chemins



\- \[ ] S’assurer que \*\*tous les modules\*\* utilisent les chemins issus du snapshot (ou d’un équivalent) et pas des chemins "magiques" hard-codés :

&nbsp; - \[ ] `ApplicationsManifestPath`

&nbsp; - \[ ] `UserDataRoot`

&nbsp; - \[ ] `DataFoldersManifestPath`

&nbsp; - \[ ] futurs chemins : `WifiExportPath`, `PrintersExportPath`, etc.



---



\## 2. Modules “Features” à migrer / reconnecter



Actuellement, plusieurs parties viennent encore du gros script historique. L’objectif est de les basculer proprement en modules dédiés, à la manière de `DataFolders`.



\### 2.1. Wi-Fi



\- \[ ] Créer un module `src\\Features\\Wifi.psm1` (ou équivalent) avec :

&nbsp; - \[ ] `Export-MWWifiProfiles` : export des profils Wi-Fi (clé incluse ou non suivant l’option).

&nbsp; - \[ ] `Import-MWWifiProfiles` : import sur le nouveau poste.

\- \[ ] Découpler du code historique :

&nbsp; - \[ ] Ne plus appeler directement les commandes netsh/PowerShell depuis `Profile.psm1`.

&nbsp; - \[ ] Passer uniquement par les fonctions du module Wifi.

\- \[ ] Intégration snapshot :

&nbsp; - \[ ] Ajouter dans `Paths` un ou plusieurs chemins pour les exports Wi-Fi (dossier / fichier XML).



\### 2.2. Imprimantes



\- \[ ] Créer un module `src\\Features\\Printers.psm1` avec :

&nbsp; - \[ ] `Export-MWPrinters` : collecte des imprimantes utilisateur/machine + paramètres utiles.

&nbsp; - \[ ] `Import-MWPrinters` : recréation des imprimantes (et éventuellement assignation par défaut).

\- \[ ] Gérer les limites :

&nbsp; - \[ ] Distinction imprimantes locales / réseau.

&nbsp; - \[ ] Gestion de cas où les serveurs d’impression ne sont plus joignables.

\- \[ ] Intégrer proprement dans `Export-MWProfile` / `Import-MWProfile` via `IncludePrinters`.



\### 2.3. Lecteurs réseau (Network Drives)



\- \[ ] Créer un module `src\\Features\\NetworkDrives.psm1` :

&nbsp; - \[ ] Export des mappings (lettre, UNC, options de reconnexion).

&nbsp; - \[ ] Import avec recréation des mappings pour le nouvel utilisateur.

\- \[ ] Prendre en compte les environnements AD :

&nbsp; - \[ ] GPO qui mappent déjà certains lecteurs.

&nbsp; - \[ ] Éviter les doublons en laissant certaines lettres sous la responsabilité du SI.



\### 2.4. RDP / Connexions distantes



\- \[ ] Créer un module `src\\Features\\Rdp.psm1` :

&nbsp; - \[ ] Export des fichiers `.rdp` / Quick Access / MRU si pertinent.

&nbsp; - \[ ] Import sur le nouveau profil.

\- \[ ] Gérer la partie sécurité :

&nbsp; - \[ ] Ne pas exporter de credentials en clair.

&nbsp; - \[ ] Documenter clairement ce qui est pris ou non.



\### 2.5. Navigateurs / favoris



\- \[ ] Créer un module `src\\Features\\Browsers.psm1` :

&nbsp; - \[ ] Browser(s) cible(s) : Chrome, Edge, Firefox en priorité.

&nbsp; - \[ ] Export des favoris (bookmarks) + éventuellement paramètres utiles.

&nbsp; - \[ ] Import sur la nouvelle machine / nouveau profil.

\- \[ ] Gérer les cas OneDrive / sync cloud :

&nbsp; - \[ ] Si le profil est déjà synchronisé via compte Microsoft / Chrome, adapter la stratégie pour éviter les doublons.



\### 2.6. Outlook / profils mail



\- \[ ] Créer un module `src\\Features\\Outlook.psm1` :

&nbsp; - \[ ] Export des fichiers PST/OST si nécessaire (et raisonnable).

&nbsp; - \[ ] Récupération du profil Outlook, signature, etc.

\- \[ ] Décider du niveau de prise en charge :

&nbsp; - \[ ] Minimal : signatures + paramètres basiques.

&nbsp; - \[ ] Avancé : gestion plus fine des profils (au prix de la complexité).

\- \[ ] Gérer les cas M365 / Exchange Online :

&nbsp; - \[ ] Probablement privilégier la reconfiguration propre plutôt qu’un clonage brutal.



\### 2.7. Fond d’écran, mise en page, barre des tâches



\- \[ ] Créer un module `src\\Features\\Desktop.psm1` :

&nbsp; - \[ ] Export fond d’écran.

&nbsp; - \[ ] Export mise en page des icônes (si encore jugé utile / possible).

&nbsp; - \[ ] Export configuration barre des tâches / menu Démarrer (dans la limite de ce que Windows permet).

\- \[ ] Intégrer aux flags :

&nbsp; - \[ ] `IncludeWallpaper`

&nbsp; - \[ ] `IncludeDesktopLayout`

&nbsp; - \[ ] `IncludeTaskbarStart`



---



\## 3. Refactor de `Profile.psm1`



\### 3.1. Orchestration propre



\- \[ ] Modifier `Export-MWProfile` pour :

&nbsp; - \[ ] arrêter d’appeler directement les “anciens blocs” du gros script.

&nbsp; - \[ ] appeler UNIQUEMENT les fonctions exposées par les modules Features (`Wifi`, `Printers`, `NetworkDrives`, etc.).

&nbsp; - \[ ] utiliser le snapshot / les `Paths` pour tous les emplacements.



\- \[ ] Modifier `Import-MWProfile` dans le même esprit.



\### 3.2. Gestion d’erreurs



\- \[ ] Harmoniser les `try/catch` :

&nbsp; - \[ ] un `try/catch` global sur l’export / import complet (déjà en partie là).

&nbsp; - \[ ] des `try/catch` par brique pour loguer finement sans casser tout le process.

\- \[ ] Centraliser les messages :

&nbsp; - \[ ] Toujours utiliser `Write-MWLogInfo/Warn/Error` pour les événements importants.

&nbsp; - \[ ] Ajouter un résumé final (nombre de warnings / erreurs).



---



\## 4. Logging – améliorations



\- \[ ] Gérer proprement le \*\*verrouillage du fichier de log\*\* :

&nbsp; - \[ ] Si `Add-Content` lève une `IOException` “file in use”, tenter :

&nbsp;   - \[ ] une rotation (nouveau fichier avec suffixe `\_2`, `\_3`, etc.),

&nbsp;   - \[ ] ou retomber sur un log minimal en mémoire / console.

\- \[ ] Ajouter un paramètre global de verbosité :

&nbsp; - \[ ] `-VerboseLog` ou équivalent,

&nbsp; - \[ ] pour activer/désactiver les logs `DEBUG` sans toucher au code.

\- \[ ] Prévoir une commande pour “ouvrir le dernier log” depuis l’UI ou depuis le script (ex: `Show-MWLastLog` qui ouvre Notepad sur le bon fichier).



---



\## 5. UI / Expérience utilisateur



\### 5.1. Interface WPF



\- \[ ] Reprendre l’ancienne interface WPF (si existante) et la reconnecter à la nouvelle architecture :

&nbsp; - \[ ] L’écran principal doit piloter :

&nbsp;   - \[ ] le choix des options (IncludeUserData, Wifi, etc.),

&nbsp;   - \[ ] le chemin d’export,

&nbsp;   - \[ ] le lancement de `Export-MWProfile`,

&nbsp;   - \[ ] le lancement de `Import-MWProfile`.

\- \[ ] Organiser l’UI par onglets ou sections :

&nbsp; - \[ ] Export,

&nbsp; - \[ ] Import,

&nbsp; - \[ ] Logs / diagnostics,

&nbsp; - \[ ] Options avancées (mode DataFolders, filtrage applis, etc.).



\### 5.2. Intégration DataFolders dans l’UI



\- \[ ] Ajouter un bouton “Choisir les dossiers à exporter” qui :

&nbsp; - \[ ] appelle la logique `UseDataFoldersManifest = $true`,

&nbsp; - \[ ] et affiche soit `Out-GridView`, soit un équivalent intégré WPF (liste avec cases à cocher).

\- \[ ] Même chose côté import : visualiser source → destination pour les dossiers utilisateurs.



---



\## 6. Packaging / EXE / signature



\### 6.1. Compilation en EXE



\- \[ ] Préparer la ligne PS2EXE (ou autre outil équivalent) pour générer :

&nbsp; - \[ ] un EXE d’export,

&nbsp; - \[ ] un EXE d’import,

&nbsp; - \[ ] ou un EXE unique mode “wizard”.

\- \[ ] Gérer les dépendances :

&nbsp; - \[ ] Intégrer tous les `.psm1` nécessaires,

&nbsp; - \[ ] Vérifier que les chemins relatifs (Logs, etc.) restent cohérents dans le contexte EXE.



\### 6.2. Signature



\- \[ ] Étudier les options pour :

&nbsp; - \[ ] signer l’EXE (ou au minimum le script PowerShell) afin de limiter les alertes antivirus / SmartScreen.

\- \[ ] Documenter les limites :

&nbsp; - \[ ] ce qui est possible gratuitement / avec un cert auto-signé,

&nbsp; - \[ ] ce qui nécessiterait un certificat Code Signing officiel.



---



\## 7. Tests, validation \& scénarios type



\### 7.1. Scénarios de tests techniques



\- \[ ] Préparer une check-list de tests pour chaque brique :

&nbsp; - \[ ] DataFolders : export/import, présence ou non de certains dossiers, tests `WhatIf`.

&nbsp; - \[ ] Wifi, imprimantes, lecteurs réseau, etc. une fois migrés en modules.

\- \[ ] Tester :

&nbsp; - \[ ] poste local → même poste (validation basique),

&nbsp; - \[ ] vieux PC → nouveau PC,

&nbsp; - \[ ] avec différents types de profils (OneDrive Desktop redirigé, profil classique…).



\### 7.2. Non-régressions vis-à-vis de l’ancien script



\- \[ ] Lister les \*\*fonctionnalités de l’ancien script\*\* qui ne sont pas encore couvertes par les nouveaux modules.

\- \[ ] Pour chacune :

&nbsp; - \[ ] décider si on la reprend telle quelle,

&nbsp; - \[ ] on la simplifie,

&nbsp; - \[ ] ou on l’abandonne (car trop fragile / peu utile en pratique).



---



\## 8. Documentation / GitHub



\### 8.1. Docs techniques (développées dans ce repo)



\- \[ ] Maintenir à jour :

&nbsp; - \[ ] `MW-Project-Vision.md` (vision globale),

&nbsp; - \[ ] `MW-Implemented-Features.md` (ce qui est déjà fait),

&nbsp; - \[ ] `MW-Backlog-Roadmap.md` (ce fichier → à ajuster au fur et à mesure).

\- \[ ] Ajouter :

&nbsp; - \[ ] un `README.md` synthétique pour GitHub,

&nbsp; - \[ ] une section “Comment contribuer / comment builder”.



\### 8.2. Guide utilisateur



\- \[ ] Rédiger un guide simple :

&nbsp; - \[ ] “Comment faire un export de profil depuis un ancien PC”

&nbsp; - \[ ] “Comment faire l’import sur le nouveau PC”

&nbsp; - \[ ] “Que fait chaque case à cocher (Wifi, Imprimantes, etc.)”

\- \[ ] Inclure un chapitre :

&nbsp; - \[ ] sur les limites fonctionnelles (ce que l’outil NE fait PAS),

&nbsp; - \[ ] sur les bonnes pratiques (OneDrive, signatures Outlook, etc.).



---



\## 9. Roadmap proposée (itérative)



Une suggestion de découpage en étapes réalistes :



1\. \*\*Phase A – Stabilisation du Core\*\*

&nbsp;  - \[ ] Finaliser snapshot + Paths.

&nbsp;  - \[ ] Nettoyer Profile pour qu’il s’appuie proprement sur snapshot + DataFolders.

&nbsp;  - \[ ] Renforcer Logging.



2\. \*\*Phase B – Migration des Features critiques\*\*

&nbsp;  - \[ ] Wi-Fi

&nbsp;  - \[ ] Imprimantes

&nbsp;  - \[ ] Lecteurs réseau

&nbsp;  - \[ ] RDP



3\. \*\*Phase C – UX \& confort\*\*

&nbsp;  - \[ ] Browsers

&nbsp;  - \[ ] Outlook / signatures

&nbsp;  - \[ ] Desktop / Taskbar / Start



4\. \*\*Phase D – UI \& packaging\*\*

&nbsp;  - \[ ] Reconnexion WPF

&nbsp;  - \[ ] Build EXE

&nbsp;  - \[ ] Tests réels terrain + retours d’expérience.



5\. \*\*Phase E – “Produit fini”\*\*

&nbsp;  - \[ ] Doc propre (technique + utilisateur).

&nbsp;  - \[ ] Stabilisation, corrections de bugs.

&nbsp;  - \[ ] Éventuellement : préparation d’une version publiable (GitHub “officiel”).



---



Ce backlog/roadmap est volontairement détaillé : il sert de \*\*liste de courses\*\* pour avancer étape par étape, sans perdre de vue l’objectif final.



