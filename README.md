# OpenComputers Maintainer Releases

This public repository contains generated, immutable deployment artifacts for
the OpenComputers Maintainer stack. The private source repository is not
mirrored here.

Release directories are append-only. Operators must use URLs pinned to the full
40-character publication commit SHA and must verify the SHA-256 values before
an in-game deployment. Branch names, `latest`, and movable tags are not trusted
deployment identities.

Current release:

- `maintainer-c0.1.2-a0.1.67-g0.1.0-d0.1.70-x0.1.10-d7a06017a26d`
- 178 managed files
- Artifact commit: `9de654203e87b72b2a4c52956ea636b14c4d6861`
- Bundle SHA-256: `96d897577837de639e616518671cb56ef03d45b5b7561d24d9ed1835305c2b38`

Previous releases:

- `maintainer-c0.1.2-a0.1.65-g0.1.0-d0.1.68-x0.1.10-73602ba093a0`
- Bundle SHA-256: `358be84ab127899345d7a77e4f5e57dbb0d9e980e74d6945e167448d39fd7749`

- `maintainer-c0.1.2-a0.1.62-g0.1.0-d0.1.65-x0.1.8-3d612527d052`
- Bundle SHA-256: `acc23e4e30c61bc6e868e86d0ad3a5c25fc03787de48e35574cb0c337eca38e4`

Superseded releases:

- `maintainer-c0.1.2-a0.1.58-g0.1.0-d0.1.61-x0.1.8-e503776e335e`
  rejected valid OpenOS callable-table Craftable methods during exact State 5
  verification. It must not be used for new deployments.

- `maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.58-x0.1.8-1ab196d99adb`
  rejected GTNH callable-table filesystem callbacks during preflight. It made no
  live target changes, but must not be used for new deployments.
