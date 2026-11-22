# Architecture d'AzerothVeil

## 1. Organisation des fichiers

```
AzerothVeil/                     dépôt Git (WSL)
├── addon/                       ← EXACTEMENT ce qui est chargé par WoW (déployé dans AddOns/AzerothVeil)
│   ├── AzerothVeil.toc          ordre de chargement
│   ├── Bindings.xml             raccourci clavier
│   ├── LICENSE.md, NOTICE.md    GPL v3 et mentions des tiers (obligatoires)
│   ├── Core/                    cœur AzerothVeil
│   │   ├── Init.lua             namespace _G.AzerothVeil, L[], SafeCall, IsAddOnLoaded
│   │   ├── Callbacks.lua        bus de messages entre modules
│   │   ├── Events.lua           frame d'événements centrale (handlers par propriétaire)
│   │   ├── Database.lua         AzerothVeilDB : schéma, valeurs par défaut, migrations
│   │   ├── ModuleManager.lua    enregistrement, cycle de vie, dépendances, réglages
│   │   └── Bootstrap.lua        chargé en dernier : réglages → modules, démarrage au login
│   ├── Locales/                 enUS (clés), frFR
│   ├── Engine/                  moteur cartographique hérité de PerfectMap 1.5.6 (noms de fichiers d'origine)
│   │   └── Data/                données (générées hors jeu par les outils de PerfectMap/OpenMap)
│   ├── Modules/                 modules fonctionnels (un fichier ou dossier par module)
│   ├── UI/                      composants d'interface AzerothVeil (options centrales)
│   ├── Media/                   ressources graphiques (PerfectMap + futures)
│   └── Tiles/                   pyramide de tuiles de la carte (60 Mo)
├── scripts/                     check.sh, deploy.sh, deploy.conf.example (deploy.local.conf ignoré)
├── tests/                       tests unitaires Lua 5.1 du cœur (stubs de l'API WoW)
├── docs/                        audit, architecture, roadmap, développement
├── .reference/                  (ignoré) sources originales intactes : PerfectMap, OpenMap, FlareUI, DungeonJournal
├── .tools/                      (ignoré) Lua 5.1 local
├── build/                       (ignoré) copie préparée avant déploiement
└── CLAUDE.local.md, .claude/    (ignorés) configuration de l'agent IA
```

