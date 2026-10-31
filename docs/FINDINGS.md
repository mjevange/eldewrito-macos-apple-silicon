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
- **The x86_64 Homebrew tarball installs and prints a version, but cannot
  install anything.** An earlier note here claimed this kept Apple's documented
  GPTK route "slow, not dead". That was wrong, and the mistake is instructive:
  the test only ran `brew --version`, which succeeds. Any actual operation
  fails:

  ```
  Error: Homebrew's master branch is no longer supported.
  ```

  The tarball URL pulls Homebrew's **master branch**, which Homebrew now
  refuses to operate from. Both `apple/apple` and `gcenx/apple` taps therefore
  failed, and **neither produced a wine binary**.

  Untested escape: fetching a **tagged release** tarball rather than master may
  restore a working x86_64 Homebrew. Until someone confirms that, treat Apple's
  own GPTK route as **blocked on current systems**, not merely slow.
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

**Outcome: plain Wine never ran the launcher.** With `WINEPREFIX` set correctly
and 35 minutes allowed, `wine-devel 11.18` created its prefix directory and
initialised MoltenVK, but could not launch executables from it:

```
Application could not be started, or no application associated with the specified file.
ShellExecuteEx failed: File not found.
```

No launcher log was produced. The GPTK runtime completed the same sequence in
about two minutes.

**Confidence: moderate.** This suggests the CrossOver/GPTK patches do real work
beyond rendering, so the specific runtime is worth naming rather than "any
modern Wine". But the root cause was never isolated — it may be these `osx64`
builds under Rosetta on a virtualised machine rather than the absence of GPTK
itself. Worth retesting on real hardware if anyone is curious.

### Binary facts

- `launcher.exe` is **`PE32+ executable (GUI) x86-64`** — 64-bit, 11,060,322
  bytes at v0.1.1. (Commonly assumed to be 32-bit; it is not.)
- The **x64** .NET Desktop Runtime installer is itself a **`PE32` (32-bit)
  bootstrapper** — normal for Microsoft installers, but surprising in `file`
  output.
- The launcher requests .NET app host **6.0.29**; `aka.ms` currently serves
  **6.0.36**, which works.

### Two permission prompts, and only one matters

The official guide mentions the firewall prompt. There is a **second**: macOS
asks *"Allow <app> to find devices on local networks?"* when the P2P download
starts.

**The local-network prompt is not required.** An earlier draft of these notes
claimed both had to be allowed or the download would stall — that was reasoning,
not evidence, and the evidence refutes it. In the full end-to-end run the dialog
appeared and was **never answered**, yet the download ran at 3.12–5.17 MB/s and
completed all 5.7 GB. Screenshots at minutes 15 and 30 both show it still on
screen, unanswered, with the transfer progressing behind it.

It governs **local peer discovery only**, which on a cloud runner would find
nothing anyway. Allow it if you have other machines on your LAN; ignoring it
costs you nothing else.

The **firewall** prompt is the one that gates the transfer.

---

## 3b. The launcher installs into its own directory

**Verified by accident, and it matters.** A full end-to-end run downloaded all
**5.7 GB** cleanly (0 stack overflows, 172 KB of log) and the launcher
transitioned from installer to its home screen — "Version: 0.7.1" with a live
**PLAY** button.

But `eldorado.exe` was nowhere under `C:\Program Files\ElDewrito`. The launcher
had been staged in `C:\stage`, and **installed the game beside itself** rather
than at the path the official guide names.

Consequences:

- Wherever you put `launcher.exe` is where the game lands, unless you change the
  path in the wizard.
- The official guide's step 8 launch command assumes
  `C:\Program Files\ElDewrito\eldorado.exe`. That only holds if you actually
  set that path in the wizard — the guide's steps 4–6 stage the launcher in a
  **different** folder (`Program_Files`, underscore), so following it literally
  can leave the game somewhere step 8 does not look.
- `install.sh` had the same flaw and now stages the launcher inside the intended
  game directory, and locates `eldorado.exe` by search rather than assumption.

If your play command cannot find the game:

```bash
find ~/my-game-prefix/drive_c -maxdepth 5 -iname eldorado.exe
```

## 3c. macOS version: 15 or newer, not 14

Tested across three runner images, same runtime, same steps:

| Runner | macOS | Wine | Launcher window |
|---|---|---|---|
| `macos-14` | 14.8.9 | 11.16 | ❌ none after **4 minutes**, 0 crashes |
| `macos-15` | 15.7.9 | 11.16 | ✅ **22 seconds** |
| `macos-latest` | 26.6.2 | 11.16 | ✅ **22 seconds** |

**The cause is now known, and it is not windowing.** On macOS 14 the **.NET 6
Desktop Runtime installer does not install** under Wine. The missing window was
the downstream symptom: a launcher with no .NET cannot start.

```
macOS 15.8.2  ✓ wine-11.16   ✓ .NET installed: 6.0.36   → window at 15 s
macOS 14.8.9  ✓ wine-11.16   ✗ .NET did not install after 5 minutes
```

Everything before .NET passes identically on both: Apple Silicon, free space,
Rosetta 2, `wine-11.16`, prefix created.

