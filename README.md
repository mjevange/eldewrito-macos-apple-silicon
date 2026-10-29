# ElDewrito on Apple Silicon Macs

Install [ElDewrito](https://eldewrito.info/) 0.7.1 — the community mod for the
cancelled *Halo Online* — on an M-series Mac.

```bash
git clone https://github.com/mjevange/eldewrito-macos-apple-silicon.git
cd eldewrito-macos-apple-silicon
bash install.sh
```

Requires **Apple Silicon**, **macOS 14 (Sonoma) or newer**, and ~15 GB free.
Intel Macs cannot run this — [see why](#intel-macs).

[![verify](https://github.com/mjevange/eldewrito-macos-apple-silicon/actions/workflows/verify.yml/badge.svg)](https://github.com/mjevange/eldewrito-macos-apple-silicon/actions/workflows/verify.yml)

---

## What this is

The [official ElDewrito guide](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)
has a macOS section, and its steps 2–8 are correct — this repo follows them
unchanged. Its step 1 is a single line, `Install GPTK (gameportingtoolkit)`, and
**how you satisfy that line decides whether the launcher runs at all.**

The obvious free shortcut — Homebrew's Game Porting Toolkit cask — installs
perfectly and then **cannot start the launcher**. It ships Wine 7.7 despite
being published as version `3.0-3`. A current prebuilt runtime works first try.

| Runtime | Wine | Launcher |
|---|---|---|
| `gcenx/wine/game-porting-toolkit` (Homebrew cask) | 7.7 (2022) | ❌ crashes on startup |
| [`frankea/winecx-gptk`](https://github.com/frankea/winecx-gptk) `runtime-v4.6.4` | **11.16** | ✅ **works** |

`install.sh` uses the one that works. The reasoning, the hypotheses that were
eliminated, and every gotcha found along the way are in
**[docs/FINDINGS.md](docs/FINDINGS.md)**.

---

## Status

| | |
|---|---|
| Runtime, prefix and .NET install | ✅ verified in CI |
| Launcher starts and renders its UI | ✅ verified in CI |
| Game files download over P2P | ✅ verified — 5.17 MB/s |
| **The game itself renders and plays** | ❓ **unverified** |

CI runs on GitHub's Apple Silicon runners, which report `Apple M1 (Virtual)` and
have a paravirtualised GPU. They prove installation; they cannot prove the game
renders. **If you get it running — or it fails — please
[report it](https://github.com/mjevange/eldewrito-macos-apple-silicon/issues/new/choose).**
That is the one gap CI cannot close, and real reports are what will close it.

---

## Usage

```bash
bash install.sh              # install
bash install.sh --check      # check prerequisites only, change nothing
bash install.sh --uninstall  # remove prefix, runtime and play script
```

The script is **idempotent** — re-run it safely; it skips what is already done.
When it finishes you get `~/Desktop/Play ElDewrito.command`.

### Two prompts appear during the install

1. the **firewall** prompt — the official guide mentions this one, and it
   gates the peer-to-peer download. Allow it.
2. a macOS prompt — *"Allow … to find devices on local networks?"* — which
   appears when the download starts.

**The second one is optional.** In testing the download completed at 3–5 MB/s
with that dialog sitting on screen unanswered for its entire 25-minute run, so
it is not required. Allow it anyway if you have other machines on your LAN —
it only governs local peer discovery — but ignoring it will not stall anything.

### Playing

Double-click `~/Desktop/Play ElDewrito.command`. First open needs
right-click → **Open** to clear Gatekeeper. **Plug a gamepad in before
launching**, per the official guide.

To update, re-run `bash install.sh` — the launcher self-updates over P2P.

---

## If the launcher gives you trouble

You do not strictly need it. Its only job is fetching game files, and
[eldewrito.info/download](https://eldewrito.info/download) publishes a torrent
magnet. Torrent natively on macOS, drop the folder into
`~/my-game-prefix/drive_c/Program Files/ElDewrito/`, and the play script will
find it.

---

## Intel Macs

Not supported, and not fixable. Apple's
[Game Porting Toolkit](https://github.com/apple/game-porting-toolkit) requires
Apple Silicon — it is built on D3DMetal and Rosetta 2, neither of which exists
on Intel, and GPTK 4 dropped Intel support entirely. Homebrew itself also no
longer installs on Intel macOS, which breaks most older Wine guides.

Intel options are CrossOver, [Kegworks](https://github.com/Kegworks-App/Kegworks)
or Boot Camp. None are covered here.

---

## Contributing

Hardware reports are the most valuable contribution — see
[CONTRIBUTING.md](CONTRIBUTING.md). The CI workflow re-runs the documented
install weekly, so upstream drift (a moved release asset, a renamed flag, a new
macOS image) surfaces here rather than on your Mac.

---

## Credits

- **The official guide**, macOS section credited to **@sahuntermech** on
  Discord. Everything below its step 1 is theirs and is correct; this repo only
  resolves which GPTK to use, which upstream changes turned into a trap after it
  was written.
- **ElDewrito** — [eldewrito.info](https://eldewrito.info/) ·
  [launcher source](https://github.com/eldewrito2/ElDewritoLauncher)
- **frankea** — [Whisky fork](https://github.com/frankea/Whisky) and
  [winecx-gptk](https://github.com/frankea/winecx-gptk), whose prebuilt runtime
  is what makes this work
- **Gcenx** — [homebrew-wine](https://github.com/Gcenx/homebrew-wine) and
  [macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- **Apple** — [Game Porting Toolkit](https://github.com/apple/game-porting-toolkit)

Community documentation under [MIT](LICENSE). Not affiliated with ElDewrito's
developers, Microsoft or Apple. ElDewrito is free — no donations, no
microtransactions.
