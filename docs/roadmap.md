# Roadmap d'AzerothVeil

## Étape 0 — Fondations (fait, v0.1.0)

- [x] Audit de PerfectMap 1.5.6, copie de référence locale
- [x] Adaptation minimale sous le nom AzerothVeil (style classique uniquement)
- [x] Cœur : Callbacks, Events, Database (schéma + migrations), ModuleManager, Bootstrap
- [x] Options centrales déclaratives dans la fenêtre Options du jeu
- [x] Module pilote « Amis & guilde » (`social`) piloté de bout en bout
- [x] Contrôles statiques, tests unitaires du cœur, déploiement WSL → Windows
- [ ] **Validation en jeu** (voir checklist de `docs/development.md`)

## Étape 1 — Consolidation

- Valider en jeu le comportement PerfectMap complet et le module `social` (activation/désactivation).
- Module **Transports** (le plus simple à extraire, déjà isolé) : `Vessels.lua` (ticker 0,8 s permanent),
  `Routes.lua`, catégories de pins bateau/zeppelin/tram/vol ; options « traits de voyage »
  (`routes`), live, partage. Introduire à cette occasion l'API « réglage moteur ↔ module ».
- Traduire en français les textes du moteur au fil des modifications.

## Étape 2 — Donjons

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
