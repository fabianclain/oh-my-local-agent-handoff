# shellcheck shell=bash
#
# harness-paths.sh — the paths in a working tree that are the HARNESS's, not the implementer's.
#
#   source tools/lib/harness-paths.sh
#   harness_excludes            # prints one git pathspec per line
#
# ## Why this is shared rather than written twice
#
# Two tools have to answer the same question and must not answer it differently:
#
#   verify-round   which changed files are the model's work, for the scope gate
#   sequence       is the tree clean enough to start a step in
#
# Both are asking "ignoring the harness's own footprint, what is in this tree?". When they
# disagree, the sequence refuses to start on a tree the gates would have judged clean — or worse,
# starts on one they would not. This project has already paid for that shape of drift twice:
# bench/run excluded the agent-framework state directories for months while verify-round did not,
# and the first end-to-end run in a fresh project was rejected for three "invented" files that
# were an agent's own state.
#
# The exclusions are deliberately narrow. `.handoff` is NOT excluded wholesale — a model once
# wrote three verification scripts straight into it, and that is real littering the scope gate
# must still catch.

# Every entry carries the reason it is here, because the next person's instinct on reading a
# rejection will be to add one more.
harness_excludes() {
    cat <<'PATHSPECS'
:(exclude).handoff/runs/**
:(exclude).handoff/evidence/**
:(exclude).handoff/plans/**
PATHSPECS
    # Harness territory, not the implementer's work. The driver reads it and the setup guide tells
    # the user to write it; a plan has no reason to name it.
    echo ':(exclude).handoff/config.sh'
    # The run journal — the harness's own records of previous rounds. Counting these as the
    # implementer's work fails every verification after the first, which is exactly what happened
    # the first time the journal was wired in.
    echo ':(exclude).handoff/journal/**'
    # The sanctioned scratch directory. Two of seven rounds in one real feature left scratch files
    # behind, in rounds whose prose explicitly forbade them, and both were the model wanting to
    # inspect a value with no legitimate way to do it. One of those scripts booted the whole
    # application against the live database, which is also the most plausible cause of the database
    # corruption that session. Prose has now failed at this twice; a permitted place to work is
    # more likely to be used than a prohibition is to be obeyed, and it keeps the mess somewhere
    # the round is not judged on and `handoff init` already ignores.
    echo ':(exclude).handoff/scratch/**'
    # The lock, and anything else the harness drops at the top of .handoff. Not a wildcard over
    # .handoff itself — see the header.
    echo ':(exclude).handoff/.lock'
    echo ':(exclude).handoff/ladder-notes.md'
    # Not the implementer's work, and blaming it for these is a false rejection. The first
    # end-to-end run of `handoff do` in a fresh project was rejected for three "invented" files
    # that were the agent framework's own state directory. bench/run had excluded these for
    # months; verify-round had not, and the two disagreeing is exactly the drift that keeps
    # costing this project findings.
    cat <<'PATHSPECS'
:(exclude).omc/**
:(exclude).claude/**
:(exclude)node_modules/**
:(exclude)vendor/**
:(exclude)storage/logs/**
:(exclude)storage/framework/**
PATHSPECS
}