Les **intégrations tierces** (Questie, DungeonJournal, OpenMap…) iront dans `addon/Integrations/`
quand la première sera écrite (le dossier n'est pas créé vide). Aujourd'hui celles de PerfectMap restent
dans `Engine/` (Quests.lua, Tint.lua, AddonPins.lua).

### Ordre de chargement (`AzerothVeil.toc`)

1. `Core/Init.lua` → `Locales/*` → `Core/Callbacks`, `Events`, `Database`, `ModuleManager`
2. `Engine/*` dans l'ordre exact de PerfectMap
3. `Modules/*` (chaque module s'enregistre ; rien ne s'exécute)
4. `UI/Options.lua`
5. `Core/Bootstrap.lua`

### Séquence de démarrage

```
chargement des fichiers ─ les modules s'enregistrent (aucun code fonctionnel)
ADDON_LOADED (Engine/Core.lua)
   └ Database.Load()  → migrations, AzerothVeilDB.engine = réglages PerfectMap (+ défauts)
   └ Fire SETTINGS_LOADED → Modules:LoadSettings()  (défauts des modules, état enabled)
PLAYER_LOGIN (Core/Bootstrap.lua)
   └ avertissement si PerfectMap est aussi chargé
   └ Modules:Start() → Evaluate() : Initialize + Enable des modules actifs
   └ Options.Register() → page dans Options > AddOns
```

## 2. Le cœur

- **Namespace** : un seul global, `_G.AzerothVeil` (le namespace `...` partagé par tous les fichiers, que
  le moteur appelle `FM`). Autres globaux strictement nécessaires : `AzerothVeilDB`, `/av`, raccourci
  clavier, frames nommées requises par les override bindings. `scripts/check.sh` refuse tout autre global.
- **Callbacks** (`ns.Callbacks`) : `Register(message, owner, fn)`, `Fire`, `UnregisterAll(owner)`. Les
  modules communiquent par messages, jamais en s'appelant directement.
- **Events** (`ns.Events`) : une frame centrale ; un événement du jeu est désenregistré dès que plus
  personne ne l'écoute (un module désactivé ne coûte rien).
- **Database** (`ns.Database`) : voir §4.

## 3. ModuleManager

### Déclaration (déclarative)

```lua
local M = ns.Modules:Register({
  name = "dungeons", title = L["Dungeons"], description = L["..."], order = 20,
  defaultEnabled = true,
  dependencies = { "markers" },                 -- modules AzerothVeil requis
  requiresAddOns = { },                         -- addons requis
  conflictsWithAddOns = { "ForeverDungeonJournal" }, -- si chargé, il prend le relais
  reloadOnDisable = false,                      -- true si hooks irréversibles
  settings = {
    { type = "header", label = L["Display"] },
    { key = "entrances", type = "toggle", default = true, label = ..., tooltip = ... },
    { key = "floors", type = "toggle", default = true, parent = "entrances" },
    { key = "scale", type = "range", default = 1, min = 0.5, max = 2, step = 0.05 },
    { key = "lastFloor", type = "hidden", default = 1 },
  },
})
function M:Initialize() end           -- une fois, juste avant le premier Enable
function M:Enable() end               -- démarre (événements, frames, hooks)
function M:Disable() end              -- s'arrête, libère
function M:Refresh(key, value) end    -- un réglage a changé pendant qu'il tourne
```

Aides disponibles dans un module : `self.db` (ses réglages), `self:Get/Set(key)`,
`self:IsOptionActive(key)`, `self:RegisterEvent(event, fn)`, `self:RegisterMessage(msg, fn)`,
`self:SendMessage(msg, ...)`, `self:After(s, fn)`, `self:NewTicker(s, fn)`, `self:Print(msg)`.

### Cycle de vie et règles

| État | Signification |
|---|---|
| `enabled` (sauvegardé) | ce que l'utilisateur a demandé |
| `active` (exécution) | enabled **et** addons requis présents **et** dépendances actives **et** aucun addon en conflit **et** joueur connecté |
| `unavailable` | demandé mais bloqué (raison affichée dans les options et `/av modules`) |

- **Un module désactivé n'exécute rien.** `Initialize` n'est jamais appelé pour un module qui n'a jamais
  tourné. Après `Disable`, le manager libère de lui-même événements, messages et timers pris via les aides
  du module (même si `Disable` les oublie).
- **Ses réglages sont conservés** et reviennent à la réactivation. `IsOptionActive` renvoie toujours
  `false` quand le module n'est pas actif, quelle que soit la valeur enregistrée (et `false` si l'option
  parente est éteinte).
- **Dépendances** : ordre topologique ; arrêt des dépendants avant leurs dépendances, démarrage dans
  l'ordre inverse ; les cycles sont refusés ; un module dont le `Enable` échoue est nettoyé et marqué
  indisponible jusqu'à sa prochaine désactivation/réactivation.

### Désactivation logique ≠ déchargement

WoW charge **tous** les fichiers listés dans le `.toc` au démarrage et ne peut pas en décharger un.
Désactiver un module **arrête son exécution** mais son code reste en mémoire (coût mémoire négligeable,
coût CPU nul). Conséquences :

