# AzerothVeil

Addon de cartographie personnel pour **World of Warcraft Forever**, basé sur
PerfectMap 1.5.6 (CurseForge) de sokenn_ : carte du monde d'un seul tenant, zoom fluide,
style Blizzard classique, et une architecture modulaire pour ajouter des fonctions progressivement.

- `addon/` : l'addon tel que chargé par le jeu (déployé dans `Interface/AddOns/AzerothVeil`)
- `docs/` : [audit de PerfectMap](docs/perfectmap-audit.md), [architecture](docs/architecture.md),
  [roadmap](docs/roadmap.md), [développement](docs/development.md)
- `scripts/` : `check.sh` (contrôles), `deploy.sh` (déploiement WSL → Windows)
- `tests/` : tests unitaires du cœur (Lua 5.1)

En jeu : `/av` (carte), `/av config` (modules), `/av help`.

Licence : GNU GPL v3 (voir `LICENSE` et `addon/NOTICE.md` pour les composants tiers).
