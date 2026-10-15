# AEGIS PR-1 External Exact-Head Witness

This branch exists only to trigger an external execution witness for:

- source repository: `Aegis-Omega/AEGIS-OMEGA`
- candidate SHA: `6bf071d9c757d0f3514904f1efad3e3b14a60a09`
- expected parent SHA: `32b7eb6a37fb69d19dd80189390b6641c5004ef1`

The witness is explicitly **not** repo-native AEGIS CI, canonical admission, EffectBoundAdmission, or production proof. It exists to establish whether the frozen PR-1 transition-binding and receipt-separation code actually executes and passes its exact 58-test Automaton-3 suite on an independently allocated GitHub-hosted runner.
