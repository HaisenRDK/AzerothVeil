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

- Brouillard de guerre sur les zones inexplorées (`C_MapExplorationInfo`, compatible carte seamless),
  plusieurs modes d'affichage ; option liée à Questie (`requiresAddOns` d'un sous-réglage).

## Étape 4 — Marqueurs

- Points d'intérêt configurables avec les icônes de PerfectMap, catégories indépendantes.
- Compatibilité avec les marqueurs partagés d'OpenMap (préfixe `OpenMap`, protocole à étudier dans
  `.reference/OpenMap/Map/Pins.lua`) pour le groupe et la guilde.

## Questions ouvertes

- Permissions de Santiago Reyes / Exehn si AzerothVeil devait être distribué (cf. audit §1).
- Faut-il, à terme, des addons « Load on Demand » par module pour un vrai déchargement ?
