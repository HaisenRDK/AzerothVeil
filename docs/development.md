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

**Écrans d'options (menu ⚙ de la carte = écran principal)**
3. Menu ⚙ de la carte : onglets « Transports » et « Amis & guilde » avec « Activer le module », son état,
   et toutes les options (bateaux, zeppelins, tram, tracés, suivi…) avec leurs icônes ; aucun bouton de
   renvoi. Module désactivé : options grisées et non cliquables, valeurs conservées.
3b. Changer une option dans le menu ⚙ : elle change aussitôt dans `/av config` et dans Options > AddOns >
   AzerothVeil (et inversement, depuis chacun des trois écrans).
3c. `/av config` ouvre la fenêtre (cadre Blizzard classique), `/av config` à nouveau la ferme ; croix et
   Échap la ferment ; Options > AddOns > AzerothVeil affiche directement la liste des modules et leurs réglages.
4. Déplacer la fenêtre par sa barre de titre ; impossible de la sortir de l'écran ; `/reload` : elle
   rouvre au même endroit.
5. Pour chaque module : titre et case « Activer le module » sur la même ligne. Décocher : réglages grisés
   avec leurs valeurs ; recocher : valeurs inchangées.
6. En combat : `/av config` puis Échap ne bloque aucune touche du jeu.

**Transports**
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
