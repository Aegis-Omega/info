#!/usr/bin/env python3
"""Generate candidate TRACE authority-staleness conformance fixtures.

Candidate-only contribution for agentrust-io/trace-spec#66.

Design constraints from maintainer review:
- crypto-valid is necessary but insufficient;
- one defect per vector;
- state_digest, authority_epoch, fence_token, and replay ledger are the new surface;
- resolved contradictions FAIL;
- unresolvable authority context downgrades honestly to CONTRAINDICATED;
- pure replay changes only replay_seen; every authority binding still matches;
- outputs are deterministic and intended for byte-reproduction guards like trace-spec#171.

This file deliberately does not define normative TRACE schema fields. The fixtures are
candidate test material ahead of the v1.0 schema/editorial decision.
"""
from __future__ import annotations

import copy
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import rfc8785
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

OUT = Path(__file__).resolve().parent
FIXTURE_PROFILE = "trace.authority-binding.candidate.v1"
RECEIPT_TYPE = "agentrust:authority-bound-action-receipt"

# Test-only deterministic Ed25519 private half. It is intentionally committed and
# MUST NOT be used outside this fixture corpus.
PRIVATE_KEY_BYTES = hashlib.sha256(
    b"trace authority-stale candidate fixtures deterministic test key v1"
).digest()
PRIVATE_KEY = Ed25519PrivateKey.from_private_bytes(PRIVATE_KEY_BYTES)
PUBLIC_KEY_BYTES = PRIVATE_KEY.public_key().public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw,
)
KEY_ID = "did:web:fixtures.agentrust.example#authority-stale-ed25519-01"

SESSION_REF = "ses_authority_binding_2026_08_18_001"
ACTION = {
    "agent_id": "did:web:agent.example:worker-17",
    "action_type": "tool.invoke",
    "action_scope": "resource:ledger/demo-account-7",
    "tool_name": "ledger.settle",
    "arguments_digest": "sha256:" + hashlib.sha256(b"{amount:7,currency:TEST}").hexdigest(),
}
POLICY_CURRENT = {
    "policy_id": "enterprise-zero-trust-v7",
    "ruleset": "permit bounded settlement; require fresh authority context",
    "revision": 7,
}
STATE_CURRENT = {
    "resource": "ledger/demo-account-7",
    "version": 19,
    "balance_minor": 10000,
}
STATE_STALE = {
    "resource": "ledger/demo-account-7",
    "version": 18,
    "balance_minor": 10000,
}
CURRENT_AUTHORITY_EPOCH = 42
STALE_AUTHORITY_EPOCH = 41
CURRENT_FENCE_TOKEN = "fence:ledger-demo-account-7:00000042"
STALE_FENCE_TOKEN = "fence:ledger-demo-account-7:00000041"


@dataclass(frozen=True)
class Expected:
    verifier_result: str
    action_receipts_verified: bool
    resolution_class: str
    defect: str | None


def jcs_bytes(value: Any) -> bytes:
    """Canonical bytes under RFC 8785/JCS."""

    return rfc8785.dumps(value)


def sha256_jcs(value: Any) -> str:
    return "sha256:" + hashlib.sha256(jcs_bytes(value)).hexdigest()


ACTION_REF = sha256_jcs(ACTION)
POLICY_DIGEST = sha256_jcs(POLICY_CURRENT)
STATE_CURRENT_DIGEST = sha256_jcs(STATE_CURRENT)
STATE_STALE_DIGEST = sha256_jcs(STATE_STALE)


def sign_payload(payload: dict[str, Any]) -> dict[str, Any]:
    signature = PRIVATE_KEY.sign(jcs_bytes(payload)).hex()
    return {
        "payload": payload,
        "signature": {
            "alg": "EdDSA",
            "kid": KEY_ID,
            "sig": signature,
        },
    }


def verify_signature(envelope: dict[str, Any]) -> bool:
    try:
        PRIVATE_KEY.public_key().verify(
            bytes.fromhex(envelope["signature"]["sig"]),
            jcs_bytes(envelope["payload"]),
        )
        return True
    except Exception:
        return False


