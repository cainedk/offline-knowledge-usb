#!/usr/bin/env bash
#
# make-usb-library.sh — build a portable, offline Kiwix library on a USB stick.
#
# What it does:
#   1. Downloads the newest version of each ZIM library from Kiwix (resumable).
#   2. Downloads the portable kiwix-serve web server for Linux, macOS and Windows.
#   3. Writes double-click launchers + a README onto the stick.
#
# Result: plug the stick into ANY computer, double-click the launcher for that
# OS, and the whole library opens in your browser at http://localhost:8888 —
# nothing to install, works offline — no hotspot, server or web host needed,
# just the ZIM files and a bundled reader.
#
# ---------------------------------------------------------------------------
# USAGE:
#   1. Format the stick as exFAT first (see "FORMATTING" below). This script does
#      NOT format anything — wiping the wrong device is unrecoverable, so that
#      step stays manual and deliberate.
#   2. Mount the stick, then run:
#        bash make-usb-library.sh /path/to/mounted/stick
#      e.g.  Linux: bash make-usb-library.sh /media/$USER/PUNKNUKE
#            macOS: bash make-usb-library.sh /Volumes/PUNKNUKE
#   You can stop (Ctrl+C) and re-run any time; finished files are skipped,
#   partial ones resume.
#
# FORMATTING (do this once, manually, BEFORE running):
#   exFAT is required — FAT32 can't hold the 118 GiB Wikipedia file.
#   Linux:  lsblk -o NAME,SIZE,MODEL,TRAN   # find YOUR stick, e.g. sdb
#           sudo wipefs -a /dev/sdX && sudo mkfs.exfat -n PUNKNUKE /dev/sdX
#           (needs the 'exfatprogs' package)
#   macOS:  diskutil list                   # find YOUR disk, e.g. disk4
#           diskutil eraseDisk ExFAT PUNKNUKE /dev/diskN
#   TRIPLE-CHECK the device name — it erases everything on it.
# ---------------------------------------------------------------------------

set -uo pipefail

# ======================= SETTINGS you may want to change ===================

# Wikipedia flavour:  maxi  = full articles + images (~118 GiB)   <- fits 256 GB
#                     nopic = full articles, no images (~30-55 GiB)
#                     mini  = intros + infoboxes only (~6 GiB)
WIKIPEDIA_FLAVOR="maxi"

PORT=8888                                   # browser port the viewer serves on
KIWIX_ZIM="https://download.kiwix.org/zim"
KIWIX_REL="https://download.kiwix.org/release/kiwix-tools"

# Libraries to include:  folder_on_kiwix | filename_base_without_date | label
# The script finds the newest dated file matching the base automatically, so you
# never edit dates. Trim or add lines freely.
#   NOTE: two bases are worth a sanity check against the live catalog the first
#   time — 'freecodecamp_en_all' and the 'zimgit-*' names. If one resolves to
#   nothing, the script prints the real filenames in that folder so you can fix
#   the one line.
CONTENT=(
  "wikipedia|wikipedia_en_all_${WIKIPEDIA_FLAVOR}|Wikipedia (English, ${WIKIPEDIA_FLAVOR})"
  "other|mdwiki_en_all_maxi|MDWiki (medical)"
  "ifixit|ifixit_en_all|iFixit repair guides"
  "freecodecamp|freecodecamp_en_all|freeCodeCamp"
  "wikivoyage|wikivoyage_en_all_maxi|Wikivoyage"
  "wiktionary|wiktionary_en_all_nopic|Wiktionary"
  "wikibooks|wikibooks_en_all_maxi|Wikibooks"
  "stack_exchange|electronics.stackexchange.com_en_all|SE: Electronics"
  "stack_exchange|raspberrypi.stackexchange.com_en_all|SE: Raspberry Pi"
  "stack_exchange|arduino.stackexchange.com_en_all|SE: Arduino"
  "stack_exchange|unix.stackexchange.com_en_all|SE: Unix"
  "stack_exchange|askubuntu.com_en_all|SE: Ask Ubuntu"
  "stack_exchange|superuser.com_en_all|SE: Super User"
  "stack_exchange|ham.stackexchange.com_en_all|SE: Ham radio"
  "stack_exchange|security.stackexchange.com_en_all|SE: Security"
  "stack_exchange|outdoors.stackexchange.com_en_all|SE: Outdoors"
  "stack_exchange|sustainability.stackexchange.com_en_all|SE: Sustainability"
  "stack_exchange|diy.stackexchange.com_en_all|SE: DIY"
  "stack_exchange|cooking.stackexchange.com_en_all|SE: Cooking"
  "other|zimgit-post-disaster_en|Survival: post-disaster"
  "other|zimgit-medicine_en|Survival: medicine"
  "other|zimgit-water_en|Survival: water"
  "other|zimgit-food-preparation_en|Survival: food prep"
  "other|zimgit-knots_en|Survival: knots"
)

