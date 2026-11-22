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
- Textes nouveaux via `L["English"]`, traduction dans `Locales/frFR.lua`.

## Commandes en jeu

| Commande | Effet |
|---|---|
| `/av` | ouvrir/fermer la carte |
| `/av config` | options centrales (modules) |
| `/av modules` | état des modules ; `/av modules enable|disable <nom>` |
| `/av stats` | performances du moteur |
| `/av help` | toutes les commandes |

## Checklist de validation en jeu (à faire après chaque déploiement important)

1. **PerfectMap désactivé** dans la liste des AddOns (sinon conflit sur M), AzerothVeil activé.
2. Aucune erreur Lua au chargement (`/console scriptErrors 1`).
3. M ouvre la carte AzerothVeil (cadre Blizzard classique, titre « AzerothVeil ») ; molette, drag,
   survol des zones, passage entre zones, zoom très proche (terrain) et très lointain (monde).
4. Icônes (vol, donjons, PNJ), clic sur un donjon → carte intérieure, clic droit → menu.
5. L ouvre le journal ; Échap ferme la carte ; en combat, la carte s'ouvre/ferme sans erreur.
6. Options > AddOns > AzerothVeil : module « Amis & guilde » listé ; décocher → réglages grisés,
   `/av modules` indique « désactivé » ; recocher → réglages identiques à avant.
7. `/reload` : l'état des modules et les réglages sont conservés.
8. `/av stats` : temps de rafraîchissement comparable à PerfectMap (`/pmap stats` dans PerfectMap).
