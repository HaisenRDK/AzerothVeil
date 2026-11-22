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
5. Onglet Boss : liste, clic → bon étage affiché, repère qui clignote ; boss non placés indiqués.
6. Onglet Quêtes : avec une quête de ce donjon dans le journal (ex. Mortemines) : état, progression ;
   clic → récompenses avec infobulles du jeu ; Maj-clic → lien dans le chat ; sans quête : message.
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

