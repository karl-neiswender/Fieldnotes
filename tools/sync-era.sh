#!/bin/sh
# One-way copy of the addon's runtime files from this checkout into Classic Era on the PC, for
# testing there. Run it after edits; then /reload in game.
#
# Never a link: the CurseForge app recognises the addon by the X-Curse-Project-ID in its TOC and
# "updates" it by deleting the folder's contents. It once made Forever Goal Tracker
# delete its own checkout's Media and Fonts through a junction. A copy can only lose itself.
#
# The copy also drops the TOC's X-Curse-Project-ID line, so the app has nothing to recognise: the
# checkout keeps it (the release packager needs it), the game does not read it.
#
# Mirrors the .pkgmeta ignore list (development files, artwork originals, unused fonts).
export MSYS_NO_PATHCONV=1
SRC="$(cd "$(dirname "$0")/.." && pwd -W | sed 's#/#\\#g')"
DST='C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\Fieldnotes'

link=$(powershell -NoProfile -Command "if (Test-Path -LiteralPath '$DST') { (Get-Item -LiteralPath '$DST' -Force).LinkType }" | tr -d '\r')
if [ -n "$link" ]; then
    echo "Refusing: the Era folder is a $link. Remove only the link (cmd /c rmdir), never its contents."
    exit 1
fi

robocopy "$SRC" "$DST" /MIR /NFL /NDL /NJH /NP /R:1 /W:1 \
    /XD .git .agents .github .claude tools reports research_notes Screenshots design \
        "$SRC\\Media\\artwork" "$SRC\\Media\\final-images" \
    /XF README.md .gitignore .pkgmeta ROADMAP.md CLAUDE.md AGENTS.md "*-source.*" \
        Cinzel-Regular.ttf OpenSans-Regular.ttf OpenSans-Bold.ttf OpenSans-OFL.txt logo.png
code=$?
# robocopy: 0-7 are success (8 and up are failures)
if [ "$code" -ge 8 ]; then echo "robocopy failed ($code)"; exit "$code"; fi
sed -i '/^## X-Curse-Project-ID/d' "$(cygpath -u "$DST")/Fieldnotes.toc"
grep -m1 "## Version" "$DST\\Fieldnotes.toc"
echo "Era copy updated from $SRC"
