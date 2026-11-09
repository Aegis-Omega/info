# AEGIS PR-2 Final Scoped Exact-Head Witness

Exact source candidate: `Aegis-Omega/AEGIS-OMEGA@e3dc56f3da9156c091bfbc2067d775aa2190ac6d`

Stacked parent: `6bf071d9c757d0f3514904f1efad3e3b14a60a09`

Required evidence scope:
- schema validation including EffectWitness;
- exact 75-test Automaton-3 suite;
- MCP fail-closed integration;
- claims and constitutional hash checks;
- canonical `validate-automaton3.py` with external-runner OIDC availability;
- manifest binding of effect adapter/test/schema;
- receipt-level `admission_scope = REPOSITORY_CANDIDATE_ADMISSION_NOT_EFFECT_BOUND_STATE_ADMISSION`;
- caller-supplied post-state authority remains forbidden;
- CompleteVerification / AtomicAdmission / EffectBoundAdmission remain unavailable.

Any successful result is `EXTERNAL_EXACT_HEAD_WITNESS`, never AEGIS repo-native CI or effect-bound state admission.
