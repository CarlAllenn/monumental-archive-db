#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Carl Allen
# SPDX-License-Identifier: AGPL-3.0-only

# edtf-postgres supply-chain gate. Closes the loop between the image digest
# pinned in the Dockerfile and the publisher that claims to have produced
# it. Two facts, and NEITHER is sufficient alone:
#
#   1. The build enforces that the stage it pulls matches the pinned digest
#      (BuildKit, fail-closed). That proves the bytes did not change. It
#      does not prove they are the right bytes.
#   2. `gh attestation verify` proves the image was built by edtf's own
#      publish workflow, keyless through Sigstore, on a GitHub-hosted
#      runner, AND from the release tag matching the version we pin. That
#      proves authenticity of an image — but on its own says nothing about
#      what our Dockerfile pins.
#
# Only asserting (2) about exactly the digest in (1) connects them. Without
# this script a Dockerfile edit swapping the image reference and its digest
# together passes every other gate in the repo.
#
# The pinned digest is the multi-arch INDEX digest, and the attestation's
# subject is that same index — so one verification covers the amd64 and the
# arm64 manifest both, including the architecture this build is not
# producing.
set -euo pipefail

dockerfile=Dockerfile
repo=CarlAllenn/edtf
image_repo=ghcr.io/carlallenn/edtf-postgres

# The pinned reference, read from the Dockerfile itself so this gate can
# never drift from what the build actually pulls.
image=$(sed -n "s|^FROM \(${image_repo}[^ ]*\) AS edtf\$|\1|p" "${dockerfile}" | head -1)
if [[ -z ${image} ]]; then
  echo "edtf-attestation: no '${image_repo}... AS edtf' line in ${dockerfile}" >&2
  exit 1
fi

# A tag alone would leave the gate verifying whatever the tag points at
# now, which is not necessarily what the build pulled.
if [[ ${image} != *@sha256:* ]]; then
  echo "edtf-attestation: ${image} is not pinned by digest" >&2
  exit 1
fi

# The ref the signature was minted from is part of the identity, not an
# afterthought. `--signer-workflow` constrains the workflow PATH and says
# nothing about the ref, so an attestation from edtf's publish.yml running
# on ANY branch or tag would satisfy it — the same hole that was closed on
# our own cosign identity by anchoring it through `@refs/heads/main$`
# (publish.yml). Anchoring here is stricter than that, because we can be:
# edtf publishes from a release tag, and the tag is derivable from the very
# pin we are checking, so the gate demands the ONE ref that could
# legitimately have produced these bytes rather than a family of them.
#
# `1.2.3-pg18` -> `1.2.3` -> `refs/tags/v1.2.3`. Bumping the pin moves the
# expected ref with it, so this cannot drift.
tag=${image#*:}
tag=${tag%@*}
version=${tag%-pg*}
if [[ -z ${version} || ${version} == "${tag}" ]]; then
  echo "edtf-attestation: cannot derive a version from tag '${tag}'" >&2
  exit 1
fi
# Escape the dots so 1.2.3 cannot match 1x2x3.
identity="^https://github\.com/${repo}/\.github/workflows/publish\.yml@refs/tags/v${version//./\\.}\$"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# Fail-closed, verified both directions against 1.2.3-pg18: a digest with
# no attestation exits nonzero (HTTP 404 from the attestations API), and so
# does a real attestation checked against the wrong signer identity —
# including one that differs only in the ref.
if ! gh attestation verify "oci://${image}" \
  --repo "${repo}" --cert-identity-regex "${identity}" > "${work}/att" 2>&1; then
  echo "edtf-attestation: attestation verification FAILED for ${image}:" >&2
  echo "edtf-attestation: required identity ${identity}" >&2
  cat "${work}/att" >&2
  exit 1
fi

echo "edtf-attestation: ${image#*@} attested to publish.yml@refs/tags/v${version}"
