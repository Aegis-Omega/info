# Candidate authority-staleness fixtures for TRACE #66

This directory is a **non-normative candidate fixture set** for `agentrust-io/trace-spec#66`, prepared from maintainer review on 2026-08-16 / 2026-08-18.

It does **not** propose a schema diff or normative `verification.md` language. The goal is to give maintainers deterministic bytes that can test the eventual v1.0 authority-context semantics the day the schema/editorial decision lands.

The generated JSON fixtures are committed beside the generator. CI must now regenerate them and prove byte-for-byte equality; a changed generator or hand-edited fixture must therefore fail closed rather than drift silently.

## Maintainer-requested boundary

The corpus tests the proposition:

```text
crypto_valid = true
!=
action_receipts_verified = true
```

A correctly signed receipt must still fail closed when its authority context is stale or contradicted, and must honestly downgrade when the relevant authority context cannot be resolved.

Existing TRACE coverage is intentionally reused rather than duplicated:

- `session_ref`: ACTA `06-session-binding-mismatch` + conformance `12` / `21`
- `action_ref`: conformance `05` / `10` / `18` / `19`
- `policy_digest`: ACTA `05-stale-policy-digest`

This candidate set covers the maintainer-identified uncovered surface:

```text
state_digest
authority_epoch
fence_token
replay ledger
```

## Vectors

| file | only defect | expected candidate result |
|---|---|---|
| `01-valid-current-authority.json` | none | `PASS` |
| `02-state-digest-mismatch.json` | `state_digest_mismatch` | `FAIL` |
| `03-stale-authority-epoch.json` | `stale_authority_epoch` | `FAIL` |
| `04-authority-epoch-unresolvable.json` | `authority_epoch_unresolvable` | `CONTRAINDICATED` |
| `05-fence-token-mismatch.json` | `fence_token_mismatch` | `FAIL` |
| `06-pure-replay.json` | `pure_replay` | `FAIL` |

`06-pure-replay.json` is deliberately strict: its signed receipt payload is identical to the valid baseline. Every binding matches. Only `verification_context.replay_ledger.replay_seen` changes to `true`.

`03-stale-authority-epoch.json` and `05-fence-token-mismatch.json` are separate vectors. The stale-epoch vector keeps the current fence; the fence-mismatch vector keeps the current epoch.

`04-authority-epoch-unresolvable.json` is distinct from stale/contradicted authority. The resolver has no current epoch value, so the expected candidate behavior is an honest downgrade to `CONTRAINDICATED`, not a fabricated comparison and not an upgrade from signature validity.

## Cryptography and determinism

`gen_authority_stale_fixtures.py` uses:

- RFC 8785 / JCS canonicalization via `rfc8785`;
- Ed25519 signatures via `cryptography`;
- a deterministic, **test-only** private seed committed in generated `key-material.json`;
- real signature verification of every generated vector;
- a self-check that every negative vector carries exactly one defect;
- explicit checks that pure replay changes no receipt binding;
- explicit checks that stale epoch does not also stale the fence and vice versa.

The generated JSON files live beside the generator so they fit the byte-reproduction pattern merged in `trace-spec#171`: discovery of `gen_*.py`, regeneration in an isolated copy, name-set comparison, and byte-for-byte fixture comparison.

## Generate

```bash
python -m pip install rfc8785==0.1.4 cryptography==49.0.0
python examples/authority-stale/gen_authority_stale_fixtures.py
```

Expected stdout starts with:

```text
AUTHORITY_STALE_FIXTURES_GENERATED
vectors=6
```

## Candidate-only field layout

The vectors intentionally use a candidate wrapper rather than pretending the still-live v1.0 schema decision has already landed:

```text
receipt.payload
verification_context.admitted_bindings
verification_context.state_digest_resolution
verification_context.authority_epoch_resolution
verification_context.fence_token_resolution
verification_context.replay_ledger
```

That layout exists only to make the semantic defects mechanically testable now. Maintainers remain authoritative over the eventual TRACE schema placement and normative vocabulary.
