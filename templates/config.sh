# Copy to <your-repo>/.handoff/config.sh and edit.
#
# PROJECT_RULES is injected into every implementer prompt. Without it the implementer has no
# idea how your project builds, tests, or formats, and you will spend review rounds on churn
# that a few lines here would have prevented.
#
# Keep it short and specific. Conventions the implementer cannot infer from the code are worth
# far more than restating things it can already see.

read -r -d '' PROJECT_RULES <<'RULES' || true
Project conventions:
- Format with `<your formatter>` before finishing. This is mandatory.
- Generate files with `<your scaffolding command>`, non-interactively.
- Tests live in `<path>` and run with `<command>`.
- <Any architectural rule that is not obvious from reading one file.>
- <Any trap that has bitten before — those are the highest-value lines here.>
RULES

# Optional: override where plans and run artifacts live.
# HANDOFF_PLANS_DIR="$REPO_ROOT/.handoff/plans"
# HANDOFF_RUNS_DIR="$REPO_ROOT/.handoff/runs"

# Optional: how many tool-calling iterations the local model gets before a round is cut off.
#
# Raise this if rounds end on the turn limit with the work half-written — check the round's last
# reasoning block before deciding, because a model that was still searching needs a better plan
# rather than more turns, and one that was mid-implementation needs exactly this.
#
# Large existing files are what usually exhausts it. A codebase of 1,000-line classes may want 120.
# NATIVE_MAX_TURNS=80
