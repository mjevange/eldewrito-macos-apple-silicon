# ElDewrito on Apple Silicon Macs

Installing [ElDewrito](https://eldewrito.info/) 0.7.1 — the community mod for the
cancelled *Halo Online* — on an M-series Mac, via Apple's Game Porting Toolkit.

The [official guide](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)
has a macOS section, and it is correct as far as it goes. Its first step is
`Install GPTK (gameportingtoolkit)` — one line that expands into four
prerequisites it never states. This repo fills that gap, keeps the rest of the
official steps verbatim, and runs the install chain in CI so you can see whether
it still resolves today.

---

## ⚠️ Verification status

**Read this before following the guide.** Honesty about what has actually been
tested matters more than looking authoritative.

| Part | Status |
|---|---|
| Steps 1–8 (Rosetta, x86_64 Homebrew, GPTK cask, prefix, .NET, launcher binary) | 🟡 Exercised headlessly in CI — see the Actions tab |
| Step 9 (launcher wizard UI renders) | 🟡 Screenshot attempted in CI; may be limited by the runner's display |
| Steps 10–11 (config tweak, game actually renders and plays) | 🔴 **Untested.** No hardware confirmation yet |
| Official guide's own macOS steps | 🔴 A single community contribution; no independent corroboration found |

Every individual component here is well-trodden — GPTK, .NET 6 under Wine,
DirectX 11 via D3DMetal. Their *combination* for this specific game is not.
**If you get it working, or it fails, please open an issue** with your Mac model,
macOS version and where it broke. That's how this stops being guesswork.

---

## Requirements

| | |
|---|---|
| **Chip** | Apple Silicon (M1 or later). **Intel Macs cannot run this** — see below |
| **macOS** | Sonoma 14.0 or later (GPTK requires it) |
| **Disk** | ~15 GB free (game is ~5 GB; prefix and runtimes take the rest) |
| **Network** | The launcher downloads game files over BitTorrent |

### Intel Macs

Apple's [Game Porting Toolkit](https://github.com/apple/game-porting-toolkit)
lists "a Mac with Apple silicon" as a hard prerequisite, and GPTK 4 dropped
Intel support entirely to target Metal 4. GPTK is built on D3DMetal plus
Rosetta 2, neither of which exists on Intel. There is no flag or workaround.

Intel users' options are CrossOver, [Kegworks](https://github.com/Kegworks-App/Kegworks)
(which supports Intel and ships `wine32on64`), or Boot Camp. Those paths are out
of scope here and are not covered by this repo's CI.

---

## The one rule that causes most failures

GPTK's Wine is an **x86_64** binary, so every `brew` command must run inside a
Rosetta shell against the **Intel** Homebrew in `/usr/local` — not the arm64
Homebrew in `/opt/homebrew` that an M-series Mac normally has.

Opening a new Terminal tab puts you back on arm64 and silently uses the wrong
Homebrew. If you reopen Terminal mid-install, re-run:

```bash
arch -x86_64 zsh
eval "$(/usr/local/bin/brew shellenv)"
```

---

## Install

### 0. Verify the machine

```bash
uname -m                    # must print arm64
sw_vers -productVersion     # must be 14.0 or higher
xcode-select --install      # skip if already present
```

### 1. Rosetta 2 and the x86_64 Homebrew

```bash
# check first — often already installed
/usr/bin/pgrep -q oahd && echo "Rosetta present" || echo "not installed"

softwareupdate --install-rosetta --agree-to-license
arch -x86_64 zsh
```

Installing Rosetta is **not** a macOS update — it adds a ~300 MB system
component through the software-update channel, changes no OS version, and needs
no reboot.

Then, **inside that Rosetta shell**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/usr/local/bin/brew shellenv)"

