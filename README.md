# bc-copilot-blueprint

> The first AL repository where **GitHub Copilot Coding Agent** can
> autonomously develop and verify Business Central extensions —
> compile, publish, and run AL tests against a real BC instance,
> end-to-end, with no human in the loop.

## Why this exists

GitHub Copilot is great at writing AL syntactically. It is, today,
**bad at writing AL that actually works**, because it has no way to
*run* Business Central and verify its own output. It guesses at API
shapes. It hallucinates field names. It writes tests that compile but
have never executed.

This repo fixes that. It uses [`StefanMaron/MsDyn365Bc.On.Linux`][bc-linux]
— a project that runs the real Business Central server on plain Linux
containers — and wires it into the GitHub Copilot Coding Agent's
execution environment so the agent can:

1. Read the example `app/` and `test/` folders to understand the
   conventions of this repo.
2. Write production AL in `app/src/` and matching tests in `test/src/`.
3. Run `./scripts/iterate.sh` to compile, publish to a running BC
   instance, and execute the tests.
4. Read the test results, fix what's broken, and iterate — against the
   same long-running BC instance, so each iteration takes seconds.

The agent never has to restart BC. The agent never has to wait six
minutes for a CI workflow round-trip. The agent gets the same
fast-feedback dev loop a human AL developer would get on their laptop.

## How it works (architecture)

```
┌──────────────────────────────────────────────────────────────────────┐
│  GitHub Copilot Coding Agent's runner (one Ubuntu VM per task)       │
│                                                                      │
│  Phase 1 — copilot-setup-steps.yml (runs ONCE, ~5 min)              │
│    • git clone StefanMaron/MsDyn365Bc.On.Linux → .bc-linux/         │
│    • download BC artifacts → .bc-artifacts/                         │
│    • docker compose pull (warm image cache)                         │
│    • install .NET 8 + AL compiler                                   │
│    • stage symbols → .symbols/                                      │
│                                                                      │
│  Phase 2 — Copilot iterates (many times, seconds per iteration)     │
│    1. Edit app/src/*.al or test/src/*.al                            │
│    2. Run ./scripts/iterate.sh                                      │
│         ↳ first run: docker compose up → BC live (~1-2 min)         │
│         ↳ AL compile app/                                           │
│         ↳ AL compile test/ (with app/ as dependency)                │
│         ↳ POST .app files to localhost:7049 (BC dev endpoint)       │
│         ↳ scripts/run-tests.sh → real test runner inside BC         │
│    3. Read pass/fail output, fix, go to 1.                          │
│                                                                      │
│  Phase 3 — Copilot opens a PR                                       │
│    • .github/workflows/bc-test.yml runs the same compile/publish/   │
│      test cycle on a clean GH Actions runner — independent          │
│      validation of whatever Copilot committed.                      │
└──────────────────────────────────────────────────────────────────────┘
```

The blueprint deliberately **consumes** [bc-linux][bc-linux] as a
sibling clone rather than vendoring or forking it. Both
`copilot-setup-steps.yml` and `bc-test.yml` resolve `.bc-linux` /
`StefanMaron/MsDyn365Bc.On.Linux@master` at runtime. When bc-linux
ships an improvement, this blueprint gets it on the next task with no
changes here.

## Before forking — one-time setup you cannot skip

GitHub Copilot Coding Agent runs behind a strict outbound firewall
that blocks most internet hosts. The default allowlist already covers
`mcr.microsoft.com`, `ghcr.io`, Docker Hub, npm, NuGet, Linux package
mirrors, etc. — so most of what bc-linux needs works out of the box.

**One host is missing from the default allowlist:**
`bcartifacts.blob.core.windows.net` (where Microsoft hosts the BC
artifacts download). You **must** add it to your fork's custom
allowlist before the agent's setup will succeed.

To add it:

1. Fork this repo into your org or personal account.
2. Go to **Settings → Copilot → Coding agent → Custom allowlist**
   (at the repo level, or at the org level if you want all your
   repos to inherit it).
