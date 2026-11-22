#!/usr/bin/env bash
# AzerothVeil — deploy from WSL to the WoW Forever client on Windows.
#
#   scripts/deploy.sh               checks, build, copy to <AddOns>/AzerothVeil
#   scripts/deploy.sh --dry-run     shows what would be copied / removed, changes nothing
#   scripts/deploy.sh --skip-checks no scripts/check.sh first (not recommended)
#
# The AddOns folder is read from scripts/deploy.local.conf (not versioned; copy deploy.conf.example).
# Safety:
#   * the target must be <...>/<flavor>/Interface/AddOns of a WoW install (Wow.exe two levels up), the
#     flavor folder being WoW Forever's (EXPECTED_FLAVOR, "_forever_" by default);
#   * only <AddOns>/AzerothVeil is written to. Files removed from the addon are removed there too
#     (rsync --delete), strictly inside that folder, and only if it is AzerothVeil's (its .toc is there,
#     or it's empty / new). No other addon's folder is ever touched; no symlink is followed or made.
#   * copy only (no symlinks between WSL and Windows), no admin rights, nothing changed in Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/scripts/deploy.local.conf"
ADDON_NAME="AzerothVeil"
SRC="$ROOT/addon"
BUILD="$ROOT/build/$ADDON_NAME"

DRY_RUN=0
SKIP_CHECKS=0
for a in "$@"; do
	case "$a" in
		--dry-run|-n) DRY_RUN=1 ;;
		--skip-checks) SKIP_CHECKS=1 ;;
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
		*) echo "Unknown option: $a" >&2; exit 2 ;;
	esac
done

die() { echo "deploy: $*" >&2; exit 1; }

# --- configuration ------------------------------------------------------------
[[ -f "$CONF" ]] || die "no $CONF. Copy scripts/deploy.conf.example to scripts/deploy.local.conf and set WOW_ADDONS_DIR."
WOW_ADDONS_DIR=""
EXPECTED_FLAVOR="_forever_"
# shellcheck source=/dev/null
source "$CONF"
[[ -n "$WOW_ADDONS_DIR" ]] || die "WOW_ADDONS_DIR is empty in $CONF"

# --- the target: WoW Forever's AddOns folder ------------------------------------
[[ -d "$WOW_ADDONS_DIR" ]] || die "not a folder: $WOW_ADDONS_DIR (is the Windows drive mounted?)"
ADDONS="$(realpath -e "$WOW_ADDONS_DIR")" || die "can't resolve $WOW_ADDONS_DIR"
[[ "$(basename "$ADDONS")" == "AddOns" ]] || die "$ADDONS doesn't end in AddOns"
INTERFACE="$(dirname "$ADDONS")"
[[ "$(basename "$INTERFACE")" == "Interface" ]] || die "$ADDONS isn't inside an Interface folder"
FLAVOR_DIR="$(dirname "$INTERFACE")"
[[ -f "$FLAVOR_DIR/Wow.exe" || -f "$FLAVOR_DIR/WowClassic.exe" ]] || die "no Wow.exe in $FLAVOR_DIR: not a WoW install"
[[ "$(basename "$FLAVOR_DIR")" == "$EXPECTED_FLAVOR" ]] || die "$FLAVOR_DIR isn't the $EXPECTED_FLAVOR client (EXPECTED_FLAVOR in $CONF)"
[[ -w "$ADDONS" ]] || die "no write permission on $ADDONS"

TARGET="$ADDONS/$ADDON_NAME"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
	[[ -L "$TARGET" ]] && die "$TARGET is a symlink: remove it by hand first (this script only copies)"
	[[ -d "$TARGET" ]] || die "$TARGET exists and isn't a folder"
	[[ "$(realpath -e "$TARGET")" == "$ADDONS/$ADDON_NAME" ]] || die "$TARGET resolves elsewhere"
	if [[ -n "$(ls -A "$TARGET")" && ! -f "$TARGET/$ADDON_NAME.toc" ]]; then
		die "$TARGET isn't empty and has no $ADDON_NAME.toc: not ours, left alone"
	fi
fi

# --- checks -------------------------------------------------------------------------
if (( SKIP_CHECKS == 0 )); then
	echo "== checks"
	"$ROOT/scripts/check.sh" || die "checks failed: nothing deployed (fix them, or --skip-checks)"
fi

# --- build: only what the game loads -------------------------------------------------
echo "== build -> build/$ADDON_NAME"
[[ -f "$SRC/$ADDON_NAME.toc" ]] || die "no $SRC/$ADDON_NAME.toc"
mkdir -p "$BUILD"
# (the game's files only: Lua, XML, the .toc, art, the license and notice; never AI, Git, tests or tools)
rsync -rt --delete --delete-excluded \
	--exclude='.*' \
	--exclude='CLAUDE*.md' --exclude='AGENTS.md' --exclude='AGENT.md' --exclude='GEMINI.md' \
	--exclude='*.sh' --exclude='*.py' --exclude='*.js' --exclude='*.conf' --exclude='*.example' \
	--exclude='tests/' --exclude='docs/' --exclude='scripts/' --exclude='tools/' \
	--exclude='README*' --exclude='*.bak' --exclude='*~' \
	"$SRC/" "$BUILD/"
# (no other markdown than the license and the notice)
find "$BUILD" -name '*.md' ! -name 'LICENSE.md' ! -name 'NOTICE.md' -delete
FILES=$(find "$BUILD" -type f | wc -l)
SIZE=$(du -sh "$BUILD" | cut -f1)
echo "   $FILES files, $SIZE"

# --- copy -------------------------------------------------------------------------------
echo "== deploy -> $TARGET"
RSYNC_OPTS=(-rt --delete --no-perms --no-owner --no-group --modify-window=2 --itemize-changes)
(( DRY_RUN )) && RSYNC_OPTS+=(--dry-run)
if (( DRY_RUN == 0 )); then mkdir -p "$TARGET" || die "can't create $TARGET"; fi
CHANGES="$(rsync "${RSYNC_OPTS[@]}" "$BUILD/" "$TARGET/")" || die "copy failed (permissions? is WoW holding a file?)"
N_CHANGED=$(printf '%s\n' "$CHANGES" | grep -c '^[<>c]f' || true)
N_DELETED=$(printf '%s\n' "$CHANGES" | grep -c '^\*deleting' || true)
if (( DRY_RUN )); then
	printf '%s\n' "$CHANGES" | grep -E '^([<>c]f|\*deleting)' | head -50 || true
	echo "== dry run: $N_CHANGED file(s) would be copied, $N_DELETED removed. Nothing changed."
else
	echo "== done: $N_CHANGED file(s) copied, $N_DELETED removed."
	echo "   In game: /reload (a new or renamed file, or a .toc change, needs the game restarted)."
fi