# ===========================================================================

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: bash make-usb-library.sh /path/to/mounted/stick"
  echo "See the FORMATTING section at the top of this script first."
  exit 1
fi
if [ ! -d "$TARGET" ] || [ ! -w "$TARGET" ]; then
  echo "ERROR: '$TARGET' is not a writable directory. Is the stick mounted?"
  exit 1
fi

ZIM_DIR="$TARGET/zim"
APPS_DIR="$TARGET/apps"
mkdir -p "$ZIM_DIR" "$APPS_DIR" || { echo "ERROR: cannot create folders on target"; exit 1; }

# ---- dependency check -----------------------------------------------------
need=(); for c in curl aria2c tar unzip grep sed sort; do command -v "$c" >/dev/null 2>&1 || need+=("$c"); done
if [ ${#need[@]} -gt 0 ]; then
  echo "ERROR: missing tools: ${need[*]}"
  echo "  Debian/Ubuntu/Pi:  sudo apt update && sudo apt install -y curl aria2 tar unzip"
  echo "  macOS (Homebrew):  brew install curl aria2 gnu-tar unzip"
  exit 1
fi

# ---- filesystem sanity ----------------------------------------------------
fs="$(stat -f -c %T "$TARGET" 2>/dev/null || true)"
case "$fs" in
  msdos|vfat|fat*) echo "ERROR: target looks like FAT32 ('$fs'). Reformat as exFAT — FAT32 cannot hold the Wikipedia file."; exit 1;;
  exfat|fuseblk)   echo "Filesystem: $fs (OK).";;
  "")              echo "Filesystem: could not detect (continuing).";;
  *)               echo "Filesystem: $fs (not exFAT — fine on this machine, but exFAT is the cross-platform choice).";;
esac

# ---- space check ----------------------------------------------------------
avail_gib="$(df -Pk "$TARGET" 2>/dev/null | awk 'NR==2{printf "%.0f", $4/1048576}')"
[ -n "${avail_gib:-}" ] && echo "Free space on target: ~${avail_gib} GiB"
if [ -n "${avail_gib:-}" ] && [ "$WIKIPEDIA_FLAVOR" = "maxi" ] && [ "$avail_gib" -lt 190 ]; then
  echo "WARNING: < 190 GiB free. maxi Wikipedia + full library needs ~180 GiB."
  echo "         Consider WIKIPEDIA_FLAVOR=nopic, or a bigger stick. Continuing in 5s..."; sleep 5
fi

SKIPPED=()

# newest_zim FOLDER BASE  ->  prints newest "base_YYYY-MM.zim" or nothing
newest_zim() {
  local folder="$1" base="$2" esc
  esc="$(printf '%s' "$base" | sed 's/[.[\*^$/]/\\&/g')"
  curl -sL "${KIWIX_ZIM}/${folder}/" 2>/dev/null \
    | grep -oE "${esc}_[0-9]{4}-[0-9]{2}(\.[0-9]+)?\.zim" 2>/dev/null \
    | sort -u | sort | tail -1
}

# show_candidates FOLDER BASE  -> list real .zim names so a wrong base is obvious
show_candidates() {
  local folder="$1" base="$2" token="${2%%_*}"; token="${token%%.*}"
  echo "    files in /$folder/ matching '$token':"
  curl -sL "${KIWIX_ZIM}/${folder}/" 2>/dev/null \
    | grep -oE '[A-Za-z0-9._-]+\.zim' | grep -i "$token" | sort -u | head -20 | sed 's/^/      /'
}

