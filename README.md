# OpenComputers Maintainer Releases

This public repository contains generated, immutable deployment artifacts for
the OpenComputers Maintainer stack. The private source repository is not
mirrored here.

Release directories are append-only. Operators must use URLs pinned to the full
40-character publication commit SHA and must verify the SHA-256 values before
an in-game deployment. Branch names, `latest`, and movable tags are not trusted
deployment identities.

Current release:

- `maintainer-c0.1.2-a0.1.60-g0.1.0-d0.1.63-x0.1.8-65c5e4bf031f`
- 174 managed files
- Artifact commit: `1551744d3589321355f7b216b24a07980d1047fb`
- Bundle SHA-256: `6aa1ffa652e4fa51632448f3fc20541a6dc53852174a30be64c67f4acea1200d`

Previous release:

- `maintainer-c0.1.2-a0.1.59-g0.1.0-d0.1.62-x0.1.8-b8ac7f191cbc`
- Bundle SHA-256: `6b94887478afa8b0c23875446553f2115e0d443caa06f4500659d66f8e77cae4`

Superseded releases:

- `maintainer-c0.1.2-a0.1.58-g0.1.0-d0.1.61-x0.1.8-e503776e335e`
  rejected valid OpenOS callable-table Craftable methods during exact State 5
  verification. It must not be used for new deployments.

- `maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.58-x0.1.8-1ab196d99adb`
  rejected GTNH callable-table filesystem callbacks during preflight. It made no
  live target changes, but must not be used for new deployments.
