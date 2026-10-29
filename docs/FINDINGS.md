# Findings

Everything established while working out how to install ElDewrito 0.7.1 on
Apple Silicon, including the things that **don't** work and why. Recorded here
because CI logs expire and the reasoning is worth more than the conclusion.

All claims below were produced on GitHub-hosted `macos-15-arm64` runners across
eleven CI runs in October 2026.

---

## 1. The decisive result

**The ElDewrito launcher will not start on Wine 7.7. It starts on Wine 11.16.**

| Runtime | Reports | Launcher |
|---|---|---|
| `gcenx/wine/game-porting-toolkit` (Homebrew cask, labelled `3.0-3`) | `wine-7.7 (Game Porting Toolkit 1.1)` | ❌ stack overflow, no window |
| [`frankea/winecx-gptk`](https://github.com/frankea/winecx-gptk) `runtime-v4.6.4` | `wine-11.16` | ✅ boots, wizard advances, download runs |

Under 7.7 the launcher loads .NET, executes managed code, reaches WinRT
notification code and dies:

```
0128:fixme:combase:RoGetActivationFactory (L"Windows.UI.Notifications.ToastNotificationManager" …): semi-stub
0128:err:combase:RoGetActivationFactory Failed to find library for L"Windows.UI.Notifications.ToastNotificationManager"
0024:err:virtual:virtual_setup_exception stack overflow 4208 bytes in thread 0024
```

Under 11.16 the same toast failure appears **twice and is harmless** — the
launcher continues, renders its window, and the log shows ordinary UI work
(DirectWrite layout, bitmap scaling, DWM composition).

**The toast error is a symptom, not the cause.** Do not chase it.

---

## 2. Hypotheses tested and eliminated

### .NET version — eliminated

The launcher reports it wants app host **6.0.29**, so a version mismatch was the
obvious theory. It is wrong.

| Wine | .NET | Log size | Stack overflows | Window |
|---|---|---|---|---|
| 7.7 | 6.0.29 (exact match) | 30,083 b | 1 | no |
| 7.7 | 6.0.36 (current) | 30,083 b | 1 | no |
| 7.7 | none | 3,351 b | 0 | yes — "install .NET" dialog |
| 11.16 | 6.0.36 | 26,228 b | 0 | **yes — the wizard** |

Pinning the exact requested runtime produces a **byte-identical** crash log. Any
6.0.x x64 Desktop Runtime is equally fine, and none of them help on 7.7.

Useful detail: with **no** .NET present, the launcher's native host shows a clean
"You must install .NET Desktop Runtime" dialog. That proves Wine's windowing
works even on 7.7 — the failure is specifically in managed startup.

### Reported Windows version — eliminated

Since WinRT toasts postdate Windows 7, reporting an older OS looked promising.
It is not.

| Reported version | Log size | Stack overflows |
|---|---|---|
| `win10` | 27,819 b | 1 |
| `win81` | 27,819 b | 1 |
| `win7` | 27,738 b | 1 |
| `winxp` | 1,234 b | 0 — app exits immediately, refuses to run |

### Waiting longer — eliminated

Wine apps can be slow to show a window, so the 60-second observation window was
suspect. Extending it to five minutes produced a **byte-identical 27,819-byte
log**: the process wedges and emits nothing further. Patience does not help.

---

## 3. Environment facts

### The Homebrew cask is much older than its version implies

Published as `3.0-3`, with `CFBundleShortVersionString` also `3.0-3`, but
`wine64 --version` reports `wine-7.7 (Game Porting Toolkit 1.1)` — a 2022 Wine.
It *does* bundle D3DMetal, at
`/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework`.
It links `wine64`, `wine64-preloader` and `wineserver` into the Homebrew prefix,
and conflicts with `wine-crossover`, `wine-stable`, `wine@devel`, `wine@staging`.

### Homebrew changes that break most existing guides

- **`--no-quarantine` has been removed** (Homebrew 6.0.22): passing it fails with
  `invalid option: --no-quarantine`. Use `xattr -dr com.apple.quarantine <path>`.
  Nearly every Wine-on-Mac guide still prescribes the old flag.
- **Homebrew refuses to install on Intel macOS**: `Homebrew on macOS is only
  supported on Apple Silicon processors!` This silently breaks the "install an
  x86_64 Homebrew into /usr/local" step that every GPTK guide prescribes —
  `install.sh` exits and leaves you on the arm64 brew with no warning.
- **The x86_64 Homebrew is still installable by tarball**, bypassing the
  installer's arch check, and runs fine under Rosetta:
  ```bash
  sudo mkdir -p /usr/local/homebrew && sudo chown -R "$(whoami)" /usr/local/homebrew
  curl -fsSL https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C /usr/local/homebrew
  arch -x86_64 /usr/local/homebrew/bin/brew --version
  ```
  So **Apple's documented GPTK route remains viable** — it is slow, not dead.
- **`gcenx/homebrew-wine` now contains only `game-porting-toolkit.rb`.**
  `wine-crossover` and `wine-stable` are gone from that tap, almost certainly
  collateral from Homebrew dropping Intel macOS.

### Apple's own GPTK formula

Apple distributes **D3DMetal as binaries** (in the DMG) but **Wine as a formula
that compiles from source**, which is where the ~75-minute build figure comes
from. In our run, `brew install apple/apple/game-porting-toolkit` produced **no
wine binary** and the dependent steps skipped. Not investigated further once a
prebuilt current runtime was found.

### Plain (non-GPTK) Wine on Apple Silicon

[`Gcenx/macOS_Wine_builds`](https://github.com/Gcenx/macOS_Wine_builds) publishes
`wine-devel` / `wine-staging` tarballs — 11.18 at time of writing. These are
`osx64` (Intel) builds running under Rosetta, and they behaved badly:

- `wine --version` with **no `WINEPREFIX` set** creates `~/.wine` and triggers a
  full `wineboot`, which pops **Wine Mono/Gecko installer dialogs** that nothing
  can click in CI. The only clue is
  `wine: created the configuration directory '/Users/runner/.wine'`.
- Even with `WINEPREFIX` set, prefix initialisation ran past 8 and 25 minute
  limits, and produced
  `ShellExecuteEx failed: File not found` when launching from an incomplete
  prefix.

**`WINEDLLOVERRIDES="mscoree,mshtml="` suppresses the Mono/Gecko prompts but
breaks .NET.** It disables the .NET shim loader, producing cascades of:

```
err:module:fixup_imports_ilonly mscoree.dll not found,
  IL-only binary L"System.Runtime.dll" cannot be loaded
```

Do not use it for a real install. (It did **not** cause the Wine 7.7 crash — that
reproduces without it.)

### Binary facts

- `launcher.exe` is **`PE32+ executable (GUI) x86-64`** — 64-bit, 11,060,322
  bytes at v0.1.1. (Commonly assumed to be 32-bit; it is not.)
- The **x64** .NET Desktop Runtime installer is itself a **`PE32` (32-bit)
  bootstrapper** — normal for Microsoft installers, but surprising in `file`
  output.
- The launcher requests .NET app host **6.0.29**; `aka.ms` currently serves
  **6.0.36**, which works.

### Two permission prompts, not one

The official guide mentions the firewall prompt. There is a **second** one:
macOS asks *"Allow <app> to find devices on local networks?"* when the P2P
download starts. **Both must be allowed** or the torrent stalls at 0% with no
useful error.

---

## 4. What CI can and cannot prove

GitHub's arm64 runners report:

```
model: Apple Paravirtual device
type: Integrated
Metal Shading Language 3.2
GPU Family Apple 5 / Mac 1 / Mac 2
GPU memory available: 4778 MB
```

A **paravirtualised** GPU. MoltenVK 1.4.2 initialises and enumerates 153 Vulkan
extensions, so the graphics stack comes up — but this is not real hardware.

**Proven in CI:** runtime install, prefix creation, .NET install, launcher
startup, window rendering, wizard interaction, and the P2P download running at
**5.17 MB/s** with a realistic time estimate.

**Not provable in CI:** whether Halo Online itself renders through DXMT/D3DMetal.
That needs a physical Mac. The verified runtime ships **DXVK 1.10.3** and
**DXMT 0.80** (`gptkCapable: true`), both far newer than the cask's D3DMetal,
which is a better starting position than where this began.

---

## 5. Errata in the official guide

The [official guide](https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)'s
macOS section is credited to **@sahuntermech** on Discord, and its steps 2–8 are
correct and used unchanged here. These are transcription slips, plus one
unstated requirement:

| Where | As written | Actually |
|---|---|---|
| step 1 | "Install GPTK" | Requires Apple Silicon **and macOS 14+**, neither stated. Which GPTK you install decides whether the launcher runs at all |
| step 3 | ".NET 6.0.2" | `6.0.32` per its own command; any 6.0.x x64 works |
| step 5 | `gameportingtoolkit~/my-game-prefix` | missing space before `~` |
| step 6 | `'C:\Program_files\launcher.exe` | unclosed quote; lowercase `files` |
| step 4 | `\Users~\my-game-prefix` | shorthand for `/Users/<username>/` — never a literal `~` folder |
| steps 4–8 | `Program_Files` vs `Program Files` | Different directories, both intentional: underscore is the staging folder you create, space is where the launcher installs |

---

## 6. Incidental gotchas

Mostly relevant to anyone scripting this or adapting Linux tooling:

- **macOS has no `timeout` command** (it is GNU coreutils). Wrapping commands in
  it fails with `command not found`, and if swallowed by `|| true` the wrapped
  command silently never runs.
- **`aka.ms` and the GitHub releases API both return 403 under parallel load.**
  Pin fallback URLs.
- **`mxschmitt/action-tmate` installed cleanly but never emitted a session
  string**, running 11m51s past its own 600-second connect timeout with no
  output. It is also deprecated upstream and scheduled for disablement on
  2026-12-11.