Worth noting how this was missed for several runs. The `compat` tests ran the
.NET install inline **without verifying it**, so on macOS 14 they proceeded to a
launcher that had nothing to run on, and the visible symptom was "no window".
Only `install.sh`, which does verify, surfaced the real failure. The first fix
attempted — replacing a fixed `sleep 10` with a five-minute poll — did not help,
confirming it is a genuine failure rather than a race.

**This corrects the requirement.** Earlier notes said "macOS 14 (Sonoma) or
newer", taken from Apple's GPTK documentation rather than tested. The
observed floor is **macOS 15**.

Caveat worth stating: this is on virtual machines. A 14.x user seeing it work on
real hardware should [report it](https://github.com/mjevange/eldewrito-macos-apple-silicon/issues/new/choose)
— that would change the recommendation.

## 3d. .NET: any of 6.0.29, 6.0.36 or 8.0.33 works

The launcher requests app host **6.0.29**, but it is not fussy:

| Installed | Launcher window | Crashes |
|---|---|---|
| 6.0.29 (exact match) | ✅ | 0 |
| 6.0.36 (latest 6.x) | ✅ | 0 |
| **8.0.33** | ✅ | 0 |

So users are **not** pinned to an end-of-life runtime. .NET 8 satisfies it
through roll-forward, which matters because Microsoft will eventually stop
serving 6.0.x.

## 3e. Apple's own GPTK route is blocked

Tested properly, with errors captured rather than swallowed:

- The x86_64 Homebrew **is** installable from a **tagged release** tarball
  (tag 7.0.11) and is operational — `brew search` works. Pulling
  `tarball/master` does not: Homebrew refuses to run from master.
- But **both** `apple/apple` and `gcenx/apple` fail to install
  `game-porting-toolkit`, and neither produces a wine binary:

  ```
  If the biggest companies in the world cannot support macOS Intel x86_64
  Some of Homebrew's bottles (binary packages) cannot be used with this prefix.
  ```

Homebrew has deprecated x86_64 macOS, so the bottles the formula needs no longer
exist for a `/usr/local` prefix.

**Conclusion: Apple's documented GPTK route cannot currently be completed**, and
the prebuilt `winecx-gptk` runtime is not merely the faster option — it is the
only one that works. (These notes previously said the opposite twice, in both
directions, before the errors were actually captured.)

## 3f. The Whisky GUI route

[frankea/Whisky](https://github.com/frankea/Whisky) **3.7.0** installs cleanly
from its release DMG. It downloads its Wine runtime only after GUI interaction,
so headless CI could not confirm which build it uses — the app is installed and
functional, but `whisky_wine=not-found` without clicking through it.

Given the maintainer also publishes `winecx-gptk`, it very likely uses the same
runtime verified here, but that is **inference, not measurement**. Anyone using
Whisky successfully is welcome to confirm it.

## 3g. Sync modes: the guide's `no-esync` advice is stale

The official guide launches with `gameportingtoolkit-no-esync`. That predates
Wine 11 by years. On Wine 11.16 all three modes start the launcher cleanly:

| Mode | Window | Crashes |
|---|---|---|
| `WINEESYNC=0` (the guide's advice) | 22 s | 0 |
| `WINEESYNC=1` | **16 s** | 0 |
| `WINEMSYNC=1` | 17 s | 0 |

msync is confirmed genuinely active rather than silently ignored — the Wine log
shows it bootstrapping:

```
msync: bootstrapped mach port on wine-35f505-msync.
msync: up and running.
```

**What this does and does not establish.** That esync and msync *work* is solid:
a window appeared, zero crashes, and msync logged itself up. That either is
*faster* is suggestive only — one sample each, and 16 vs 22 seconds is within
runner noise.

Sync primitives matter mainly for **in-game** performance, which has not been
tested, so `install.sh` still defaults to the guide's conservative `WINEESYNC=0`.
The play script honours an override, so a user on real hardware can try:

```bash
ELDEW_SYNC=msync ~/Desktop/Play\ ElDewrito.command
```

and report whether it helps. Changing the default on launcher-only evidence
would be exactly the inference-over-measurement mistake these notes record
elsewhere.

## 3h. How long it takes and how much space

Measured end to end on a `macos-15` runner, excluding game files:

| Stage | Time | Disk after |
|---|---|---|
| Runtime download and extract | 8 s | 1.3 GB |
| Wine prefix creation | 87 s | 635 MB |
| .NET 6 install | 32 s | 958 MB |
| Launcher to visible window | 15 s | — |
| **Total install** | **158 s** | **~2.3 GB** |

Peak launcher memory: **290 MB**. Add ~5.7 GB for game files, so budget ~8 GB
rather than the 15 GB the preflight demands — that figure is deliberately
conservative.

## 3i. Community corroboration: none

Asked in the ElDewrito Discord (28 Oct 2026) whether anyone had used the gdoc's
macOS steps. The only reply confirmed Linux works and that nobody there had
tried macOS. So the guide's macOS section remains, as far as can be determined,
a single uncorroborated contribution — which is consistent with the stale
assumptions found in it, and means the verification here may be the first.

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
startup, window rendering, wizard interaction, and the **complete 5.7 GB P2P
download** — peaking at 5.17 MB/s, finishing clean, with the launcher reaching
its home screen and offering PLAY.

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