download_zim() {
  local folder="$1" base="$2" label="$3" fname stem have g
  echo "----------------------------------------------------------------------"
  echo ">> $label"
  fname="$(newest_zim "$folder" "$base")"
  if [ -z "$fname" ]; then
    echo "    !! no file found for base '$base' in /$folder/ — SKIPPED"
    show_candidates "$folder" "$base"
    SKIPPED+=("$label ($folder/$base)")
    return
  fi
  # "already have it" ignores any .1/.2 rename suffix: a complete copy = no .aria2 beside it
  stem="${fname%.zim}"; stem="${stem%.[0-9]}"
  have=""; shopt -s nullglob
  for g in "$ZIM_DIR/${stem}"*.zim; do [ -f "$g" ] && [ ! -f "$g.aria2" ] && have="$g"; done
  shopt -u nullglob
  if [ -n "$have" ]; then echo "    already complete: $(basename "$have")"; return; fi
  rm -f "$ZIM_DIR/$fname.meta4"   # stale mirror list otherwise blocks resume
  echo "    downloading $fname"
  # no-rename + no-overwrite: resume the real file instead of spawning .1/.2 duplicates
  aria2c --continue=true --auto-file-renaming=false --allow-overwrite=false \
         -x4 -s4 --file-allocation=none \
         --max-tries=0 --retry-wait=15 --summary-interval=30 \
         --lowest-speed-limit=50K --timeout=60 --connect-timeout=60 \
         --console-log-level=warn --show-console-readout=true \
         -d "$ZIM_DIR" -o "$fname" \
         "${KIWIX_ZIM}/${folder}/${fname}" \
    || echo "    !! aria2 exited non-zero for $fname (re-run to resume)"
}

# ---- fetch the viewer (portable kiwix-serve) for each platform ------------
fetch_tools() {
  local plat_url_pat="$1" outdir="$2" isdir="$3" asset
  mkdir -p "$outdir"
  if [ -x "$outdir/kiwix-serve" ] || [ -f "$outdir/kiwix-serve.exe" ]; then
    echo "    viewer already present in $(basename "$outdir")"; return 0
  fi
  asset="$(curl -sL "${KIWIX_REL}/" 2>/dev/null | grep -oE "$plat_url_pat" | sort -V | tail -1)"
  if [ -z "$asset" ]; then echo "    !! could not find kiwix-tools asset for $(basename "$outdir")"; return 1; fi
  local tmp; tmp="$(mktemp -d)"
  echo "    fetching $asset"
  curl -sL -o "$tmp/$asset" "${KIWIX_REL}/${asset}" || { echo "    !! download failed"; rm -rf "$tmp"; return 1; }
  mkdir -p "$tmp/x"
  if [ "$isdir" = "zip" ]; then unzip -qo "$tmp/$asset" -d "$tmp/x"; else tar -xzf "$tmp/$asset" -C "$tmp/x"; fi
  # flatten EVERYTHING into outdir — the Windows build needs its ICU/other DLLs
  # sitting right next to kiwix-serve.exe, so keep all files, not just the binaries.
  find "$tmp/x" -type f -exec cp {} "$outdir/" \;
  chmod +x "$outdir"/kiwix-serve "$outdir"/kiwix-manage 2>/dev/null
  rm -rf "$tmp"
  [ -x "$outdir/kiwix-serve" ] || [ -f "$outdir/kiwix-serve.exe" ]
}

echo "======================================================================"
echo " Building portable library on: $TARGET"
echo " Wikipedia flavour: $WIKIPEDIA_FLAVOR   |   viewer port: $PORT"
echo "======================================================================"

echo; echo "### Step 1/3: viewer binaries"
fetch_tools 'kiwix-tools_linux-x86_64[0-9A-Za-z._-]*\.tar\.gz' "$APPS_DIR/linux-x86_64" tar
fetch_tools 'kiwix-tools_macos-x86_64[0-9A-Za-z._-]*\.tar\.gz' "$APPS_DIR/macos-x86_64" tar
fetch_tools 'kiwix-tools_macos-arm64[0-9A-Za-z._-]*\.tar\.gz'  "$APPS_DIR/macos-arm64"  tar   # best effort
fetch_tools 'kiwix-tools_win-x86_64[0-9A-Za-z._-]*\.zip'       "$APPS_DIR/windows-x86_64" zip

echo; echo "### Step 2/3: content (this is the long part — resumable)"
for row in "${CONTENT[@]}"; do
  IFS='|' read -r folder base label <<<"$row"
  download_zim "$folder" "$base" "$label"
