# Développement d'AzerothVeil

## Environnement

- Code dans WSL : `~/projets/AzerothVeil` ; client WoW Forever sous Windows.
- Lua 5.1 (celui de WoW) pour les contrôles. Si `lua5.1` n'est pas installé, une copie locale sans droits
  administrateur :
  ```bash
  mkdir -p .tools/pkgs && cd .tools/pkgs
  apt-get download lua5.1 liblua5.1-0
  for d in *.deb; do dpkg -x "$d" ../root; done
  ```
  `scripts/check.sh` la trouve tout seul.

## Boucle de travail

```bash
scripts/check.sh              # syntaxe Lua 5.1, .toc, globaux, restes PerfectMap, tests unitaires
scripts/deploy.sh --dry-run   # ce qui serait copié/supprimé
scripts/deploy.sh             # contrôles + build/ + copie vers AddOns/AzerothVeil
```
Puis en jeu : `/reload` (un nouveau fichier ou une modification du `.toc` exige de relancer le jeu).

Configuration du déploiement : `cp scripts/deploy.conf.example scripts/deploy.local.conf` (non versionné).
Le script vérifie que la cible est bien `…/_forever_/Interface/AddOns` d'une installation WoW, n'écrit
que dans `AddOns/AzerothVeil`, refuse un dossier `AzerothVeil` qui ne contiendrait pas notre `.toc`, et
n'utilise jamais de lien symbolique.

## Règles de code

- Pas de nouveau global (contrôlé par `check.sh`). Tout passe par le namespace `ns`.
- Rien au chargement d'un fichier de module sauf `ns.Modules:Register{}`.
- Pas d'`OnUpdate` permanent ; préférer événements et `self:After/NewTicker` (annulés à la désactivation).
- Toute API WoW utilisée doit être vérifiée dans le client ou dans un addon installé qui l'utilise
  (`.reference/`), et appelée défensivement (`pcall`, test d'existence) si elle peut manquer.
- Valeurs d'unités : passer par `ns.Plain` (valeurs « secrètes » du moteur 12.x).
- Modifications du moteur : minimales, commentées `-- AzerothVeil: ...`. Voir `git diff 00f834f -- addon/`.
- **Tout texte visible via `L["English"]`**, traduction dans `Locales/frFR.lua` (vérifié par `check.sh`).

## Commandes en jeu

| Commande | Effet |
|---|---|
| `/av` | ouvrir/fermer la carte |
| `/av config` | options centrales (modules) |
| `/av modules` | état des modules ; `/av modules enable|disable <nom>` |
| `/av stats` | performances du moteur |
| `/av help` | toutes les commandes |

## Checklist de validation en jeu (v0.2.0)

Préparation : relancer le jeu (nouveaux fichiers et `.toc` modifié), `/console scriptErrors 1`.

**Général**
1. Aucune erreur Lua au chargement ; la carte (M) se comporte comme avant (zoom, déplacement, survol).
2. Client en français : menu ⚙ de la carte, infobulles des icônes, journal de quêtes, carte de donjon en
   français. Les noms de zones et villes sont ceux du jeu.

**Fenêtre d'options (écran principal) et bouton de minicarte**
3. Bouton de minicarte : clic gauche ouvre/ferme la carte, clic droit ouvre/ferme les options, glisser le
   déplace autour de la minicarte (position gardée après `/reload`) ; avec FlareUI, il est rangé dans son
   tiroir. Onglet Carte : « Bouton de la minicarte » le masque/affiche. Compartiment d'addons du jeu : mêmes clics.
4. Fenêtre d'options : s'ouvre carte fermée ; déplaçable par sa barre de titre, ne sort pas de l'écran ;
   poignée en bas à droite : agrandit/réduit toute la fenêtre ; position et taille gardées après `/reload` ;
   croix et Échap la ferment ; elle reste ouverte quand on ferme la carte.
5. Onglets Transports et Amis & guilde : en-tête encadré (icône, titre, case d'activation à côté du titre,
   description, état), puis boîtes « Affichage » / « Fonctionnalités » (ou « Réglages ») en deux colonnes.
   Décocher le module : options grisées et non cliquables, valeurs conservées.
5b. Un changement dans la fenêtre se voit aussitôt dans Options > AddOns > AzerothVeil, et inversement.
6. En combat : `/av config` puis Échap ne bloque aucune touche du jeu.

**Transports**
6c. Zoom (v0.3.5) : en zoomant depuis la vue du monde, les maîtres de vol apparaissent au même cran
    que les quêtes du journal (avant les PNJ des villes et les icônes de Questie).
6b. Maîtres de vol : dans l'onglet Transports (« Afficher les maîtres de vol », sous-option « Maîtres de vol
    ennemis »), plus dans l'onglet Lieux ; vos choix d'avant sont repris ; module désactivé : plus aucun.