def baseline_receipt_payload() -> dict[str, Any]:
    return {
        "type": RECEIPT_TYPE,
        "issued_at": "2026-08-18T18:00:00.000Z",
        "issuer_id": KEY_ID,
        "session_ref": SESSION_REF,
        "action_ref": ACTION_REF,
        "policy_digest": POLICY_DIGEST,
        "state_digest": STATE_CURRENT_DIGEST,
        "authority_epoch": CURRENT_AUTHORITY_EPOCH,
        "fence_token": CURRENT_FENCE_TOKEN,
        "decision": "allow",
    }


def baseline_context() -> dict[str, Any]:
    return {
        "admitted_bindings": {
            "session_ref": SESSION_REF,
            "action_ref": ACTION_REF,
            "policy_digest": POLICY_DIGEST,
        },
        "state_digest_resolution": {
            "status": "resolved",
            "value": STATE_CURRENT_DIGEST,
        },
        "authority_epoch_resolution": {
            "status": "resolved",
            "value": CURRENT_AUTHORITY_EPOCH,
        },
        "fence_token_resolution": {
            "status": "resolved",
            "value": CURRENT_FENCE_TOKEN,
        },
        "replay_ledger": {
            "replay_seen": False,
            "ledger_key": "sha256:" + hashlib.sha256(
                f"{SESSION_REF}|{ACTION_REF}|{CURRENT_AUTHORITY_EPOCH}|{CURRENT_FENCE_TOKEN}".encode()
            ).hexdigest(),
        },
    }


def build_vector(
    *,
    name: str,
    description: str,
    receipt_overrides: dict[str, Any] | None = None,
    context_mutator: Any | None = None,
) -> dict[str, Any]:
    payload = baseline_receipt_payload()
    payload.update(receipt_overrides or {})
    context = baseline_context()
    if context_mutator is not None:
        context_mutator(context)
    return {
        "name": name,
        "description": description,
        "profile": FIXTURE_PROFILE,
        "action": copy.deepcopy(ACTION),
        "trusted_issuer_keys": {
            KEY_ID: {
                "kty": "OKP",
                "crv": "Ed25519",
                "public_key_hex": PUBLIC_KEY_BYTES.hex(),
            }
        },
        "receipt": sign_payload(payload),
        "verification_context": context,
    }


def detected_defects(vector: dict[str, Any]) -> list[str]:
    payload = vector["receipt"]["payload"]
    context = vector["verification_context"]
    defects: list[str] = []

    # Existing covered fields stay equal in every candidate here. If one changes,
    # the generator fails instead of silently adding a second defect.
    for field in ("session_ref", "action_ref", "policy_digest"):
        if payload[field] != context["admitted_bindings"][field]:
            defects.append(f"existing_{field}_mismatch")

    state = context["state_digest_resolution"]
    if state["status"] == "unresolvable":
        defects.append("state_digest_unresolvable")
    elif payload["state_digest"] != state["value"]:
        defects.append("state_digest_mismatch")

    epoch = context["authority_epoch_resolution"]
    if epoch["status"] == "unresolvable":
        defects.append("authority_epoch_unresolvable")
    elif payload["authority_epoch"] != epoch["value"]:
        defects.append("stale_authority_epoch")

    fence = context["fence_token_resolution"]
    if fence["status"] == "unresolvable":
        defects.append("fence_token_unresolvable")
    elif payload["fence_token"] != fence["value"]:
        defects.append("fence_token_mismatch")

    if context["replay_ledger"]["replay_seen"] is True:
        defects.append("pure_replay")

    return defects


