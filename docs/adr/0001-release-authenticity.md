# ADR 0001: Commit-pinned releases with keyless evidence

- Status: Accepted
- Date: 2026-11-17

## Context

Reparo is frequently installed with elevated privileges. A mutable branch URL or a
release record that cannot be tied back to reviewed source leaves operators unable
to distinguish reviewed bytes from later repository changes. Long-lived signing
keys would add a high-value secret and rotation burden to this repository.

## Decision

Use a two-transaction release:

1. Merge and validate the coherent source change.
2. In a later reviewed commit, update the candidate or production manifest with the
   exact source commit, commit-derived raw URLs, SHA-256 values, and source version.

Third-party Actions are pinned to commit SHAs. A release tag runs the provenance
workflow with GitHub OIDC, emits deterministic SPDX 2.3 and checksum artifacts, and
creates GitHub build-provenance and SBOM attestations. No signing secret is stored.
Production publication still requires protected review, successful CI, and a canary;
an attestation is evidence, not an independent authorization to deploy.

## Custody, rotation, revocation, and failure behavior

GitHub's short-lived OIDC workflow identity and managed artifact-attestation signing
service hold the signing authority. Reparo maintainers do not generate, export, or
rotate a private signing key. Trust-root and signer rotation are therefore GitHub's
responsibility; maintainers review and pin attestation Action updates, keep a supported
GitHub CLI verifier, and rerun a known-good verification after either changes.

A cryptographic statement is historical evidence and cannot be made untrue after
publication. If a release must be withdrawn, remove it from the production manifest,
block or delete its mutable release/tag entry through the emergency review path,
publish a revocation notice naming version, hashes, reason, and replacement, and
advance to a reviewed release. Retain the original attestation for audit. Verification
policy must therefore require both a valid GitHub attestation and current authorization
by the production manifest; a valid attestation for a withdrawn artifact is insufficient.

Attestation lookup and verification are online release gates. If GitHub identity,
attestation, transparency, or verifier services are unavailable or return an uncertain
result, do not publish or newly deploy that release. An isolated site may continue a
previously approved version using its retained manifest, bytes, and hash evidence, but
must not treat cached source or an unverifiable new bundle as newly approved. Rollback
uses the last retained reviewed production manifest and does not require weakening a
verification check.

## Consequences

- Runtime installers can remain simple and authorize exact bytes from the manifest.
- Operators can verify downloaded release bundles with `gh attestation verify`.
- Rotation has no repository secret ceremony, while withdrawal requires an explicit
  authorization record because historical attestations remain valid evidence.
- Source and manifest cannot be one self-referential commit, so release promotion
  necessarily takes two commits.
- Repository protection and GitHub availability remain part of the trust base.
