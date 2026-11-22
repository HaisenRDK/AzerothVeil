# Roadmap d'AzerothVeil

## Étape 0 — Fondations (fait, v0.1.0)

- [x] Audit de PerfectMap 1.5.6, copie de référence locale
- [x] Adaptation minimale sous le nom AzerothVeil (style classique uniquement)
- [x] Cœur : Callbacks, Events, Database (schéma + migrations), ModuleManager, Bootstrap
- [x] Options centrales déclaratives
- [x] Module pilote « Amis & guilde » (`social`) piloté de bout en bout
- [x] Contrôles statiques, tests unitaires du cœur, déploiement WSL → Windows
- [x] Validation en jeu (confirmée par l'utilisateur)

## Étape 1 — Consolidation (v0.2.0)

- [x] Validation en jeu de la v0.1.0 (carte, module Amis & guilde)
- [x] Fenêtre d'options indépendante, déplaçable, en-tête générique des modules
- [x] Localisation centralisée et obligatoire (frFR/enUS), textes visibles du moteur traduits
- [x] Module **Transports** : un point par trajet comme OpenMap, tracés, suivi des bateaux conservé
  (et désactivable), partage, clic vers la destination
- [ ] Validation en jeu de la v0.2.0 (checklist de `docs/development.md`)
- [x] Maîtres de vol rattachés au module Transports (v0.3.1)
- [ ] Transports, piste : clic sur les bateaux en mouvement

## Étape 2 — Donjons (v0.4.0)

- [x] Audit (PerfectMap, OpenMap, DungeonJournal 2.1.3, OpenMap_NoDungeonMap) : `docs/dungeons-audit.md`
- [x] Module `dungeons` : entrées, sélecteur d'ailes, cartes intérieures, étages, boss, entrées/sorties,
  carte automatique à l'intérieur, retour au contexte précédent
- [x] Panneau latéral Quêtes / Boss (données du jeu et du moteur ; pas de butin ni de donneurs sans
  DungeonJournal)
- [x] Délégation à DungeonJournal (optionnelle, par numéro d'instance)
- [ ] Validation en jeu (checklist de `docs/development.md`)
- [ ] Pistes : noms des boss localisés (via le client, comme DungeonJournal), zoom/déplacement des
  cartes intérieures dessinées, carte de DungeonJournal intégrée si une API publique le permet un jour

## Étape 3 — Exploration

- [x] Module **Carte** : options de l'ancien onglet Carte du moteur, devenues déclaratives (migration 6)
- [x] Brouillard de guerre sur les zones inexplorées, rendu de la carte de Blizzard (art de base + morceaux explorés,
  `C_MapExplorationInfo`), option du module Carte
- [ ] Validation en jeu (checklist de `docs/development.md`)
- [ ] Pistes : mode « assombrir » (Darken d'OpenMap, `MapFog`),
  option liée à Questie (`requiresAddOns` d'un sous-réglage)

## Étape 3 bis — Icônes (v0.5.0)

- [x] Module **Icônes** : capitales, PNJ des villes, maîtres de métiers (anciens onglets Lieux / PNJ des villes /
  Métiers du moteur), migration 7
- [x] Option « PNJ des zones inexplorées » du module Carte
- [ ] Validation en jeu (checklist de `docs/development.md`)
- [x] « Tout afficher / Tout masquer » dans les en-têtes de section (déclaratif : `all = true` sur l'en-tête,
  `noAll` sur une option), « Mes métiers », « Toutes les classes » sous Maîtres de classe

## Pistes — capitales

- [ ] Orgrimmar : minimap souterraine (Fente de l'Ombre) au zoom des grottes. Aucune donnée disponible (ni OpenMap
  ni nous) : il faudrait extraire du client les images de minimap du WMO d'Orgrimmar (`WMOMinimapTexture`) et leur
  position, comme `tools/map-caves/minimap.py` d'OpenMap ; demande un lecteur CASC (outil à installer, accord requis).

## Étape 4 — Marqueurs (v0.6.0)

- [x] Module **Marqueurs de carte** : marqueurs illimités (note, icône, couleur), catégories libres affichables
  séparément, Ctrl+clic pour poser (suivi), fiche, liste par catégorie, lien dans le chat
- [x] Partage compatible OpenMap (préfixe `OpenMap`, messages `P1`, code `OMPINS1:`) : groupe, guilde, cible ;
  réception confirmée par notre fenêtre (option : ceux du groupe sans demander)
- [ ] Validation en jeu (checklist de `docs/development.md`)
- [ ] Pistes : partager l'icône entre utilisateurs d'AzerothVeil (OpenMap n'en a pas : il faudrait un message à part),
  marqueurs sur la minicarte

## Étape 4 bis — Journal de quêtes et police (v0.6.1, fait)

- Page d'une quête : infobulles des récompenses à côté du journal (comme le butin des boss), noms en couleur
  de qualité avec une ombre ; trois boutons : Suivre (flèche + suivi des objectifs, grisé si le suivi est
  plein), Partager (grisé avec sa raison), Abandonner.
- Liste : recherche sur toute la largeur, « Quêtes (n/max) » et Tout replier / Tout déplier dessous, compteur
  suivies/total après le nom d'une zone repliée ; quatre options du module Quêtes ; couleurs adoucies.
- Friz Quadrata TT dans tout l'addon (`Style.FontPath`, `Style.Friz`, `Style.FrizButton`).

## Questions ouvertes

- Permissions de Santiago Reyes / Exehn si AzerothVeil devait être distribué (cf. audit §1).
- Faut-il, à terme, des addons « Load on Demand » par module pour un vrai déchargement ?