done

echo; echo "### Step 3/3: launchers + README"

# ---------- Linux launcher ----------
cat > "$TARGET/start-linux.sh" <<EOF
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
BIN="\$DIR/apps/linux-x86_64/kiwix-serve"
PORT=$PORT
shopt -s nullglob
ZIMS=("\$DIR"/zim/*.zim)
if [ \${#ZIMS[@]} -eq 0 ]; then echo "No ZIM files in \$DIR/zim"; read -r -p "Enter to close"; exit 1; fi
chmod +x "\$BIN" 2>/dev/null
echo "Library starting at http://localhost:\$PORT   (close this window to stop)"
( sleep 2; xdg-open "http://localhost:\$PORT" >/dev/null 2>&1 ) &
exec "\$BIN" --port "\$PORT" "\${ZIMS[@]}"
EOF
chmod +x "$TARGET/start-linux.sh"

# ---------- macOS launcher (double-clickable) ----------
cat > "$TARGET/start-macos.command" <<EOF
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PORT=$PORT
xattr -dr com.apple.quarantine "\$DIR/apps" 2>/dev/null   # clear Gatekeeper flag
if [ "\$(uname -m)" = "arm64" ] && [ -x "\$DIR/apps/macos-arm64/kiwix-serve" ]; then
  BIN="\$DIR/apps/macos-arm64/kiwix-serve"
else
  BIN="\$DIR/apps/macos-x86_64/kiwix-serve"
fi
shopt -s nullglob
ZIMS=("\$DIR"/zim/*.zim)
if [ \${#ZIMS[@]} -eq 0 ]; then echo "No ZIM files in \$DIR/zim"; read -r -p "Enter to close"; exit 1; fi
chmod +x "\$BIN" 2>/dev/null
echo "Library starting at http://localhost:\$PORT   (close this window to stop)"
( sleep 2; open "http://localhost:\$PORT" ) &
exec "\$BIN" --port "\$PORT" "\${ZIMS[@]}"
EOF
chmod +x "$TARGET/start-macos.command"

# ---------- Windows launcher ----------
cat > "$TARGET/START-WINDOWS.bat" <<EOF
@echo off
setlocal enabledelayedexpansion
set "DIR=%~dp0"
set "BIN=%DIR%apps\\windows-x86_64\\kiwix-serve.exe"
set "PORT=$PORT"
set "ZIMS="
for %%f in ("%DIR%zim\\*.zim") do set "ZIMS=!ZIMS! "%%f""
if "!ZIMS!"=="" ( echo No ZIM files in %DIR%zim & pause & exit /b 1 )
echo Library starting at http://localhost:%PORT%  (close this window to stop)
start "" cmd /c "timeout /t 2 /nobreak >nul & start "" http://localhost:%PORT%"
"%BIN%" --port %PORT% !ZIMS!
pause
EOF

# ---------- README ----------
cat > "$TARGET/README.txt" <<EOF
OFFLINE LIBRARY  —  how to open it
==================================

Plug this stick into any computer, then:

  Windows    double-click  START-WINDOWS.bat
  Mac        double-click  start-macos.command
  Linux      run           ./start-linux.sh   (or double-click, "Run")

Your web browser opens at  http://localhost:$PORT  showing every book.
It's fully offline. To stop, just close the little black window.

First-time security prompts (normal for apps run off a USB stick):
  Windows  "Windows protected your PC"  ->  More info  ->  Run anyway
  Mac      if it's blocked: right-click start-macos.command -> Open -> Open

If nothing opens, type  http://localhost:$PORT  into your browser by hand.

Folders:  zim\  = the library files    apps\ = the Kiwix viewer (3 platforms)
EOF

echo; echo "======================================================================"
echo " DONE."
du -sh "$ZIM_DIR" 2>/dev/null | awk '{print " Library size: "$1}'
echo " Books on stick:"; ls -1 "$ZIM_DIR"/*.zim 2>/dev/null | sed 's#.*/#   #'
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo; echo " SKIPPED (base name needs checking — see the file lists printed above):"
  for s in "${SKIPPED[@]}"; do echo "   - $s"; done
fi
echo " Eject safely, then test the launcher for your OS."
echo "======================================================================"
