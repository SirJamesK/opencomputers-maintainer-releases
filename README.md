# OpenComputers Maintainer Releases

This public repository contains generated, immutable deployment artifacts for
the OpenComputers Maintainer stack. The private source repository is not
mirrored here.

Release directories are append-only. Operators must use URLs pinned to the full
40-character publication commit SHA and must verify the SHA-256 values before
an in-game deployment. Branch names, `latest`, and movable tags are not trusted
deployment identities.

Current release:

- `maintainer-c0.1.2-a0.1.70-g0.1.0-d0.1.73-x0.1.11-87e2cfcef07f`
- 182 managed files
- Artifact commit: `bb35a9ba71b5f4e1867c491e4bc664786383ba91`
- Bundle SHA-256: `ca7f3b683ffcc69bbd8748a0006c122064c3013db25a7f84fe7e4f3123f67869`

Previous releases:

- `maintainer-c0.1.2-a0.1.69-g0.1.0-d0.1.72-x0.1.11-10946c619334`
- 182 managed files
- Artifact commit: `efd8076ffc81877f0ec4a71071471363dbc68d2e`
- Bundle SHA-256: `83ad2c93e9fbc92b40b9c481940f5ac0beb27e53ef04a7ab9cf1487a7b7e68c5`

- `maintainer-c0.1.2-a0.1.68-g0.1.0-d0.1.71-x0.1.10-510ad6407eae`
- 178 managed files
- Artifact commit: `8eb7c57f561daecb74a8189ffac0cda73b2c312c`
- Bundle SHA-256: `e305ec604425a9972eb31e471d9fe87907af2feb2fd1c6f4ea2281b99425e58f`

- `maintainer-c0.1.2-a0.1.65-g0.1.0-d0.1.68-x0.1.10-73602ba093a0`
- Bundle SHA-256: `358be84ab127899345d7a77e4f5e57dbb0d9e980e74d6945e167448d39fd7749`

- `maintainer-c0.1.2-a0.1.62-g0.1.0-d0.1.65-x0.1.8-3d612527d052`
- Bundle SHA-256: `acc23e4e30c61bc6e868e86d0ad3a5c25fc03787de48e35574cb0c337eca38e4`

Superseded releases:

- `maintainer-c0.1.2-a0.1.67-g0.1.0-d0.1.70-x0.1.10-d7a06017a26d`
  falsely treated a valid OpenOS no-return runtime-state file close as failure,
  which could leave the GTNH 2.8.4 Craft API selector locked. It must not be
  used for new deployments.

- `maintainer-c0.1.2-a0.1.58-g0.1.0-d0.1.61-x0.1.8-e503776e335e`
  rejected valid OpenOS callable-table Craftable methods during exact State 5
  verification. It must not be used for new deployments.

- `maintainer-c0.1.2-a0.1.56-g0.1.0-d0.1.58-x0.1.8-1ab196d99adb`
  rejected GTNH callable-table filesystem callbacks during preflight. It made no
  live target changes, but must not be used for new deployments.
