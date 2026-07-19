# OpenComputers Maintainer Releases

This public repository contains generated, immutable deployment artifacts for
the OpenComputers Maintainer stack. The private source repository is not
mirrored here.

Release directories are append-only. Operators must use URLs pinned to the full
40-character publication commit SHA and must verify the SHA-256 values before
an in-game deployment. Branch names, `latest`, and movable tags are not trusted
deployment identities.

Current release:

- `maintainer-c0.1.2-a0.1.59-g0.1.0-d0.1.62-x0.1.8-b8ac7f191cbc`
- 173 managed files
- Artifact commit: `ce5d28e7f3d3d8e94be42b530c53f2e091abfd7e`
- Bundle SHA-256: `6b94887478afa8b0c23875446553f2115e0d443caa06f4500659d66f8e77cae4`

Previous release:

- `maintainer-c0.1.2-a0.1.57-g0.1.0-d0.1.60-x0.1.8-cdcc24edc0ae`
- Bundle SHA-256: `408a9724823670e5e82f22d60cf7d8ed07af622e6d63a9e712ff5e2968c3fccf`

Superseded releases:

- `maintainer-c0.1.2-a0.1.58-g0.1.0-d0.1.61-x0.1.8-e503776e335e`
  rejected valid OpenOS callable-table Craftable methods during exact State 5
  verification. It must not be used for new deployments.

- `maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.58-x0.1.8-1ab196d99adb`
  rejected GTNH callable-table filesystem callbacks during preflight. It made no
  live target changes, but must not be used for new deployments.
