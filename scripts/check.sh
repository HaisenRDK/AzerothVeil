#!/usr/bin/env bash
# AzerothVeil — static checks, run before each deploy (scripts/deploy.sh runs it).
#   1. Lua 5.1 syntax of every file (luac -p)
#   2. the .toc: every file it lists exists, every .lua of the addon is listed
#   3. globals written: only the allowed ones (luac -l: SETGLOBAL)
#   4. leftover references to PerfectMap's names in code (paths, frames, SavedVariables)
#   5. the core's unit tests (tests/test_core.lua)
#   6. translations: every L["..."] of the code has its French entry (scripts/check_locales.py)
# Lua 5.1: lua5.1/luac5.1 from PATH, else the local copy in .tools/ (see docs/development.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="$ROOT/addon"
TOC="$ADDON/AzerothVeil.toc"
cd "$ROOT"

# --- Lua 5.1 ---------------------------------------------------------------
LUA="$(command -v lua5.1 || true)"
LUAC="$(command -v luac5.1 || true)"
if [[ -z "$LUA" || -z "$LUAC" ]]; then
	LOCAL="$ROOT/.tools/root/usr"
	if [[ -x "$LOCAL/bin/lua5.1" ]]; then
		export LD_LIBRARY_PATH="$LOCAL/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
		LUA="$LOCAL/bin/lua5.1"
		LUAC="$LOCAL/bin/luac5.1"
	else
		echo "Lua 5.1 not found: install lua5.1, or see docs/development.md (local copy in .tools/)." >&2
		exit 2
	fi
fi

errors=0
fail() { echo "  FAIL: $*"; errors=$((errors + 1)); }

mapfile -t LUA_FILES < <(cd "$ADDON" && find . -name '*.lua' | sed 's|^\./||' | sort)

# --- 1. syntax --------------------------------------------------------------
echo "[1/6] Lua 5.1 syntax (${#LUA_FILES[@]} files)"
for f in "${LUA_FILES[@]}"; do
	if ! out="$("$LUAC" -p "$ADDON/$f" 2>&1)"; then fail "syntax error in $f: $out"; fi
done

# --- 2. toc -----------------------------------------------------------------
echo "[2/6] .toc consistency"
mapfile -t TOC_FILES < <(tr -d '\r' < "$TOC" | grep -v '^\s*#' | grep -v '^\s*$' | sed 's|\\|/|g')
for f in "${TOC_FILES[@]}"; do [[ -f "$ADDON/$f" ]] || fail "listed in the .toc but missing: $f"; done
for f in "${LUA_FILES[@]}"; do
	printf '%s\n' "${TOC_FILES[@]}" | grep -qxF "$f" || fail "not listed in the .toc: $f"
done
grep -q '^## Interface: 16001' <(tr -d '\r' < "$TOC") || fail "the .toc's Interface isn't WoW Forever's 16001"
grep -q '^## SavedVariables: AzerothVeilDB' <(tr -d '\r' < "$TOC") || fail "the .toc's SavedVariables isn't AzerothVeilDB"

# --- 3. globals ---------------------------------------------------------------
echo "[3/6] globals written"
# the globals the addon may write: its namespace, SavedVariables, slash command, key binding, the
# Blizzard-required names; and the engine's (PerfectMap's) own ones, kept as they were
ALLOWED='^(AzerothVeil|AzerothVeilDB|AzerothVeil_Toggle|SLASH_AZEROTHVEIL1|SLASH_AZEROTHVEIL2|SlashCmdList|BINDING_HEADER_AZEROTHVEIL|BINDING_NAME_AZEROTHVEIL_TOGGLE|QUESTIE_TOWNSFOLK_KEYS)$'
for f in "${LUA_FILES[@]}"; do
	while read -r name; do
		[[ -z "$name" ]] && continue
		if ! [[ "$name" =~ $ALLOWED ]]; then fail "$f writes the global '$name'"; fi
	done < <("$LUAC" -l -p "$ADDON/$f" | awk '/SETGLOBAL/ { print $NF }' | sort -u)
done

# --- 4. PerfectMap leftovers ----------------------------------------------------
echo "[4/6] leftover PerfectMap names in code"
if grep -rnE 'AddOns\\\\PerfectMap|PerfectMapDB|PerfectMapFrame|_G\.PerfectMap|SLASH_PERFECTMAP|BINDING_[A-Z_]*PERFECTMAP' "$ADDON" --include='*.lua' --include='*.xml' --include='*.toc'; then
	fail "PerfectMap names left in code (above)"
fi

# --- 5. unit tests -----------------------------------------------------------
echo "[5/6] core unit tests"
if out="$("$LUA" tests/test_core.lua "$ADDON/" 2>&1)"; then
	echo "$out" | tail -1 | sed 's/^/  /'
else
	echo "$out" | grep -v '^  ok ' | sed 's/^/  /'
	fail "unit tests"
fi

# --- 6. translations ---------------------------------------------------------
echo "[6/6] translations"
python3 "$ROOT/scripts/check_locales.py" "$ADDON" || fail "untranslated texts"

if (( errors > 0 )); then
	echo "check: $errors problem(s)"
	exit 1
fi
echo "check: all good"