7. Ports, tours des zeppelins, tram visibles. À Tanaris (ou tout quai à plusieurs trajets) : **un point
   par trajet**, jamais regroupés, même en dézoomant.
8. Clic sur un point : la carte va **directement** à l'autre extrémité, sans menu ni infobulle
   supplémentaire, y compris entre continents ; clic sur le quai d'arrivée : retour. Tram : va à l'autre station.
   Option « Clic : aller à la destination » décochée : le clic ne fait plus rien.
9. Tracés : au survol d'un quai, les lignes de ses trajets s'affichent et finissent sur leur propre point ;
   « Toujours afficher tous les tracés » et le bouton des outils de la carte (en bas à gauche) ;
   « Afficher les tracés » décoché : aucune ligne, même au survol.
10. Options bateaux / zeppelins / autres transports (et leurs enfants) : effet immédiat, carte ouverte ou non.
11. Suivi : bateaux et zeppelins en mouvement visibles une fois connus ; `/av sailings` répond.
    Suivi décoché : plus de bateaux en mouvement, `/av sailings` indique que le suivi est désactivé.
12. Module Transports désactivé : aucune icône de transport, aucun tracé, aucun bateau en mouvement ;
    `/av sailings` indique le suivi désactivé ; réactivation : tout revient avec les mêmes réglages.
13. `/av stats` : temps de rafraîchissement comparable à la v0.1.0.

**Amis & guilde** (non-régression)
14. Activation / désactivation et réglages comme en v0.1.0, depuis la nouvelle fenêtre.

## Checklist en jeu — module Donjons (v0.4.0)

Préparation : relancer le jeu (nouveaux fichiers). Faire les tests **sans** DungeonJournal (désactivé dans
la liste des AddOns), puis **avec**.

**Sans DungeonJournal**
1. Onglet Donjons dans le menu ⚙ (et `/av config`, Options > AddOns) ; vos anciens réglages de donjons repris.
2. Royaumes de l'Est et Kalimdor : icônes d'entrée (Mortemines, Uldaman, Hache-Tripes, Monastère écarlate,
   Rochenoire), infobulle en français avec la plage de niveaux ; « Plages de niveaux » décoché : plus de niveaux.
3. Clic sur Mortemines : sa carte dans la fenêtre de la carte, boss placés, entrée marquée ; panneau de droite
   remplacé par les onglets Quêtes / Boss.
4. Monastère écarlate / Hache-Tripes / Pic Rochenoire : liste des ailes, chacune ouvre la bonne carte.
   Donjon à plusieurs étages (Rochenoire, Gnomeregan) : boutons d'étage.
4b. Étages : boutons Blizzard empilés à gauche de la carte, l'étage affiché en surbrillance. Avec
   DungeonJournal installé (option « Utiliser DungeonJournal » décochée), donjons classiques (Ombrecroc,
   Mortemines) : flèches sur les passages vers un autre étage, clic → cet étage.
5. Onglet Boss : grands portraits ; plus de liste noire sur la carte (Repaire des Noiregueules : tous ses
   boss dans l'onglet, « Non placé sur la carte ») ; clic → bon étage, repère qui clignote, et son butin
   (avec DungeonJournal installé) : icônes, noms en français, couleur de qualité, infobulle du jeu,
   Maj-clic → lien.
6. Onglet Quêtes, option « Utiliser les données de Questie » cochée (Questie installé) : toutes les
   quêtes des Mortemines de votre faction, en français, état (disponible / pas encore + niveau requis /
   en cours / prête / terminée), « Donnée par … (zone) » ; une quête du journal garde sa progression et
   ses récompenses au clic ; une autre : « Montrer le donneur sur la carte » → la carte du monde sur lui.
   Option décochée (ou Questie absent) : seulement les quêtes du journal. Premier affichage : bref
   « Lecture des quêtes de Questie... ».
7. Bouton Monde ou clic droit : retour **exactement** à la vue d'avant (même endroit, même zoom), journal de
   quêtes revenu tel qu'il était (ouvert ou replié). Ouvrir un 2ᵉ donjon depuis le premier puis revenir :
   vue de départ.
8. Dans un donjon : la carte du donjon s'affiche (option « Carte du lieu où vous êtes »), avec les onglets ;
   champ de bataille : sa carte, sans onglets. En combat : ouvrir/fermer la carte, cliquer, aucune erreur.
9. Module désactivé : plus d'icônes ni de cartes de donjon ; réactivé : tout revient avec vos réglages.
10. Raid (Cœur du Magma, Onyxia) : carte et boss ; donjon sans carte : message « Le jeu n'a pas de carte… ».

**Avec DungeonJournal**
11. Clic sur Mortemines : la fenêtre de DungeonJournal s'ouvre sur ce donjon (carte si débloquée, sinon ses
    boss ; donjon verrouillé en mode RPG : sa propre notice). Aucun onglet AzerothVeil.
