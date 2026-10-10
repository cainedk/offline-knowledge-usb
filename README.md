# Offline Knowledge USB

> A plug-and-play offline library on a USB stick — Wikipedia, medical, survival, repair and how-to knowledge that opens in any web browser with **no internet** and **nothing to install**. Built for grid-down, travel, and "just in case."

![License: MIT](https://img.shields.io/badge/license-MIT-blue)
![Shell: bash](https://img.shields.io/badge/shell-bash-green)
![Powered by Kiwix](https://img.shields.io/badge/content-Kiwix%20ZIM-orange)
![Platforms](https://img.shields.io/badge/runs%20on-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

---

## What this is

A single script that turns a 256 GB (or larger) USB stick into a self-contained offline reference library. It downloads curated [Kiwix](https://kiwix.org) `.zim` archives and bundles the portable Kiwix web-server for Windows, macOS and Linux **onto the stick itself**. Plug the stick into any computer, double-click one launcher, and the whole library opens at `http://localhost:8888`.

No install. No account. No network. When the internet isn't there — a storm, an outage, travel off-grid, or simply "what if" — a pocket-sized copy of the world's practical knowledge is worth having.

## What's inside

**Reference**
- Wikipedia — full English, with images
- Wiktionary — dictionary
- Wikibooks — open textbooks
- Wikivoyage — travel guides

**Medical & survival**
- MDWiki — medical reference
- Survival packs — post-disaster, medicine, water, food preparation, knots

**Repair & making**
- iFixit — device repair guides
- freeCodeCamp — learn to code

**Q&A (Stack Exchange)**
- Electronics · Raspberry Pi · Arduino · Unix · Ask Ubuntu · Super User · Ham radio · Security · Outdoors · Sustainability · DIY · Cooking

Everything is editable — trim or add entries in the `CONTENT` list near the top of the script.

## How it works

Kiwix packs entire websites into highly compressed `.zim` files; `kiwix-serve` reads them and serves them as a local website in your browser. This project just automates assembling the archives **and** the reader onto one stick, so any machine can browse it offline — no hotspot, server, or hosting required.

## Requirements

**To build (one-time):**
- A USB stick, **256 GB or larger**, formatted **exFAT**
- A Linux or macOS computer with: `bash`, `curl`, `aria2`, `tar`, `unzip`
- ~180 GB of downloads and a few hours (fully resumable)

**To use (anywhere):** just the stick + any Windows / macOS / Linux computer. Nothing to install.

## Build it

**1. Format the stick as exFAT.** Required — FAT32 can't hold the ~119 GB Wikipedia file. ⚠️ **This erases the stick — triple-check the device name.**

Linux:
```bash
lsblk -o NAME,SIZE,TRAN,MODEL        # find YOUR stick (TRAN=usb), e.g. sdb
sudo umount /dev/sdX?* 2>/dev/null   # unmount it first if auto-mounted
sudo wipefs -a /dev/sdX
sudo mkfs.exfat -n PUNKNUKE /dev/sdX
```

macOS:
```bash
diskutil list                        # find YOUR disk, e.g. disk4
diskutil eraseDisk ExFAT PUNKNUKE /dev/diskN
```

**2. Mount it and run the script against the mount point:**
```bash
# the path varies by OS/distro — e.g. /run/media/$USER/PUNKNUKE,
# /media/$USER/PUNKNUKE (Linux) or /Volumes/PUNKNUKE (macOS)
bash make-usb-library.sh /run/media/$USER/PUNKNUKE
```

Stop with `Ctrl+C` and re-run any time — finished files are skipped, partial ones resume.

> Tip: `bash make-usb-library.sh "$(findmnt -nro TARGET LABEL=PUNKNUKE)"` points at the stick wherever it happens to be mounted.

## Use it

Plug the stick into any computer and open the launcher for that OS:

| OS | Launcher |
| --- | --- |
| Windows | double-click `START-WINDOWS.bat` |
| macOS | double-click `start-macos.command` |
| Linux | run `./start-linux.sh` |

Your browser opens at `http://localhost:8888` with every book listed. Close the console window to stop.

First run may show a security prompt (Windows SmartScreen → *More info → Run anyway*; macOS Gatekeeper → right-click → *Open*). These are unsigned open-source binaries run from a stick — that's expected.

## Customizing

- **Wikipedia size** — set `WIKIPEDIA_FLAVOR` at the top of the script:
  - `maxi` — full articles + images (~119 GB)
  - `nopic` — full articles, no images (~30–55 GB)
  - `mini` — intros + infoboxes only (~6 GB)
- **Content** — edit the `CONTENT` list (`folder | filename-base | label`). The script finds the newest dated file automatically, and if a name has drifted it prints the real filenames in that folder so you can fix a single line.

## Size budget (256 GB stick ≈ 235 GiB usable)

| Content | Approx. |
| --- | --- |
| Wikipedia (maxi) | ~119 GB |
| freeCodeCamp | ~25–30 GB |
| Stack Exchange ×12 | ~10–15 GB |
| Everything else | ~12 GB |
| **Total** | **~170–180 GB** |

Switching Wikipedia to `nopic` frees ~85 GB.

## Troubleshooting

- **"Device or resource busy" when formatting** → the stick auto-mounted; `sudo umount /dev/sdX?*` first.
- **Mounts at a different path on each machine** → expected, and harmless: the launchers locate themselves, so only the *build* step needs the current path.
- **Download stalls at `0B` / 0 B/s** → a dead mirror. The script drops slow connections and retries other mirrors automatically; just let it run or re-run.
- **Duplicate `.1` / `.2` files** → prevented by design now; the script resumes the real file and recognises completed downloads regardless of suffix.
- **Windows: "icuuc74.dll not found"** → the viewer's DLLs must sit next to `kiwix-serve.exe`. The script bundles the full toolset; if you hit this, re-extract the Windows `kiwix-tools` zip **completely** into `apps\windows-x86_64\`.
- **"Unable to add the ZIM file" in the viewer** → that archive is corrupt/incomplete. Delete it and re-run the script to re-fetch.

## Updating

Re-run the script any time. Kiwix publishes fresh ZIMs roughly monthly; the script pulls the newest and skips what you already have.

## Credits

Content and the reader come from the [Kiwix](https://kiwix.org) project and the many communities behind each archive — Wikimedia, the Stack Exchange network, iFixit, freeCodeCamp, MDWiki and others. This repository only automates assembly.

## Licenses

- **The build script and this repository:** MIT — see [LICENSE](LICENSE).
- **The downloaded content is _not_ covered by this license.** Each `.zim` carries its own terms (Wikimedia & Stack Exchange are CC BY-SA; iFixit, freeCodeCamp and others have their own). Respect each source's license.

## Disclaimer

This is a convenience copy of public reference material for offline access. Medical, survival and safety content is **general information, not professional advice**, and no substitute for trained help or emergency services. Use your own judgment.