3. Add `https://bcartifacts.blob.core.windows.net/`
4. Save.

Without this, the `Download BC artifacts` step in
`copilot-setup-steps.yml` will fail and Copilot will surface a
firewall warning in the PR body.

> **Why isn't this baked into the recommended allowlist?** Microsoft's
> default Copilot allowlist hasn't shipped with `bcartifacts` because
> the Linux BC story is brand new. We're working on getting it added
> upstream so future forks of this blueprint don't need this manual
> step. In the meantime, it's one click.

## How to use this blueprint

### Quick path (recommended)

1. Fork this repo (button top-right on GitHub).
2. Add the `bcartifacts.blob.core.windows.net` allowlist entry (above).
3. Open an issue describing the AL feature you want, e.g.:
   *"Add a `Customer Greeter` codeunit that takes a Customer record
   and returns a personalised greeting using the customer's name and
   their preferred salutation. Include tests."*
4. Assign the issue to **Copilot**.
5. Watch. The agent will create a branch, clone the bc-linux runtime
   into its workspace, boot BC, write the AL, run the tests, fix
   anything that fails, and open a PR.
6. Review the PR. The CI workflow has already independently re-run
   all tests on a clean runner.

### What to expect on the first task

- **~5 minutes** of setup (one-time per task) before Copilot writes
  any code. This is the BC artifact download + image pull + symbol
  staging. You'll see this in the `copilot-setup-steps.yml` workflow
  run on the agent's branch.
- **~1–2 minutes** for the first `iterate.sh` invocation (BC cold
  start with warm caches).
- **Seconds** per subsequent iteration (publish + test only — BC
  stays running).
- A PR opens when Copilot is satisfied, typically after several
  iterations.

### Locally (for humans)

If you want to run the same loop on your own machine:

```bash
git clone https://github.com/<you>/bc-copilot-blueprint
cd bc-copilot-blueprint
git clone https://github.com/StefanMaron/MsDyn365Bc.On.Linux .bc-linux
mkdir -p .bc-artifacts/27.5
.bc-linux/scripts/download-artifacts.sh sandbox 27.5 w1 "$PWD/.bc-artifacts/27.5"
# install .NET 8 + AL compiler tool from NuGet, then:
./scripts/iterate.sh
```

(There is intentionally no `Makefile` or wrapper for this — humans
who want a polished local setup should use bc-linux's own
`.devcontainer/`.)

## What's in the blueprint

| Path | Purpose |
|---|---|
| `app/`, `app/src/` | Production AL extension (your code goes here) |
| `test/`, `test/src/` | Test extension with `[Test]` codeunits |
| `scripts/iterate.sh` | The single dev-loop command Copilot runs |
| `.github/workflows/bc-test.yml` | CI on push (consumes the bc-linux reusable workflow) |
| `.github/workflows/copilot-setup-steps.yml` | Pre-task setup for the Copilot agent |
| `.github/copilot-instructions.md` | Instructions Copilot reads at the start of every task |

## Validation criteria

A blueprint fork is "working" when:

1. A human forks it, adds the one allowlist entry, and pushes — CI is
   green within ~10 minutes on the first push.
2. A human assigns Copilot an issue like *"add a `MyFeature` codeunit
   with tests"* and Copilot completes the issue end-to-end without
   intervention: writes the AL, runs the tests, fixes failures,
   opens a PR.
3. The PR's CI is green when Copilot finishes.

If any of those break for you, please open an issue here — failure
modes are the most useful data we can collect.

## Credits

Built on top of [`StefanMaron/MsDyn365Bc.On.Linux`][bc-linux], which
does all the genuinely hard work (running BC on Linux containers, the
test runner, the reusable workflow). This blueprint is a thin
adaptation layer that makes that substrate consumable by GitHub
Copilot's hosted execution environment.

[bc-linux]: https://github.com/StefanMaron/MsDyn365Bc.On.Linux
