# Driving this from an agent CLI

The same procedure, in each CLI's own format. Both do the identical thing: interview, wire the
project up, write a machine-verifiable plan, check it, run it against the local model, and report
the harness's verdict rather than the model's account of itself.

| CLI | Install |
| --- | --- |
| Claude Code | `cp -r integrations/claude-skills/local-implementer ~/.claude/skills/` |
| Codex | `cp integrations/codex-prompts/local-implementer.md ~/.codex/prompts/` |

Both are global once installed — every project on the machine, nothing per-project beyond
`handoff init`.

## Keep the driver and the implementer different

The procedure tells the driver to use `HANDOFF_PROVIDER=native`. That matters most in Codex, where
`codex` is also a perfectly good *implementer* and is in fact this harness's default provider. If
the same model both writes the plan and implements it, the independence that makes a verdict worth
anything is gone — a model checking its own work is the thing this whole repository exists to
avoid.

Codex planning and a local model implementing is a sound pairing, and the cheapest one available.

## Why a driver integration is worth having at all

The measured bottleneck is not the local model's coding: 29 of 30 runs met every acceptance
criterion on a six-file task. It is producing a specification whose claims are mechanically
checkable — and every one of the 48 existing plans on the project this was extracted from failed
that test. Writing them is what a hosted model is good at and the local model is not.
