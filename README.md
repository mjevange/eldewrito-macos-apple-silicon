# ElDewrito on Apple Silicon Macs

Research notes and CI evidence for installing [ElDewrito](https://eldewrito.info/)
0.7.1 — the community mod for the cancelled *Halo Online* — on an M-series Mac.

The [official guide](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)
has a macOS section and **it is not wrong**. Its steps 2–8 are precise and we
follow them unchanged. Its step 1 is a single line — `Install GPTK
(gameportingtoolkit)` — and that line hides four prerequisites plus a choice
that turns out to decide whether the launcher runs at all.

This repo documents that choice, with the CI runs that establish it.

---

## ⚠️ Read this first

**No install path here has been confirmed working end-to-end on real hardware.**
What follows separates what is proven from what is assumed. Claims are linked to
the CI runs that produced them, so you can check rather than trust.

| Claim | Status |
|---|---|
| The prebuilt GPTK cask installs cleanly on stock arm64 Homebrew | ✅ Verified in CI |
| .NET 6 installs into that prefix under Wine | ✅ Verified (6.0.29 and 6.0.36) |
| The launcher renders a window under that Wine | ✅ Verified (screenshot) |
| **The launcher crashes on startup under that Wine** | ❌ **Verified — it does not work** |
| x86_64 Homebrew is still installable (via tarball) | ✅ Verified |
| Apple's current GPTK runs the launcher | ❓ **Untested** — needs a Developer account |
| The game itself renders through D3DMetal | ❓ **Untested** — CI runners are VMs |

**If you have this working on real hardware, please open an issue** with your
Mac model, macOS version, GPTK version and what you did. That is the one gap CI
cannot close.

---

## The headline finding

The obvious free shortcut — Homebrew's prebuilt GPTK cask — **installs
perfectly and then cannot run the launcher.**

```
wine64 --version  →  wine-7.7 (Game Porting Toolkit 1.1)
```

Despite being published as version `3.0-3`, that cask ships **Wine 7.7 with GPTK
1.1 internals**, from 2022. Under it, `launcher.exe` loads .NET, reaches Windows
toast-notification code, and dies:

```
err:virtual:virtual_setup_exception stack overflow 4208 bytes in thread 0024
```

Tested across four cells and three runs, with .NET **6.0.29** (exactly the app
host version the launcher requests) and **6.0.36** (current). The logs are
byte-identical at 30,083 bytes with one stack overflow each. **The .NET version
makes no difference.**

Notably, with *no* .NET installed the launcher shows a clean
"install .NET Desktop Runtime" dialog — so Wine's windowing works fine. The
failure is specifically in managed .NET startup.

---

## Requirements

| | |
|---|---|
| **Chip** | Apple Silicon only. Intel Macs cannot run GPTK — see below |
| **macOS** | Sonoma 14.0+ (the cask refuses below this) |
| **Disk** | ~15 GB (game ~5 GB, plus prefix and runtimes) |

### Intel Macs

Apple's [Game Porting Toolkit](https://github.com/apple/game-porting-toolkit)
requires Apple Silicon, and GPTK 4 dropped Intel support to target Metal 4. It
is built on D3DMetal and Rosetta 2, neither of which exists on Intel. No
workaround exists.

Intel options are CrossOver, [Kegworks](https://github.com/Kegworks-App/Kegworks)
or Boot Camp — none covered here. Note that Homebrew itself now refuses to
install on Intel macOS (`Homebrew on macOS is only supported on Apple Silicon
processors!`), which breaks many older Wine guides.

---

## Choosing how to install GPTK

The official guide's step 1 can be satisfied two ways. They are not equivalent.

| | **Prebuilt cask** | **Apple's own GPTK** |
|---|---|---|
| Command | `brew install --cask gcenx/wine/game-porting-toolkit` | Developer account + DMG + formula build |
| Homebrew | stock arm64 | x86_64 (tarball install) |
| Time | ~2 minutes | ~75 min compile on an M1 |
| Wine | **7.7** (2022) | current |
| D3DMetal | ✅ bundled | ✅ |
| `gameportingtoolkit` wrapper | ❌ absent — needs shims | ✅ included |
| Runs the launcher | ❌ **no — crashes** | ❓ untested |

**Recommendation: use Apple's route**, i.e. the official guide's step 1 done
properly. The cask is faster and simpler, and we can show it does not work.

This is a reversal. The cask looked like a clear improvement until it was
actually tested — which is the entire reason this repo exists.

### Apple's route

Confirmed still viable in CI. `install.sh` refuses on x86_64, but extracting the
tarball bypasses that check and brew then runs under Rosetta:

```bash
softwareupdate --install-rosetta --agree-to-license
sudo mkdir -p /usr/local/homebrew && sudo chown -R "$(whoami)" /usr/local/homebrew
curl -fsSL https://github.com/Homebrew/brew/tarball/master \
  | tar xz --strip 1 -C /usr/local/homebrew

arch -x86_64 /usr/local/homebrew/bin/brew tap apple/apple
arch -x86_64 /usr/local/homebrew/bin/brew install apple/apple/game-porting-toolkit
```

Then mount Apple's GPTK DMG (free Developer account) and copy its bridge
libraries into the brew prefix with `ditto`, per Apple's instructions. That
gives you the real `gameportingtoolkit` wrappers, so **every command in the
official guide works verbatim** and nothing below is needed.

### The cask route, for reference

Documented because it is what most people will try, and because the failure is
worth knowing about rather than rediscovering:

```bash
brew install --cask gcenx/wine/game-porting-toolkit
xattr -dr com.apple.quarantine "/Applications/Game Porting Toolkit.app"
```

`--no-quarantine` **has been removed from Homebrew** — passing it fails with
`invalid option`. Clear the attribute by hand instead. The cask provides
`wine64` but not the `gameportingtoolkit` wrappers, so the guide's commands need
shims:

```bash
cat > /usr/local/bin/gameportingtoolkit <<'EOF'
#!/bin/sh
export WINEPREFIX="$1"; shift
exec wine64 "$@"
EOF
chmod +x /usr/local/bin/gameportingtoolkit
```

Expect the launcher to crash. The rest of the install works.

---

## If the launcher will not run

**You do not actually need it.** Its only job is downloading game files over
BitTorrent. [eldewrito.info/download](https://eldewrito.info/download) publishes
a torrent magnet alongside it.

1. Torrent the game files **natively on macOS** (Transmission) — no Wine involved
2. Copy the result into `~/my-game-prefix/drive_c/Program Files/ElDewrito/`
3. Set `Game.CEFGpuEnable 0` in `data/dewrito_prefs.cfg` (guide step 7)
4. Launch `eldorado.exe` with esync off (guide step 8)

This sidesteps the crash entirely and leaves only the game's own rendering in
question. A Windows PC can also do the install and the folder copied across.

---

## Quirks worth knowing

Things that cost us a CI run each, documented so they do not cost you an evening.

- **The cask's version is misleading.** Published as `3.0-3`; `wine64 --version`
  reports `wine-7.7 (Game Porting Toolkit 1.1)`.
- **Homebrew removed `--no-quarantine`.** Nearly every Wine-on-Mac guide still
  tells you to pass it. It now errors out.
- **Homebrew refuses to install on Intel macOS**, which silently breaks the
  "install an x86_64 Homebrew" step every GPTK guide prescribes — `install.sh`
  exits and leaves you on the arm64 brew with no warning. The tarball route
  still works.
- **Plain Wine builds block on first run.** A cold prefix pops Wine Mono/Gecko
  installer dialogs that nothing can click in CI, and
  `wine: created the configuration directory` is the only clue.
  `WINEDLLOVERRIDES="mscoree,mshtml="` helps but did not fully resolve it for us.
- **The launcher is 64-bit** (`PE32+ x86-64`) and targets .NET app host
  **6.0.29**. Any 6.0.x x64 Desktop Runtime installs fine; none fixes the crash.
- **`aka.ms` and the GitHub releases API both 403 under parallel load.** Pin a
  fallback URL in any script.

### Errata in the official guide

| Where | As written | Actually |
|---|---|---|
| step 3 | ".NET 6.0.2" | `6.0.32` — matches its own command; any 6.0.x works |
| step 5 | `gameportingtoolkit~/my-game-prefix` | missing the space before `~` |
| step 6 | `'C:\Program_files\launcher.exe` | unclosed quote; lowercase `files` |
| step 4 | `\Users~\my-game-prefix` | shorthand for `/Users/<username>/` — not a literal `~` folder |

---

## The CI probes

Two workflows, run on GitHub's Apple Silicon runners (free on public repos):

- **`gptk-probe.yml`** — the install chain end to end: architecture, Rosetta,
  Homebrew, cask conflicts, GPTK, prefix, shims, .NET, launcher download, and a
  screenshot of whatever renders.
- **`dotnet-matrix.yml`** — a 2×2 of Wine version against .NET version,
  reporting window detection, stack-overflow count, log size and the exact .NET
  version installed.

Both upload screenshots, Wine logs and prefix listings as artifacts.

```bash
gh workflow run dotnet-matrix.yml && gh run watch
```

**Limitation:** the runners report `Apple M1 (Virtual)`. They have a
paravirtualised GPU, so they can verify installation and launcher startup but
say nothing about D3DMetal rendering.

---

## Credits

- **The official ElDewrito guide** — [Google Doc](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit),
  linked from [eldewrito.org/guide](https://www.eldewrito.org/guide). Its macOS
  section is credited to **@sahuntermech** on Discord. This repo supplements
  that work; where we differ, it is because upstream changed after it was
  written, not because it was wrong.
- **ElDewrito** — [eldewrito.info](https://eldewrito.info/) ·
  [launcher source](https://github.com/eldewrito2/ElDewritoLauncher)
- **Apple Game Porting Toolkit** — [apple/game-porting-toolkit](https://github.com/apple/game-porting-toolkit)
- **Gcenx** — [homebrew-wine](https://github.com/Gcenx/homebrew-wine) and
  [macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)

Community documentation. Not affiliated with ElDewrito's developers, Microsoft
or Apple. ElDewrito is free, with no donations or microtransactions.
