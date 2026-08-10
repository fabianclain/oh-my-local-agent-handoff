---
name: local-implement
description: Design a feature, write a machine-verifiable plan, and have a local model on this machine implement it while the harness verifies the result. Use when the user asks to build or change something with the local model, mentions agent-handoff, or says "implement this locally". Also use when they want a plan written in verifiable form.
user-invocable: true
---

# Implementing with the local model

You design and specify. A local model (gpt-oss-20b on this machine) writes the code. The harness
decides whether the result is acceptable — not you, and never the model's own report.

Your job is the part the local model cannot do: turning a request into a specification whose every
claim is mechanically checkable. That is the measured bottleneck.