12. Stratholme : choix entre ses deux parties ; Monastère : choix des ailes → bonne page.
13. Raid (non couvert par DungeonJournal) : carte d'AzerothVeil.
14. Option « Utiliser DungeonJournal » décochée : retour au fonctionnement sans DungeonJournal.

## Checklist en jeu — module Carte et brouillard de guerre

Préparation : relancer le jeu (nouveaux fichiers et `.toc`).

1. Fenêtre d'options : l'onglet **Carte** est le premier, en-tête de module (case d'activation) ; vos anciens
   réglages repris (Ouvrir avec M, centrer, zoom, bouton de minicarte, surbrillance, icônes, grottes, terrain,
   pêche, taille des icônes). Même page dans Options > AddOns > AzerothVeil.
2. Chaque option agit comme avant (M, taille des icônes en direct, bouton de minicarte affiché/masqué…).
3. **Brouillard de guerre** coché, sur un personnage qui n'a pas tout exploré : les zones inexplorées en
   parchemin vierge comme sur la carte de Blizzard (comparer avec elle), les zones explorées intactes ; aucune
   bande ni bord net sur les zones voisines ; en zoom rapproché, le terrain de la minimap sur les parties explorées et le
   brouillard (bords doux) sur les parties inexplorées.
4. Explorer un nouveau lieu, carte ouverte ou non : il apparaît sans `/reload`.
5. Zoom le plus éloigné : la carte du monde de Blizzard, sans brouillard (comme chez Blizzard).
6. Brouillard décoché : toute la carte revient. `/av stats` : coût du rafraîchissement acceptable avec et sans,
   en particulier au premier affichage d'un continent entier avec le brouillard.
7. Module Carte désactivé : M ouvre la carte de Blizzard, plus de bouton de minicarte ; `/av` ouvre encore la
   carte, sans brouillard ni extras ; réactivé : tout revient avec vos réglages. En combat : aucune erreur.

## Checklist en jeu — module Icônes et PNJ des zones inexplorées

Préparation : relancer le jeu (nouveau fichier et `.toc`).

1. Fenêtre d'options : plus d'onglets « Lieux », « PNJ des villes », « Métiers » ; un onglet **Icônes** juste
   après Carte (en-tête de module), sections Capitales / PNJ des villes / Maîtres de métiers, avec vos anciens
   choix repris. Même page dans Options > AddOns > AzerothVeil.
2. Cocher/décocher un type, carte ouverte : les icônes apparaissent/disparaissent aussitôt. Capitales : emblèmes
   au zoom le plus éloigné seulement.
3. Module Icônes désactivé : ni capitales, ni PNJ, ni maîtres ; réactivé : vos choix reviennent.
4. Questie : activer un type dans son menu de PNJ → il s'active ici (case cochée dans l'onglet Icônes).
5. Carte > **PNJ des zones inexplorées** décoché, sur un personnage qui n'a pas tout exploré : les PNJ des zones
   (ou parties de zones) inexplorées disparaissent, ceux des zones explorées restent ; une capitale jamais visitée
   n'a pas ses PNJ. Explorer un nouveau lieu : ses PNJ apparaissent sans `/reload`. `/av stats` : pas de
   ralentissement à l'ouverture de la carte.
6. Recoché, ou module Carte désactivé : tous les PNJ reviennent. En combat : aucune erreur.
7. En-têtes PNJ des villes et Maîtres de métiers : « Tout afficher / Tout masquer » cochent/décochent la section
   (sans toucher « Toutes les classes » ni « Mes métiers ») ; mêmes boutons dans Options > AddOns ; grisés
   module désactivé.
8. Maîtres de classe > **Toutes les classes** : les maîtres des autres classes apparaissent (infobulle : leur classe).
9. **Mes métiers** : les maîtres de vos métiers apparaissent même décochés (cases inchangées) ; apprendre un
   métier puis rouvrir la carte : ses maîtres apparaissent.

## Checklist en jeu — capitales de près

