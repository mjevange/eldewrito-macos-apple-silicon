# Contributing

## The most useful thing you can do: report your hardware

CI proves the install works, but it runs on virtual machines with a
paravirtualised GPU. **Nobody has yet confirmed the game renders on real
Apple Silicon.** If you try it — success or failure — please
[open a report](https://github.com/mjevange/eldewrito-macos-apple-silicon/issues/new/choose).

Include your Mac model, macOS version, the output of `bash install.sh --check`,
and where it got to. A failure report is as valuable as a success.

## Changing the install

`install.sh` is the single source of truth for the install, and
`.github/workflows/verify.yml` re-runs it on a real macOS runner. If you change
the install, the workflow must still pass.

Keep them in step: a change to the documented steps belongs in `install.sh`,
not only in the README.

## Recording findings

Anything learned — especially a dead end — belongs in
[docs/FINDINGS.md](docs/FINDINGS.md), with the numbers that support it. The
point of that file is that someone can check the reasoning rather than trust a
conclusion, and that knowledge survives CI logs expiring.

## Scope

This repo covers installing ElDewrito on Apple Silicon Macs. Intel Macs,
general Wine troubleshooting and ElDewrito gameplay are out of scope — the
[ElDewrito Discord](https://eldewrito.info/) is the place for those.

Please don't commit debugging scaffolding, hardcoded credentials, or workflows
that expose a runner to the internet.
