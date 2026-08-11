#!/usr/bin/env bash
#
# Bench label: lcgptossllint — gpt-oss 20B, llama.cpp, reasoning low. Identical to lcgptossl except
# that the editing rules require a syntax check immediately after every write, and a repair before
# anything else happens.
#
# This is round 16 in docs/BENCHMARK-QUEUE.md, and it targets the failure that ended the two most
# promising rounds of a real feature: a docblock run into a method body, parse error, both times on
# files over 150 lines being edited a second time. The model then kept working against a file that
# no longer parsed, and spent the rest of its budget building on it. The round was lost long before
# the harness saw it.
#
# The hypothesis is narrow and worth stating precisely, because the arm is easy to over-read: it is
# not that the model can avoid producing a broken edit. It is that a broken edit discovered on the
# next turn is repairable, and a broken edit discovered at the end of the round is not.
#
# WHAT THIS IS NOT
#
# It is not a post-write hook. Cline exposes no way to run a command between a tool call and the
# next turn, so this is a prompt-layer instruction and the model can ignore it — and sometimes will.
# A true hook would be strictly stronger and is the follow-up if this arm shows anything. Reading
# this as "a linter ran after every write" would overstate what was measured; what was measured is
# "the model was told to run one".
#
# The instruction is spliced into the canonical rules rather than copied into a second rules file.
# A copy drifts: this repository has already been bitten by two tools parsing plans with separate
# copies of the same expressions, and tools/build-integrations exists because a procedure was
# hand-ported three times and diverged on the third.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossllint"; }

_lcgptossllint_home="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_lcgptossllint_base_preflight() { :; }
eval "_lcgptossllint_base_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _lcgptossllint_base_preflight || return 1

    local source_rules="$_lcgptossllint_home/templates/agent-rules.md"
    local spliced="${TMPDIR:-/tmp}/agent-handoff-lint-rules.md"
    [[ -f "$source_rules" ]] || {
        echo "cannot find templates/agent-rules.md to splice the syntax rule into" >&2
        return 1
    }

    # Anchored on the rule it extends — "read the changed section back and verify it" is the vague
    # version of the same idea, and putting the executable form directly after it keeps the two
    # from reading as separate demands.
    local anchor='- After each edit, read the changed section back and verify it.'
    grep -qF -- "$anchor" "$source_rules" || {
        echo "the anchor rule has moved in templates/agent-rules.md; this arm would silently" >&2
        echo "become identical to lcgptossl, which is worse than failing." >&2
        return 1
    }

    awk -v anchor="$anchor" '
        { print }
        $0 == anchor {
            print "- After every write to a file, immediately run the language syntax checker on that"
            print "  file before doing anything else. For PHP that is `php -l <file>`."
            print "- If the syntax check fails, your next action must be to fix that file. Do not"
            print "  continue with the task, do not edit another file, and do not run the acceptance"
            print "  commands until it parses."
        }
    ' "$source_rules" >"$spliced" || return 1

    export HANDOFF_AGENT_RULES="$spliced"
}