brew --prefix               # MUST print /usr/local
```

Verify that last line before continuing. The two Homebrews coexist fine.

### 2. Remove conflicting Wine installs

```bash
brew list --cask | grep -E 'wine|crossover|kegworks'
```

The GPTK cask conflicts with `wine-crossover`, `wine-stable`, `wine@devel` and
`wine@staging`. Uninstall any it finds with `brew uninstall --cask <name>`.

### 3. Game Porting Toolkit · *official guide step 1*

```bash
brew install --cask --no-quarantine gcenx/wine/game-porting-toolkit
which wine64
```

It is a **cask**, not a formula. This is [gcenx's](https://github.com/Gcenx/homebrew-wine)
prebuilt GPTK 3.0, which avoids both the Apple Developer account and the
~75-minute source build that Apple's own `apple/apple` tap requires on an M1.
`--no-quarantine` is required or Gatekeeper reports Wine as damaged.

It installs `Game Porting Toolkit.app` and symlinks `wine64`,
`wine64-preloader` and `wineserver` into `/usr/local/bin`.

### 4. Restore the official guide's command syntax

The prebuilt cask provides `wine64` but **not** the `gameportingtoolkit` wrapper
scripts — those ship in Apple's DMG. These two shims recreate them so every
command the official guide prints works as written:

```bash
cat > /usr/local/bin/gameportingtoolkit <<'EOF'
#!/bin/sh
export WINEPREFIX="$1"; shift
export WINEDEBUG=-all
exec wine64 "$@"
EOF

cat > /usr/local/bin/gameportingtoolkit-no-esync <<'EOF'
#!/bin/sh
export WINEPREFIX="$1"; shift
export WINEESYNC=0
export WINEDEBUG=-all
exec wine64 "$@"
EOF

chmod +x /usr/local/bin/gameportingtoolkit /usr/local/bin/gameportingtoolkit-no-esync
```

Prefix with `sudo` if the writes are refused. This step has no counterpart in
the official guide; if you install GPTK Apple's way instead, skip it.

### 5. Create the prefix · *official guide step 4*

```bash
gameportingtoolkit ~/my-game-prefix winecfg
```

Set **Windows version** to **Windows 10**, Apply, close. Then:

```bash
mkdir -p ~/my-game-prefix/drive_c/Program_Files
```

> The official guide writes this path as `\Users~\my-game-prefix\Program_Files`.
> The `~` is shorthand for your home directory — `/Users/<username>/`. Do not
> create a folder literally named `~`.

**Smoke-test now, before downloading 5 GB:**

```bash
gameportingtoolkit ~/my-game-prefix winver
```

A window reporting *Windows 10* means Rosetta, Wine, the prefix and the shims
all work. If this fails, everything downstream would too — fix it here, where
nothing is invested.

### 6. Stage the installers · *official guide steps 2–3*

Download:

- `launcher.exe` from [eldewrito.info/download](https://eldewrito.info/download)
- the **x64 Desktop Runtime** from [.NET 6.0 downloads](https://dotnet.microsoft.com/en-us/download/dotnet/6.0) — not the SDK, not ASP.NET

```bash
cp ~/Downloads/launcher.exe ~/my-game-prefix/drive_c/Program_Files/
cp ~/Downloads/windowsdesktop-runtime-6.0.*-win-x64.exe ~/my-game-prefix/drive_c/Program_Files/

ls ~/my-game-prefix/drive_c/Program_Files/   # note the exact .NET filename
```

### 7. Install .NET · *official guide step 5*

```bash
gameportingtoolkit ~/my-game-prefix 'C:\Program_Files\windowsdesktop-runtime-6.0.32-win-x64.exe'
```

Substitute the filename `ls` showed. .NET 6 is past end-of-support, so Microsoft
may serve a later 6.0.x — any 6.0.x x64 Desktop Runtime works.

### 8. Install ElDewrito · *official guide step 6*

```bash
gameportingtoolkit ~/my-game-prefix 'C:\Program_Files\launcher.exe'
```

In the wizard:

- set the install path to `C:\Program Files\ElDewrito`
- **allow the firewall prompt** — deny it and the torrent sits at 0% with no useful error
- let the ~5 GB peer-to-peer download finish

> Note the deliberate difference between `Program_Files` (underscore — your
> staging folder) and `Program Files` (space — where the game installs). Both
> are correct; they are different directories.

**Optional: back up the prefix first.** Everything above is slow to redo:

```bash
tar -czf ~/prefix-clean.tgz -C ~ my-game-prefix
```

Restore with `rm -rf ~/my-game-prefix && tar -xzf ~/prefix-clean.tgz -C ~`.

### 9. Disable the launcher's GPU compositing · *official guide step 7*

```bash
nano ~/my-game-prefix/drive_c/Program\ Files/ElDewrito/data/dewrito_prefs.cfg
```

Set — or add, creating the file if absent:

```
Game.CEFGpuEnable 0
```

This turns off hardware acceleration in the game's embedded Chromium UI, which
otherwise renders black under Wine.

### 10. Play · *official guide step 8*

```bash
gameportingtoolkit-no-esync ~/my-game-prefix 'C:\Program Files\ElDewrito\eldorado.exe'
```

**Plug your gamepad in before launching**, per the official guide. To update
later, re-run step 8's launcher command — it self-updates over the same P2P
network.

### Optional: a double-click launcher

```bash
cat > ~/Desktop/Play\ ElDewrito.command <<'EOF'
#!/bin/sh
exec gameportingtoolkit-no-esync ~/my-game-prefix \
  'C:\Program Files\ElDewrito\eldorado.exe'