1. Thunder Bluff et Orgrimmar aux zooms intermédiaires : plus de halo brun ni de bandes latérales autour de la ville ;
   la ville et son titre intacts (bord, mesas, bandeau du haut). Vérifier qu'aucune bande claire floue (l'ancien
   bandeau de Mulgore effacé) ne gêne entre les mesas.
2. En zoomant jusqu'au terrain de la minimap : Hurlevent, Orgrimmar, Thunder Bluff, Darnassus passent en fondu à la
   minimap (plus de carte de ville par-dessus) ; dézoomer : la carte de la ville revient.
3. Forgefer et Fossoyeuse au même zoom : la carte de la ville reste, la minimap intérieure (couloirs, salles) apparaît
   par-dessus en fondu. Option Carte « Terrain de la minimap de près » décochée : comportement d'avant.
4. `/av stats` : pas de ralentissement en entrant/sortant de ce zoom au-dessus d'une capitale.
5. Au zoom de la minimap : les noms des lieux (villages, camps, mines…) apparaissent en doré, en fondu avec le
   terrain, à peu près où la carte dessinée les écrivait ; dans la langue du jeu. Avec le brouillard : seulement les
   lieux explorés, et un lieu découvert prend son nom sans `/reload`. Option Carte « Noms des lieux de près »
   décochée, ou terrain décoché : aucun nom.

## Checklist en jeu — marqueurs de carte

Préparation : relancer le jeu (nouveaux fichiers et `.toc`).

1. Onglet **Marqueurs de carte** dans les options (après Donjons), même page dans Options > AddOns.
2. Ctrl+clic sur la carte : un marqueur (épingle) apparaît, suivi (flèche de Blizzard), sa fiche s'ouvre, saisie
   de la note ; icône, couleur, catégorie modifiables et vues aussitôt sur la carte. Entrée ou Échap ferme.
3. Survol : note, zone et coordonnées, catégorie. Clic : la fiche ; Maj+clic : lien dans le chat ; Alt+clic :
   supprimé ; clic droit : suivre / ne plus suivre.
4. Clic droit sur la carte : « Ajouter un marqueur ici », « Marqueurs de carte… » (aussi `/av markers`). Liste :
   catégories (case affichée/masquée, nouvelle, renommer, supprimer en deux clics), marqueurs de la catégorie
   (clic : la carte va dessus et ouvre la fiche ; croix : supprimé).
5. Exporter puis Importer un code (et un code venu d'OpenMap) : les marqueurs arrivent dans la catégorie choisie.
6. Partage, avec un autre joueur (AzerothVeil ou OpenMap) : groupe, guilde, cible ; il reçoit une fenêtre « Les
   ajouter / Ignorer », les marqueurs vont dans « Partagés avec moi ». Plusieurs marqueurs : envoyés un par un,
   sans message d'erreur de débit.
7. « Recevoir les marqueurs partagés » décoché : plus rien n'arrive. Module désactivé : plus de marqueurs sur la
   carte, Ctrl+clic pose le point de passage comme avant ; réactivé : tout revient. En combat : aucune erreur.

## Checklist en jeu — journal de quêtes (v0.6.1)

1. Page d'une quête : survol d'une récompense → infobulle à gauche du journal, à sa hauteur ; noms lisibles.
2. Suivre : flèche de navigation + ajout au suivi ; re-clic : flèche retirée, quête toujours suivie. Suivi plein
   et quête non suivie : bouton grisé, infobulle qui l'explique. Partager grisé hors groupe, avec sa raison.
3. Liste : recherche sur toute la ligne, « Quêtes (n/max) » et Tout replier / Tout déplier ; zone repliée :
   « Nom (suivies/total) ». Chaque option du module Quêtes retire son élément ; tout décoché : plus d'en-tête.
4. Police : Friz Quadrata partout (carte, journal, options, donjons, marqueurs), y compris sur les boutons
   survolés, cliqués ou grisés.

## Checklist en jeu — version 1.0

1. Page d'une quête : la page de Blizzard dans le journal (texte, cadre des récompenses, ses boutons) ; Retour
   revient à la liste ; en combat, notre page de secours ; la fenêtre d'un PNJ donneur de quête reste normale.
2. Options du journal : polices des titres / du texte (liste de choix), récompenses colorées, type en texte ou
   icône, objectifs, couleur par difficulté, surbrillance.
3. Carte : coordonnées joueur / curseur, noms des continents et des mers (sans lettres fantômes, dans la carte),
   minimap absente d'Ahn'Qiraj et de Zul'Gurub, zones de donjons non affichées de près sans l'option.
