#!/usr/bin/env bash
# edtf-postgres supply-chain gate. Closes the loop between the checksums
# pinned in the Dockerfile and the release they claim to come from. Two
# facts, and NEITHER is sufficient alone:
#
#   1. The build enforces that the downloaded tarball matches a pinned hash
#      (BuildKit's ADD --checksum, fail-closed). That proves the download
#      did not change. It does not prove the hash is the right one.
#   2. `gh attestation verify` proves SHA256SUMS was produced by edtf's own
#      publish workflow, keyless through Sigstore, on a GitHub-hosted
#      runner. That proves authenticity of the file — but says nothing
#      about what our Dockerfile pins.
#
# Only asserting (2) AND that the pinned values appear in that attested file
# connects them. Without this script a Dockerfile edit changing the URL and
# the checksum together passes every other gate in the repo.
#
# All of the release's tarballs and SHA256SUMS are subjects of one
# provenance statement, so verifying SHA256SUMS covers every tarball.
set -euo pipefail

dockerfile=Dockerfile
repo=CarlAllenn/edtf
workflow="${repo}/.github/workflows/publish.yml"

arg() {
  # The pinned value of a build arg, read from the Dockerfile itself so this
  # gate can never drift from what the build actually uses.
  value=$(sed -n "s/^ARG ${1}=\(.*\)$/\1/p" "${dockerfile}" | head -1)
  if [[ -z ${value} ]]; then
    echo "edtf-attestation: ${1} not found in ${dockerfile}" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

version=$(arg EDTF_POSTGRES_VERSION)
sha_amd64=$(arg EDTF_SHA256_AMD64)
sha_arm64=$(arg EDTF_SHA256_ARM64)
tag="edtf-postgres-v${version}"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

if ! gh release download "${tag}" --repo "${repo}" \
  --pattern SHA256SUMS --dir "${work}" 2> "${work}/err"; then
  echo "edtf-attestation: cannot fetch SHA256SUMS for ${tag}:" >&2
  cat "${work}/err" >&2
  exit 1
fi

# Fail-closed: an unverifiable or tampered file has no attestation for its
# digest and exits nonzero (verified both directions against v1.1.2).
if ! gh attestation verify "${work}/SHA256SUMS" \
  --repo "${repo}" --signer-workflow "${workflow}" > "${work}/att" 2>&1; then
  echo "edtf-attestation: attestation verification FAILED for ${tag}:" >&2
  cat "${work}/att" >&2
  exit 1
fi

status=0
check() {
  # $1 = architecture, $2 = the checksum pinned in the Dockerfile
  asset="edtf_postgres-${version}-pg18-linux-${1}.tar.gz"
  attested=$(awk -v a="${asset}" '$2 == a { print $1 }' "${work}/SHA256SUMS")
  if [[ -z ${attested} ]]; then
    echo "edtf-attestation: ${asset} is not in the attested SHA256SUMS" >&2
    status=1
    return
  fi
  if [[ ${attested} != "${2}" ]]; then
    echo "edtf-attestation: ${asset} checksum does not match the attested release" >&2
    echo "  Dockerfile pins: ${2}" >&2
    echo "  attested:        ${attested}" >&2
    status=1
  fi
}

check amd64 "${sha_amd64}"
check arm64 "${sha_arm64}"

if [[ ${status} -eq 0 ]]; then
  echo "edtf-attestation: ${tag} attested to ${workflow}; both pinned checksums match"
fi
exit "${status}"