EOF

chmod +x ~/Desktop/Play\ ElDewrito.command
```

First open needs right-click → Open to clear Gatekeeper. Terminal flashes behind
the game; closing it quits the game.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `brew --prefix` prints `/opt/homebrew` | You're on the arm64 Homebrew. Re-run `arch -x86_64 zsh`, then the `eval` line from step 1 |
| Cask install reports a conflict | Another Wine is installed. See step 2 |
| "Wine is damaged and can't be opened" | `--no-quarantine` was omitted. Reinstall the cask with it |
| `gameportingtoolkit: command not found` | Step 4's shims weren't written or aren't executable. Re-run the `chmod` |
| Torrent stuck at 0% | Firewall prompt denied. Allow it in System Settings → Network → Firewall |
| Launcher window is black | `Game.CEFGpuEnable 0` missing or misspelled. Recheck step 9 |
| Game launches then quits | Confirm you used `gameportingtoolkit-no-esync`, not the plain wrapper |
| GPTK cask refuses to install | Check `uname -m` is `arm64` and `sw_vers` is 14.0+ |

---

## Uninstall

Nothing here writes to system locations or needs admin rights apart from step
4's shims.

```bash
rm -rf ~/my-game-prefix ~/prefix-clean.tgz
rm -f ~/Desktop/Play\ ElDewrito.command
rm -f /usr/local/bin/gameportingtoolkit /usr/local/bin/gameportingtoolkit-no-esync
brew uninstall --cask game-porting-toolkit
```

Rosetta and the x86_64 Homebrew can stay — both are inert when unused.

---

## A note on Rosetta's future

Apple has signalled Rosetta 2 will be wound down in releases after macOS 27, and
GPTK depends on it. If ElDewrito matters on a given Mac, check before upgrading
macOS. CodeWeavers has Apple-Silicon-native CrossOver builds in testing, which
is the likely long-term path.

---

## The CI probe

`.github/workflows/gptk-probe.yml` runs the install chain on a GitHub-hosted
Apple Silicon runner: architecture, Rosetta, the x86_64 Homebrew, cask
conflicts, the GPTK cask, `wine64` on PATH, prefix creation, the shims, .NET 6
under Wine, and resolving `launcher.exe` from the live releases API. It
screenshots any installer UI and uploads screenshots, the Wine log and prefix
listings as a run artifact.

It deliberately stops short of downloading game data. Trigger it from the
**Actions** tab. Its value is catching drift: a renamed cask, a moved release
asset, or a changed runner image shows up here rather than on your machine.

```bash
gh workflow run gptk-probe.yml
gh run watch
```

---

## Credits and references

- **The official ElDewrito guide** — [Google Doc](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit), linked from [eldewrito.org/guide](https://www.eldewrito.org/guide). Its macOS section is credited to **@sahuntermech** on Discord, and this repo is a supplement to that work, not a replacement
- **ElDewrito** — [eldewrito.info](https://eldewrito.info/) · [launcher source](https://github.com/eldewrito2/ElDewritoLauncher)
- **Apple Game Porting Toolkit** — [apple/game-porting-toolkit](https://github.com/apple/game-porting-toolkit)
- **gcenx** — [homebrew-wine tap](https://github.com/Gcenx/homebrew-wine), whose prebuilt cask makes step 3 a one-liner
- **.NET 6 Desktop Runtime** — [Microsoft](https://dotnet.microsoft.com/en-us/download/dotnet/6.0)

### Known errata in the official guide

| Where | As written | Actually |
|---|---|---|
| step 3 | ".NET 6.0.2" | `6.0.32` — matches its own command |
| step 5 | `gameportingtoolkit~/my-game-prefix` | missing the space before `~` |
| step 6 | `'C:\Program_files\launcher.exe` | unclosed quote; lowercase `files` |
| step 1 | "Install GPTK" | expands to Rosetta + x86_64 Homebrew + a cask |

---

Community documentation, not affiliated with ElDewrito's developers, Microsoft,
or Apple. ElDewrito is free software with no donations or microtransactions.
