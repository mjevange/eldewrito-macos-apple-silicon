# ElDewrito on Apple Silicon Macs

Getting [ElDewrito](https://eldewrito.info/) 0.7.1 — the community mod for the
cancelled *Halo Online* — running on an M-series Mac, with CI evidence for every
claim.

The [official guide](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)'s
macOS section is good, and its steps 2–8 are used here unchanged. Its step 1 is
one line — `Install GPTK (gameportingtoolkit)` — and **how you satisfy that line
decides whether the launcher runs at all.**

---

## The finding

> **The ElDewrito launcher will not start on Wine 7.7. It starts fine on Wine 11.16.**

Homebrew's prebuilt GPTK cask — the obvious free shortcut, and what most people
will reach for — ships **Wine 7.7 / GPTK 1.1** despite being published as version
`3.0-3`. Under it the launcher loads .NET, runs managed code, then dies with a
stack overflow. No window ever appears.

A **prebuilt, current** runtime fixes it with no compile.

| Runtime | Wine | Launcher |
|---|---|---|
| `gcenx/wine/game-porting-toolkit` (Homebrew cask) | 7.7 (2022) | ❌ stack overflow, no window |
| [`frankea/winecx-gptk`](https://github.com/frankea/winecx-gptk) `runtime-v4.6.4` | **11.16** | ✅ **boots, UI renders** |

Verified on GitHub `macos-15-arm64` runners: `RESULT: .NET OK`,
`RESULT: overflows=0`, and a screenshot of the installer wizard with a live
**Next** button.

**Ruled out along the way:** the .NET version is irrelevant — 6.0.29 (exactly
what the launcher requests) and 6.0.36 produce byte-identical crash logs under
7.7. So is the reported Windows version — `win10`, `win81` and `win7` all crash
identically, so the `ToastNotificationManager` failure in the log is a symptom,
not the cause.

---

## Status

| | |
|---|---|
| Launcher boots on Wine 11.16 | ✅ **Verified in CI** (screenshot + video) |
| Launcher fails on Wine 7.7 | ✅ Verified — 8 runs, every config |
| .NET 6 installs into the prefix | ✅ Verified (6.0.29 and 6.0.36) |
| Installer wizard advances | ✅ Verified |
| **Game files download over P2P** | ✅ **Verified — 5.17 MB/s, "15 minutes remaining"** |
| **The game itself renders** | ❓ **Not tested** — runners are VMs with no real GPU |

CI runners report `Apple M1 (Virtual)`. They can prove installation and launcher
startup; they can say nothing about D3DMetal/DXMT rendering. **If you get the
game running on real hardware, please open an issue** — that is the one gap that
cannot be closed here.

---

## Requirements

Apple Silicon (M1+), macOS Sonoma 14+, ~15 GB free. **Intel Macs cannot run
this** — GPTK requires Apple Silicon (it is built on D3DMetal and Rosetta 2), and
GPTK 4 dropped Intel entirely. Homebrew also no longer installs on Intel macOS,
which silently breaks most older Wine guides.

---

## Install

### 1. Get a working Wine

**Easiest — the Whisky fork (GUI).** [frankea/Whisky](https://github.com/frankea/Whisky)
v3.7.0 is the maintained fork of the discontinued Whisky, and it uses exactly the
runtime verified above. Install it, create a bottle, and point it at
`launcher.exe`. Note its bottles live under `~/Library/Containers/…`, so the
official guide's paths will not match literally.

**What CI verified — the runtime directly:**

```bash
softwareupdate --install-rosetta --agree-to-license

mkdir -p ~/ww
curl -fL -o ~/ww.tar.gz \
  https://github.com/frankea/winecx-gptk/releases/download/runtime-v4.6.4/Libraries.tar.gz
tar -xzf ~/ww.tar.gz -C ~/ww
xattr -dr com.apple.quarantine ~/ww

export WINE=~/ww/Libraries/Wine/lib/wine/x86_64-unix/wine
"$WINE" --version        # expect wine-11.16
```

459 MB, no compile. The bundle also ships **DXVK 1.10.3** and **DXMT 0.80** under
`Libraries/`, which is what the game will need for rendering.

> **Do not use** `brew install --cask gcenx/wine/game-porting-toolkit` for this.
> It installs cleanly and the launcher will never open. Also note Homebrew has
> **removed `--no-quarantine`** — passing it now errors out.

### 2. Prefix — *official guide step 4*

```bash
export WINEPREFIX=~/my-game-prefix
"$WINE" wineboot --init
sleep 40
"$WINE" cmd /c ver       # expect Microsoft Windows 10.x
mkdir -p "$WINEPREFIX/drive_c/stage"
```

The guide writes this path as `\Users~\my-game-prefix`. The `~` is shorthand for
your home directory — `/Users/<username>/`, never a literal `~` folder.

### 3. .NET 6 Desktop Runtime — *guide step 5*

```bash
cd "$WINEPREFIX/drive_c/stage"
curl -fL -o dotnet.exe \
  "https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x64.exe"
"$WINE" 'C:\stage\dotnet.exe' /quiet /norestart

ls "$WINEPREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App"
```

**Verify it rather than assume** — this step failed silently in several of our
runs. Any 6.0.x x64 Desktop Runtime works; the launcher requests app host
6.0.29 but 6.0.36 is equally fine.

### 4. Launcher — *guide step 6*

```bash
cd "$WINEPREFIX/drive_c/stage"
curl -fL -o launcher.exe \
  "https://github.com/eldewrito2/ElDewritoLauncher/releases/download/0.1.1/launcher.exe"
"$WINE" 'C:\stage\launcher.exe'
```

The wizard should appear. Install to `C:\Program Files\ElDewrito`, then expect
**two** separate permission prompts:

1. the **firewall** prompt the official guide mentions
2. a macOS prompt — *"Allow <app> to find devices on local networks?"* — which
   appears when the P2P download starts

**Both must be allowed.** The second is undocumented anywhere we could find, and
denying it stalls the torrent. Verified in CI: the download then runs at over
5 MB/s and reports a realistic time remaining.

### 5. Config and launch — *guide steps 7–8*

Set `Game.CEFGpuEnable 0` in
`drive_c/Program Files/ElDewrito/data/dewrito_prefs.cfg` (create it if absent),
then:

```bash
WINEESYNC=0 "$WINE" 'C:\Program Files\ElDewrito\eldorado.exe'
```

Plug a gamepad in **before** launching, per the official guide.

---

## If the launcher still gives you trouble

You do not strictly need it — its only job is fetching game files over
BitTorrent, and [eldewrito.info/download](https://eldewrito.info/download)
publishes a magnet link. Torrent natively on macOS, drop the folder into
`drive_c/Program Files/ElDewrito/`, and run `eldorado.exe` directly. A Windows
PC can also do the install and the folder be copied across.

---

## Quirks

Each of these cost a CI run. None is documented elsewhere that we could find.

- **The Homebrew cask's version is misleading.** Published `3.0-3`;
  `wine64 --version` reports `wine-7.7 (Game Porting Toolkit 1.1)`.
- **Homebrew removed `--no-quarantine`.** Nearly every Wine-on-Mac guide still
  tells you to pass it; it now fails with `invalid option`. Use
  `xattr -dr com.apple.quarantine` instead.
- **Homebrew refuses to install on Intel macOS**, which breaks the "install an
  x86_64 Homebrew" step every GPTK guide prescribes. `install.sh` exits and
  leaves you on the arm64 brew with no warning. Extracting the tarball to
  `/usr/local/homebrew` still works if you need it.
- **Plain Wine builds block on first run**, waiting for Wine Mono/Gecko dialogs
  nothing can click. `wine: created the configuration directory` is the only
  clue. Setting `WINEDLLOVERRIDES="mscoree,mshtml="` suppresses the prompts but
  **breaks .NET assembly loading** — do not use it for a real install.
- **The launcher is 64-bit** (`PE32+ x86-64`) and targets .NET app host 6.0.29.
- **`aka.ms` and the GitHub releases API both 403 under parallel load.** Pin
  fallback URLs in scripts.
- **macOS has no `timeout` command** — a hazard when adapting Linux scripts.

### Errata in the official guide

| Where | As written | Actually |
|---|---|---|
| step 3 | ".NET 6.0.2" | `6.0.32` per its own command; any 6.0.x works |
| step 5 | `gameportingtoolkit~/my-game-prefix` | missing space before `~` |
| step 6 | `'C:\Program_files\launcher.exe` | unclosed quote; lowercase `files` |
| step 4 | `\Users~\my-game-prefix` | means `/Users/<username>/` |

---

## CI

Three workflows run on GitHub's free Apple Silicon runners:

- **`gptk-probe.yml`** — the install chain end to end
- **`dotnet-matrix.yml`** — Wine version × .NET version
- **`mitigations.yml`** — Windows-version matrix, Apple's source-built GPTK, and
  the prebuilt runtime

All capture screenshots, 90 s of video, Wine logs and prefix listings as
artifacts.

```bash
gh workflow run mitigations.yml && gh run watch
```

Their value is catching drift: a renamed cask, a moved release asset or a new
runner image shows up here rather than on your Mac.

---

## Credits

- **The official ElDewrito guide** — [Google Doc](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit),
  macOS section credited to **@sahuntermech** on Discord. Everything below its
  step 1 is theirs and is correct; this repo only resolves which GPTK to use,
  which upstream changes turned into a trap after it was written.
- **ElDewrito** — [eldewrito.info](https://eldewrito.info/) ·
  [launcher](https://github.com/eldewrito2/ElDewritoLauncher)
- **frankea** — [Whisky fork](https://github.com/frankea/Whisky) and
  [winecx-gptk](https://github.com/frankea/winecx-gptk), whose prebuilt runtime
  is what makes this work
- **Gcenx** — [homebrew-wine](https://github.com/Gcenx/homebrew-wine),
  [macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Apple** — [Game Porting Toolkit](https://github.com/apple/game-porting-toolkit)

Community documentation. Not affiliated with ElDewrito's developers, Microsoft
or Apple.
