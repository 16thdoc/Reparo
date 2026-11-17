# Reparo 1.4.4.10

This release closes the privileged deployment gaps found in the November 2026
security review.

- Windows `-New`, the CMD installer, and SSH deployment now verify the reviewed
  manifest schema, immutable source URL, SHA-256, and version before execution.
- Custom network sources require absolute HTTPS URLs without embedded credentials
  and an explicit digest in deployment helpers.
- ProgramData installation rejects reparse points and installs an ACL that permits
  writes only to SYSTEM and Administrators while retaining standard-user read and
  execute access. Non-elevated logs move to the user's local application-data root.
- Bootstrap files use randomly named temporary directories instead of the final
  privileged install tree.
- The Moshi helper replaces `curl | sh` with download, digest verification, syntax
  validation, and file-based execution.
- GitHub Actions checkout dependencies are pinned to an immutable commit, and a
  security regression suite guards these boundaries.
- Empty persistent-syslog settings remain readable under strict mode.

Windows and native Linux retain one release identity. The native runner has no
equivalent privileged machine install: it already uses a private user data root,
HTTPS-only curl, immutable manifest URLs, hashes, and POSIX syntax validation.
