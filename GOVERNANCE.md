# Governance

## Model

The project uses the simplest governance model that is honest about how it
operates: a single maintainer
([@CarlAllenn](https://github.com/CarlAllenn)) makes all final decisions —
a "benevolent dictator" model. Proposals, disagreements and design
discussion happen in the open, on the issue tracker and in pull requests;
the maintainer decides, and records load-bearing decisions in
[docs/decisions/](docs/decisions/) so they bind future work rather than
being re-litigated.

Policy that is shared across repositories — the lint canon, the Renovate
preset, the git-hook set, the CI and publish templates — is decided in
[CarlAllenn/renovate-config](https://github.com/CarlAllenn/renovate-config)
and adopted here by deliberate drift audit rather than automatically. A
change to shared policy belongs there, not in a local override.

## Roles and responsibilities

- **Maintainer** (currently the only role held): triages issues, reviews
  and merges pull requests, owns the publish pipeline and the signing
  identity, responds to security reports per [SECURITY.md](SECURITY.md),
  and owns the decision register.
- **Contributors**: anyone submitting issues or pull requests under the
  requirements in [CONTRIBUTING.md](CONTRIBUTING.md). No CLA — the DCO
  sign-off is the legal mechanism.

Should the project gain regular contributors, committer status and this
document evolve with it; until then, documenting a committee that does not
exist would be less honest than documenting the dictatorship that does.

## Access continuity

The practical single-maintainer risk is mitigated as follows:

- **Everything needed to build, test and publish lives in the repository.**
  The toolchain is pinned by mise in strict/locked mode, the gate is one
  command (`task ci`) that behaves identically on a laptop and in CI, and
  the publish pipeline is [a single
  workflow](.github/workflows/publish.yml). There is no build step that
  exists only in someone's shell history.
- **No long-lived tokens exist to lose.** Publishing authenticates with the
  workflow's own `GITHUB_TOKEN` for GHCR and with Sigstore OIDC for
  signing. There is no registry password, no signing key, and nothing in
  the repository's secrets that a successor would need to be handed. This
  is the whole reason keyless signing was chosen over a key pair: a private
  key is exactly the artifact that cannot be inherited.
- **Whoever controls the GitHub repository can publish.** Because the
  cosign certificate identity names *this repository's publish workflow*,
  transferring the repository transfers the ability to publish verifiable
  images — no key ceremony, no re-registration.
- The maintainer's estate arrangements cover credential succession for the
  GitHub account, and GitHub's [deceased user
  policy](https://docs.github.com/site-policy/other-site-policies/github-deceased-user-policy)
  provides a fallback path for transferring the repository.
- **The licence guarantees a fork can continue the work** without any legal
  transfer at all. This repository is unusually well suited to that: it is
  a Dockerfile, three pinned extensions and a pipeline. A fork changes the
  image name and the cosign identity, and is otherwise complete.

## What consumers are entitled to rely on

Governance of a published artifact is partly a promise about change. The
commitments here:

- **Consumers pin digests**, so nothing this project does can change an
  image somebody has already pulled. There are no version tags to
  re-point and, per the tag-immutability ruleset, no tags that can move.
- **The signing identity will not weaken.** If it ever must change, the
  change is announced in the README and the decision register before the
  first image signed under the new identity is published.
- **The three-extension surface is the scope.** Adding a fourth extension
  is a governance decision recorded in `docs/decisions/`, not a routine
  pin bump — see the [roadmap](docs/roadmap.md).
