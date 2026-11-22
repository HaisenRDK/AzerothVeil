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
- [ ] Transports, pistes : maîtres de vol (aujourd'hui une catégorie « Lieux » du moteur), clic sur
  les bateaux en mouvement

## Étape 2 — Donjons

Approche validée : d'abord les données déjà présentes et les API natives, **sans dépendance à
DungeonJournal** ; l'intégration DungeonJournal sera étudiée ensuite. Les onglets quêtes / boss /
récompenses ne sont pas développés tant que ce n'est pas demandé.

- Module **Donjons** sur `Dungeon.lua` : entrées interactives, carte intérieure, étages, retour à la
  position précédente sur la carte du monde.
- Intégration **DungeonJournal** (`conflictsWithAddOns` / `Integrations/DungeonJournal.lua`) : vérifier
  l'API réelle de `_G.ForeverDungeonJournal_NS` avant tout usage ; si DJ est actif, il prend la main sur
  les clics des icônes de donjon.
- Sous-modules **Quêtes de donjon** et **Boss & butin** (dépendance `dungeons`, conflit avec DJ),
  présentés en deux onglets du panneau latéral de la carte (à la place du journal de quêtes).

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