- Le code d'un module ne doit rien faire **au chargement du fichier** à part s'enregistrer
  (pas de `CreateFrame` avec scripts, pas d'événement, pas de hook au niveau fichier).
- Les `hooksecurefunc` / `HookScript` **ne peuvent pas être retirés** : le hook doit tester
  `self:IsActive()` en premier, et le module déclarer `reloadOnDisable = true` ; les options affichent
  alors « Recharger l'interface ».
- Les préfixes de messages d'addon enregistrés le restent jusqu'au prochain /reload (sans effet).
- **/reload nécessaire** : nouveaux fichiers ou modification du `.toc` (redémarrage complet du jeu),
  désactivation d'un module `reloadOnDisable`. Un vrai déchargement nécessiterait des addons
  « Load on Demand » séparés : non retenu à ce stade (complexité, un dossier par module).

### Modules du moteur (migration progressive)

Le moteur PerfectMap n'est pas réécrit. Un sous-système devient piloté par un module en lui ajoutant
des points d'entrée `Start/Stop` et en faisant de ses `Layout/Tick` des retours immédiats quand il est
arrêté — c'est fait pour `Engine/Friends.lua` (module `social`). Les options correspondantes quittent
alors `FM.db` pour les réglages du module (migration de schéma).

## 4. Configuration et persistance

`AzerothVeilDB` (SavedVariables, compte) :

```lua
{ schema = 1,
  engine  = { ... },    -- réglages de PerfectMap, mêmes clés (FM.db)
  modules = { social = { enabled = true, settings = { show = true, share = false, asked = false } } },
  core    = { optionsModule = "social" } }
```

- Valeurs par défaut fusionnées à chaque chargement ; une valeur de mauvais type est remise par défaut.
- **Migrations** : `Database.migrations[n]` amène un schéma n-1 à n, exécutées une fois dans l'ordre ;
  un fichier venant d'une version plus récente n'est jamais rétrogradé. Migration 1 : déplacement des
  options amis/guilde du moteur vers le module `social`.
- Les anciennes migrations internes de PerfectMap (dans `Engine/Core.lua`) sont conservées telles quelles
  sur `engine`.

### Interface de configuration

`Options > AddOns > AzerothVeil` (ou `/av config`) : liste des modules à gauche (couleur = état), à
droite la description, la case « Activer ce module », l'état/raison, puis les réglages **générés depuis
la déclaration** (`header`, `toggle`, `range`). Réglages grisés mais visibles quand le module est off.
Composants natifs uniquement : `InsetFrameTemplate`, `UICheckButtonTemplate`,
`MinimalSliderWithSteppersTemplate`, `UIPanelButtonTemplate`, polices `GameFont*`.
Les réglages historiques de la carte restent dans le menu ⚙ de la carte.

## 5. Contrat des intégrations tierces

- Toujours **facultatives** : `requiresAddOns` pour un module qui n'a de sens qu'avec l'addon,
  `conflictsWithAddOns` quand l'autre addon doit prendre la main (ex. quêtes et boss de donjon quand
  DungeonJournal est actif).
- Ne jamais modifier les fichiers ni les SavedVariables d'un autre addon ; lecture seule de leur API
  publique, protégée par `pcall`, et **vérifiée dans leur code** avant usage.
- Testées au `PLAYER_LOGIN` (tous les addons sont chargés).

## 6. Traductions

`L["Texte anglais"]` renvoie la traduction du client ou la clé. `Locales/frFR.lua` ne s'exécute que sur un
client français. Le code nouveau passe par `L[]` ; les textes du moteur PerfectMap restent en anglais et
seront traduits au fil des modifications.

## 7. Compromis et limitations

- Couplage fort de `Map.lua` conservé (performances, stabilité) : les modules s'y branchent par des
  points d'entrée dédiés plutôt que par un système de calques générique — à introduire quand un 2ᵉ ou
  3ᵉ module de rendu le justifiera.
- Le code mort du style moderne (`Style.lua`, `FM.AskStyle`) est laissé en place (modification minimale).
- Les tuiles (60 Mo) et médias sont versionnés dans Git (dépôt local) pour un build reproductible.
- Tests unitaires limités au cœur (le moteur dépend de l'API graphique du client).
