#!/bin/sh
# Builds dist/dnd5e.koplugin-<version>.zip for a GitHub release.
# The zip holds a single dnd5e.koplugin/ folder, which is what KOReader and
# Storefront expect. Run from the plugin folder: sh tools/release.sh
set -eu
version=$(sed -n 's/.*version = "\(.*\)".*/\1/p' _meta.lua)
[ -n "$version" ] || { echo "version not found in _meta.lua" >&2; exit 1; }
luajit tools/check_l10n.lua it >/dev/null || { echo "Italian translation incomplete: run luajit tools/check_l10n.lua it" >&2; exit 1; }
for f in *.lua l10n/*.lua spells/*.lua; do luajit -bl "$f" >/dev/null; done
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/dnd5e.koplugin/l10n" dist
cp _meta.lua main.lua dnd5e_*.lua LICENSE README.md "$stage/dnd5e.koplugin/"
cp l10n/*.lua "$stage/dnd5e.koplugin/l10n/"
mkdir -p "$stage/dnd5e.koplugin/spells"
cp spells/*.lua "$stage/dnd5e.koplugin/spells/"
out="$PWD/dist/dnd5e.koplugin-v$version.zip"
rm -f "$out"
(cd "$stage" && zip -qr "$out" dnd5e.koplugin)
echo "$out"
