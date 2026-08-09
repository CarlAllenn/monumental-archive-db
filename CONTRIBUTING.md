# Contributing

Contributions are welcome — issues, discussion and pull requests alike.
This document is the contract for what an acceptable contribution looks
like; the enforcement layer described below applies it mechanically, so
nothing here is aspirational.

## Development quick start

Tooling is pinned by [mise](https://mise.jdx.dev) and tasks run via
[Task](https://taskfile.dev):

```bash
git clone https://github.com/CarlAllenn/monumental-archive-db
cd monumental-archive-db
mise install   # installs the pinned toolchain and the git hooks
task ci        # the full gate: lints, scans, build, smoke, image scan
```

`mise install` also installs the lefthook git hooks; from then on every
commit runs the lint suite plus gitleaks and conventional-commit
enforcement, and every push builds and smokes the image when the Dockerfile
or the smoke script changed. There are no bypass flags — fixing tool output
is never optional. Personal overrides go in `lefthook-local.yml`, which is
gitignored.

You need Docker (or a compatible engine) to run `task build` and
`task smoke`. Everything else is installed by mise.

## Requirements for an acceptable contribution

- **One pull request per issue.** Branch from `origin/main`.
- **Conventional commits**, enforced by the commit-msg hook.
- **Signed commits.** A signed-commit ruleset is active on the repository.
- **Developer Certificate of Origin.** By adding `Signed-off-by` to your
  commits (`git commit -s`) you assert the
  [DCO](https://developercertificate.org/): that you are legally entitled
  to contribute the change under this project's licence.
- **The gate must be green.** `task ci` is identical to GitHub CI — same
  tasks, same order, same tool versions.
- **Respect the decision register.** [docs/decisions/](docs/decisions/)
  records load-bearing architectural decisions. A change that contradicts
  one is not automatically wrong, but it must amend the record rather than
  quietly diverge from it.
- **New words go in `.codespellrc`**, not in a lint bypass.

### Tests are part of the change

This repository has no unit tests because it has no application code. Its
test is [scripts/db-image-smoke.sh](scripts/db-image-smoke.sh), which boots
the built image and proves the extensions actually load — asserting against
`pg_get_loaded_modules()` rather than `\dx`, because `\dx` reports what is
*installable*, not what is *loaded*.

So: **a change to what the image contains comes with a smoke assertion that
fails without it.** Adding an extension without adding its assertion means
the next refactor can silently drop it and the gate will stay green.

One trap if you touch that script: the official entrypoint starts postgres
*twice* on a fresh volume, and the script deliberately waits for the
**second** "ready to accept connections" before asserting. Removing that
wait produces a test that passes locally and races in CI.

## Coding standard

The coding standard is the enforced configuration itself. Read the files
rather than a restatement of them, which would drift:

| Scope | Config |
| --- | --- |
| Dockerfile | [.hadolint.yaml](.hadolint.yaml) |
| Shell | [.shellcheckrc](.shellcheckrc), `shfmt -s -i 2 -ci -bn -sr` |
| Workflows | `actionlint`, `zizmor --persona=pedantic` |
| YAML | [.yamllint](.yamllint) |
| Markdown | [.markdownlint-cli2.jsonc](.markdownlint-cli2.jsonc) |
| TOML | [taplo.toml](taplo.toml) |
| Spelling | [.codespellrc](.codespellrc) |
| Whitespace | [.editorconfig](.editorconfig) |
| CVEs | [trivy.yaml](trivy.yaml) |

It is enforced twice — locally by the hooks, remotely by required status
checks on `main` — so a change that violates it cannot merge.

Most of this configuration is copied from
[CarlAllenn/renovate-config](https://github.com/CarlAllenn/renovate-config)
and marked "do not edit locally". Fix those upstream; a local edit will be
reverted by the next drift audit.

### Two conventions that are easy to break silently

- **Renovate pin convention.** Apt package versions live in
  `ARG *_VERSION=` lines with a `# renovate:` comment above them. An inline
  version in an apt line looks equivalent and silently loses Renovate
  coverage, so the pin quietly stops being maintained. Image pins need none
  of this — the native Dockerfile manager reads `FROM` lines and bumps tag
  and digest together.
- **edtf_postgres is a build stage, never a base.** It is consumed as
  `ghcr.io/carlallenn/edtf-postgres:<version>-pg18`, pinned by
  manifest-index digest. `FROM`-ing it as our base would inherit an apt
  layer we cannot refresh, which breaks the decision in
  [0001-own-the-installation](docs/decisions/0001-own-the-installation.md).
  The runtime stage globs `edtf_postgres*` out of the two extension paths
  rather than copying directories wholesale, so none of its base files
  cross over. Never bump that pin without keeping
  `task scan:edtf` green.

## Code review

Every change — including the maintainer's own — lands through a pull
request against `main` with the full gate green; direct pushes are blocked
by a repository ruleset. Review checks, in order of importance:

1. **Does the image still assert what it claims?** The supply-chain
   guarantees are the product here: digest pinning, the attestation gate,
   native multi-arch builds, pull-back-and-re-prove before signing. A diff
   that weakens one of those is the failure mode that matters most, and it
   rarely looks like a bug.
2. **Tests carry the claim**: a change to image contents needs the smoke
   assertion that fails without it.
3. **The gate**: reviewers do not re-litigate what the gate enforces
   mechanically.
4. **Publish-pipeline changes get adversarial review**: a pipeline diff is
   reviewed by asking what it can no longer catch. Reordering the
   build → smoke → push → re-prove → sign sequence is the specific thing
   to refuse.

External contributions are reviewed by the maintainer against the same
list. The project is honest that maintainer-authored changes are
self-reviewed against it (see [GOVERNANCE.md](GOVERNANCE.md)); tool
assistance is used liberally, but the accountable reviewer is the
maintainer.

## Small tasks for new contributors

Issues labelled `good first issue` are scoped to be tractable without deep
context. Perennially good entry points here:

- **Smoke-test coverage.** Every assertion added to
  `scripts/db-image-smoke.sh` is a claim the image can no longer break
  silently, and each one is independently reviewable.
- **Documentation that names a digest or a version.** These rot without
  failing anything. Finding one that has drifted is a real contribution.
- **Egress allowlists.** The harden-runner lists in the workflows are
  derived from audit runs, never guessed. Re-deriving one from a current
  run and recording the derivation is self-contained work.

## Reporting problems

Bugs and feature requests go to the [issue
tracker](https://github.com/CarlAllenn/monumental-archive-db/issues).
Security problems go through private vulnerability reporting — see
[SECURITY.md](SECURITY.md), which includes the response process, the scope
boundary between this image and its upstreams, and reporter credit policy.