def write_json(path: Path, value: Any) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    vectors: dict[str, dict[str, Any]] = {}
    expected: dict[str, Expected] = {}

    vectors["01-valid-current-authority.json"] = build_vector(
        name="valid-current-authority",
        description=(
            "Crypto-valid baseline: every admitted authority binding resolves and "
            "matches, and the replay ledger has not seen this authorization instance."
        ),
    )
    expected["01-valid-current-authority.json"] = Expected(
        verifier_result="PASS",
        action_receipts_verified=True,
        resolution_class="RESOLVED_MATCH",
        defect=None,
    )

    vectors["02-state-digest-mismatch.json"] = build_vector(
        name="state-digest-mismatch",
        description=(
            "The receipt is correctly signed but names a stale state digest while the "
            "current admitted state resolves successfully. This is a resolved "
            "contradiction, not an availability failure."
        ),
        receipt_overrides={"state_digest": STATE_STALE_DIGEST},
    )
    expected["02-state-digest-mismatch.json"] = Expected(
        verifier_result="FAIL",
        action_receipts_verified=False,
        resolution_class="CONTRADICTED",
        defect="state_digest_mismatch",
    )

    vectors["03-stale-authority-epoch.json"] = build_vector(
        name="stale-authority-epoch",
        description=(
            "The receipt is correctly signed and all other bindings match, but its "
            "authority_epoch is one epoch behind the resolved current authority epoch."
        ),
        receipt_overrides={"authority_epoch": STALE_AUTHORITY_EPOCH},
    )
    expected["03-stale-authority-epoch.json"] = Expected(
        verifier_result="FAIL",
        action_receipts_verified=False,
        resolution_class="CONTRADICTED",
        defect="stale_authority_epoch",
    )

    def epoch_unresolvable(context: dict[str, Any]) -> None:
        context["authority_epoch_resolution"] = {
            "status": "unresolvable",
            "reason": "resolver_unavailable",
        }

    vectors["04-authority-epoch-unresolvable.json"] = build_vector(
        name="authority-epoch-unresolvable",
        description=(
            "The receipt is correctly signed and internally well-formed, but the "
            "verifier cannot resolve the current authority epoch. The verifier must "
            "downgrade honestly rather than upgrade from signature validity."
        ),
        context_mutator=epoch_unresolvable,
    )
    expected["04-authority-epoch-unresolvable.json"] = Expected(
        verifier_result="CONTRAINDICATED",
        action_receipts_verified=False,
        resolution_class="UNRESOLVABLE",
        defect="authority_epoch_unresolvable",
    )

    vectors["05-fence-token-mismatch.json"] = build_vector(
        name="fence-token-mismatch",
        description=(
            "The receipt is correctly signed and authority_epoch is current, but the "
            "fence_token does not match the resolved current fence. Epoch and fence are "
            "kept independent so this vector exercises exactly one defect."
        ),
        receipt_overrides={"fence_token": STALE_FENCE_TOKEN},
    )
    expected["05-fence-token-mismatch.json"] = Expected(
        verifier_result="FAIL",
        action_receipts_verified=False,
        resolution_class="CONTRADICTED",
        defect="fence_token_mismatch",
    )

    def replay_seen(context: dict[str, Any]) -> None:
        context["replay_ledger"]["replay_seen"] = True

    vectors["06-pure-replay.json"] = build_vector(
        name="pure-replay",
        description=(
            "Every receipt/admitted binding matches and the signature is valid. The "
            "only defect is replay_seen=true for the exact authorization instance."
        ),
        context_mutator=replay_seen,
    )
    expected["06-pure-replay.json"] = Expected(
        verifier_result="FAIL",
        action_receipts_verified=False,
        resolution_class="REPLAYED",
        defect="pure_replay",
    )

    # ----- self-check the corpus before writing any bytes -------------------
    failures: list[str] = []
    baseline_payload = vectors["01-valid-current-authority.json"]["receipt"]["payload"]

    for filename, vector in vectors.items():
        if not verify_signature(vector["receipt"]):
            failures.append(f"{filename}: crypto signature did not verify")

        defects = detected_defects(vector)
        exp = expected[filename]
        expected_defects = [] if exp.defect is None else [exp.defect]
        if defects != expected_defects:
            failures.append(
                f"{filename}: defects={defects!r}, expected={expected_defects!r}"
            )

        if exp.verifier_result == "PASS" and defects:
            failures.append(f"{filename}: PASS vector carries a defect")
        if exp.verifier_result in {"FAIL", "CONTRAINDICATED"} and len(defects) != 1:
            failures.append(f"{filename}: negative vector must have exactly one defect")

        # Every candidate in this set must stay crypto-valid. This is the theorem
        # under test: signature validity never upgrades stale/unresolvable authority.
        if exp.action_receipts_verified is False and not verify_signature(vector["receipt"]):
            failures.append(f"{filename}: negative vector must remain crypto-valid")

    # Pure replay is specifically required to have byte-identical signed receipt
    # content to the valid baseline; only replay-ledger context may differ.
    replay_payload = vectors["06-pure-replay.json"]["receipt"]["payload"]
    if replay_payload != baseline_payload:
        failures.append("06-pure-replay.json: receipt payload differs from valid baseline")

    # The stale-epoch vector must not also stale the fence.
    epoch_payload = vectors["03-stale-authority-epoch.json"]["receipt"]["payload"]
    if epoch_payload["fence_token"] != CURRENT_FENCE_TOKEN:
        failures.append("03-stale-authority-epoch.json: fence token also changed")

    # The fence-mismatch vector must not also stale the epoch.
    fence_payload = vectors["05-fence-token-mismatch.json"]["receipt"]["payload"]
    if fence_payload["authority_epoch"] != CURRENT_AUTHORITY_EPOCH:
        failures.append("05-fence-token-mismatch.json: authority epoch also changed")

    # No expected code may smuggle a multi-defect disjunction back into the corpus.
    for filename, exp in expected.items():
        rendered = json.dumps(exp.__dict__, sort_keys=True)
        if " OR " in rendered.upper():
            failures.append(f"{filename}: expected outcome contains disjunction")

    if failures:
        raise SystemExit("SELF-CHECK FAILED\n" + "\n".join(failures))

    for filename, vector in vectors.items():
        write_json(OUT / filename, vector)

    expected_doc = {
        "schema_version": "candidate-1",
        "source_issue": "agentrust-io/trace-spec#66",
        "non_normative": True,
        "principle": "crypto_valid=true is necessary but insufficient for authority-context verification",
        "existing_coverage_reused": {
            "session_ref": ["acta/06-session-binding-mismatch", "conformance/12", "conformance/21"],
            "action_ref": ["conformance/05", "conformance/10", "conformance/18", "conformance/19"],
            "policy_digest": ["acta/05-stale-policy-digest"],
        },
        "new_surface": ["state_digest", "authority_epoch", "fence_token", "replay_ledger"],
        "results": {
            filename: {
                "crypto_valid": True,
                "verifier_result": exp.verifier_result,
                "action_receipts_verified": exp.action_receipts_verified,
                "resolution_class": exp.resolution_class,
                "defect": exp.defect,
            }
            for filename, exp in expected.items()
        },
    }
    write_json(OUT / "expected.json", expected_doc)
    write_json(
        OUT / "key-material.json",
        {
            "warning": "TEST-ONLY DETERMINISTIC KEY MATERIAL; NEVER USE IN PRODUCTION",
            "algorithm": "Ed25519",
            "kid": KEY_ID,
            "private_key_hex": PRIVATE_KEY_BYTES.hex(),
            "public_key_hex": PUBLIC_KEY_BYTES.hex(),
            "seed_derivation": "sha256('trace authority-stale candidate fixtures deterministic test key v1')",
        },
    )

    print("AUTHORITY_STALE_FIXTURES_GENERATED")
    print(f"vectors={len(vectors)}")
    print(f"public_key={PUBLIC_KEY_BYTES.hex()}")
    for filename in sorted(vectors):
        exp = expected[filename]
        print(
            f"{filename}: crypto_valid=true defect={exp.defect or 'none'} "
            f"verifier_result={exp.verifier_result}"
        )


if __name__ == "__main__":
    main()
