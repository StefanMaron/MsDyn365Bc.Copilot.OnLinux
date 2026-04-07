# Instructions for GitHub Copilot Coding Agent

You are working in a Business Central AL extension repository. Unlike most
AL repos you've seen, **this one is wired so you can actually run BC and
verify your work** — not just compile it. Read this whole file before you
start a task.

## What's running in your environment

Before you started, the `copilot-setup-steps.yml` workflow already:

- Cloned `StefanMaron/MsDyn365Bc.On.Linux` into `.bc-linux/` (gitignored —
  do **not** modify or commit anything in there).
- Downloaded BC artifacts (~3 GB) into `.bc-artifacts/`.
- Pulled the `bc-runner` and SQL Server docker images.
- Installed the .NET 8 SDK and the Linux AL compiler. The `AL` command is
  on your `PATH`.
- Staged BC platform and test framework symbols into `.symbols/`.
- Resolved which baseline BC apps to keep in the database and wrote them
  to `.bc-cache/env`.

Business Central is **not running yet**. The first time you run the dev
loop in a session, BC boots in ~1–2 minutes (with everything cached).
After that, it stays running for the rest of your session and every
subsequent iteration takes seconds.

## Your dev loop

The only command you need:

```bash
./scripts/iterate.sh
```

This compiles `app/`, then `test/` (with `app/` as a dependency),
publishes both `.app` files to the running BC instance via the dev
endpoint, and runs every `[Test]` codeunit in the 50100..50199 range
through the BC test runner.

**Run it after every meaningful edit.** Read the output. If compilation
fails, fix the AL. If a test fails, read the assertion message and fix
either the production code or the test (whichever is wrong). Re-run.
The container persists across iterations — you do not need to restart
anything.

## What NOT to do

- **Do not run `docker compose down`, `docker stop`, or anything else
  that would tear down BC.** Killing the container forces a 1–2 minute
  cold start on the next iteration. There is no scenario in a normal
  task where you should restart BC.
- **Do not edit anything under `.bc-linux/`, `.bc-artifacts/`, `.symbols/`,
  `.bc-cache/`, or `build/`.** These are runtime state. If something
  there looks broken, the answer is *not* to fix it by hand — describe
  the symptom in your PR and stop.
- **Do not add new top-level `app/` or `test/` directories.** If you
  need to split an app, ask in the PR description first. The CI workflow
  in `.github/workflows/bc-test.yml` is hard-coded to compile `app/` and
  `test/`; changing the layout means changing CI too.
- **Do not commit `.app` files**, dependency caches (`.alpackages/`),
  or anything in `build/`. These are reproducible from source.

## Repository layout

```
app/                  ← your production AL code goes here
  app.json            ← extension manifest, ID range 50000..50099
  src/                ← .al files (objects)
test/                 ← your test AL code goes here
  app.json            ← test extension manifest, ID range 50100..50199
  src/                ← .al test codeunits ([Test] procedures)
scripts/iterate.sh    ← the dev loop you should run after edits
.github/
  workflows/
    bc-test.yml             ← CI: re-runs the same tests on a clean runner on push
    copilot-setup-steps.yml ← what set up your environment (don't edit)
  copilot-instructions.md   ← this file
```

## AL conventions in this repo

- Production codeunits use IDs **50000..50099**. Tests use **50100..50199**.
  These ranges are declared in the respective `app.json` files. If you need
  more, expand the range in `app.json` first.
- One AL object per file. Filename pattern: `<Name>.<Type>.al`
  (e.g. `Customer.Table.al`, `HelloWorld.Codeunit.al`).
- Test codeunits must declare `Subtype = Test;` and use the `[Test]`
  attribute on each test procedure. Use `Codeunit "Library Assert"` for
  assertions — it's already in the test app's dependencies.
- Follow the pattern in `test/src/HelloWorldTest.Codeunit.al`: GIVEN /
  WHEN / THEN comment structure, descriptive procedure names, one logical
  assertion per test.

## When you're done

Commit your changes and open a PR as usual. The `bc-test.yml` workflow
will re-run the full compile + publish + test cycle on a clean runner —
this is your independent validation. If `iterate.sh` was passing locally
but CI fails, the most likely cause is that you committed a stale `.app`
file or forgot to commit a new `.al` file; check your `git status`
carefully.

## If something goes wrong

- **`iterate.sh` says "BC artifacts not found"**: setup didn't complete.
  This is an environment problem, not something you can fix in code.
  Stop and report it in the PR description.
- **`iterate.sh` says "BC unhealthy"**: BC failed to start. Read the
  log tail it printed. If it mentions a missing dependency app, the
  most likely cause is that one of your `dependencies` in `app.json` or
  `test/app.json` references an app that wasn't kept in the selective
  filter. Add it to the keep set by editing `dependencies` correctly,
  then re-run.
- **A test fails with a message you don't understand**: re-read the
  test, the production code, and the assertion message together. Do
  *not* delete or skip the test — fix the underlying issue.
- **Compilation fails on a symbol you expected to exist**: check
  `.symbols/` for the expected `.app` file. If it's missing, the BC
  artifact didn't ship it for this version/country combination. Pick a
  different API or add the missing module to your dependencies.

## The point of all this

This blueprint exists to prove a specific claim: that an AI coding agent
can do the full compile-publish-test cycle on Business Central
autonomously, with no human in the loop. You are the test of that
claim. Take your time, iterate carefully, and let the test runner be
your ground truth.
