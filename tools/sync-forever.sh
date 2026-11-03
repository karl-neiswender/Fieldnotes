#!/bin/sh
# One-way copy of the addon's runtime files from this checkout into live Forever, for testing
# there. Run it after edits; then /reload in game. Works on the Mac (rsync) and on the PC from Git
# Bash (robocopy, like sync-era.sh).
#
# Never a link: the CurseForge app recognises the addon by the X-Curse-Project-ID in its TOC and
# "updates" it by deleting the folder's contents. It once made Forever Goal Tracker
# delete its own checkout's Media and Fonts through a junction. A copy can only lose itself.
#
# The copy also drops the TOC's X-Curse-Project-ID line, so the app has nothing to recognise: the
# checkout keeps it (the release packager needs it), the game does not read it.
#
# Mirrors the .pkgmeta ignore list (development files, artwork originals, unused fonts).
#
# Refuses a destination that holds a .git folder: that is a whole checkout copied by hand (for
# example the PC's beta Interface folder pasted into _forever_), not a copy made by this script.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
    export MSYS_NO_PATHCONV=1
    SRC="$(cd "$(dirname "$0")/.." && pwd -W | sed 's#/#\\#g')"
    DST='C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Fieldnotes'

    link=$(powershell -NoProfile -Command "if (Test-Path -LiteralPath '$DST') { (Get-Item -LiteralPath '$DST' -Force).LinkType }" | tr -d '\r')
    if [ -n "$link" ]; then
        echo "Refusing: the Forever folder is a $link. Remove only the link (cmd /c rmdir), never its contents."
        exit 1
    fi
    if [ -d "$(cygpath -u "$DST")/.git" ]; then
        echo "Refusing: $DST holds a .git folder (a copied checkout). Delete that folder by hand, then rerun."
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
    TOC="$(cygpath -u "$DST")/Fieldnotes.toc"
    sed -i '/^## X-Curse-Project-ID/d' "$TOC"
    ;;
*)
    SRC="$(cd "$(dirname "$0")/.." && pwd)"
    DST='/Applications/World of Warcraft/_forever_/Interface/AddOns/Fieldnotes'

    if [ -L "$DST" ]; then
        echo "Refusing: the Forever folder is a symlink. Remove only the link (rm, no -r), never its contents."
        exit 1
    fi
    if [ -d "$DST/.git" ]; then
        echo "Refusing: $DST holds a .git folder (a copied checkout). Delete that folder by hand, then rerun."
        exit 1
    fi
    if [ ! -d "$(dirname "$DST")" ]; then echo "No AddOns folder at $(dirname "$DST")"; exit 1; fi

    rsync -a --delete \
        --exclude '/.git' --exclude '/.agents' --exclude '/.github' --exclude '/.claude' \
        --exclude '/tools' --exclude '/reports' --exclude '/research_notes' --exclude '/Screenshots' --exclude '/design' \
        --exclude '/Media/artwork' --exclude '/Media/final-images' \
        --exclude '/README.md' --exclude '/.gitignore' --exclude '/.pkgmeta' --exclude '/ROADMAP.md' \
        --exclude '/CLAUDE.md' --exclude '/AGENTS.md' --exclude '*-source.*' \
        --exclude '/Fonts/Cinzel-Regular.ttf' --exclude '/Fonts/OpenSans-Regular.ttf' \
        --exclude '/Fonts/OpenSans-Bold.ttf' --exclude '/Fonts/OpenSans-OFL.txt' \
        --exclude '/Media/logo.png' --exclude '.DS_Store' \
        "$SRC/" "$DST/" || { echo "rsync failed"; exit 1; }
    TOC="$DST/Fieldnotes.toc"
    sed -i '' '/^## X-Curse-Project-ID/d' "$TOC"
    ;;
esac
grep -m1 "## Version" "$TOC"
echo "Forever copy updated from $SRC"
