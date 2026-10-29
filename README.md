# gptk-probe

A GitHub Actions workflow that validates an install chain on an Apple Silicon
macOS runner, headlessly.

It checks, in order: `arm64`, Rosetta 2, an x86_64 Homebrew in `/usr/local`,
conflicting Wine casks, the `gcenx/wine/game-porting-toolkit` cask, `wine64` on
PATH, Wine prefix creation, a `gameportingtoolkit` shim, the .NET 6 desktop
runtime installing under Wine, and whether a Windows installer UI renders.

Screenshots, the Wine log and prefix listings upload as a run artifact.

Run it from the **Actions** tab (`workflow_dispatch`). It deliberately stops
short of downloading any game data.
