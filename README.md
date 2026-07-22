# OpenComputers Maintainer Releases

This public repository contains generated, immutable deployment artifacts for
the OpenComputers Maintainer stack. The private source repository is not
mirrored here.

Release directories are append-only. Operators must use URLs pinned to the full
40-character publication commit SHA and must verify the SHA-256 values before
an in-game deployment. Branch names, `latest`, and movable tags are not trusted
deployment identities.

Current release:

- `maintainer-c0.1.2-a0.1.62-g0.1.0-d0.1.65-x0.1.8-3d612527d052`
- 177 managed files
- Artifact commit: `1ac9c5ed6f4a7ef603d01f99f062ba39c6a0d87b`
- Bundle SHA-256: `acc23e4e30c61bc6e868e86d0ad3a5c25fc03787de48e35574cb0c337eca38e4`

Previous release:

- `maintainer-c0.1.2-a0.1.61-g0.1.0-d0.1.64-x0.1.8-49c169136e34`
- Bundle SHA-256: `4b2398d4ac2996fcc4b704ebd1e92ede1361b3d23ab5d0c0fc3164d16e74008a`

Superseded releases:

- `maintainer-c0.1.2-a0.1.58-g0.1.0-d0.1.61-x0.1.8-e503776e335e`
  rejected valid OpenOS callable-table Craftable methods during exact State 5
  verification. It must not be used for new deployments.

- `maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.58-x0.1.8-1ab196d99adb`
  rejected GTNH callable-table filesystem callbacks during preflight. It made no
  live target changes, but must not be used for new deployments.
