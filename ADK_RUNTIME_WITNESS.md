# ADK Runtime Witness

Purpose: isolate binary-wheel/runtime verification from AEGIS canonical lineage and from the Proofline contest repository.

Required checks on GitHub-hosted runners:
- Python 3.12 and 3.13
- exact `google-adk==2.6.3` wheel download
- SHA-256 = `3c53fc7885bbc00f98fe90e30474ad7ef7d1ccdc4dd7aa0be154721e61295f04`
- install ADK + Firestore runtime
- import `Agent`, `App`, and `firestore.Client`
- instantiate `Agent(model="gemini-3.5-flash")` and `App(root_agent=...)`

This branch is only a transport/runtime witness. It does not promote AEGIS canonical authority and does not claim GCP effect execution.
