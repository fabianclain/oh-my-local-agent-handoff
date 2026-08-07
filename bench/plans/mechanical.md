# Mechanical fixture: normalize one name

## Goal

Create a small Bash command that normalizes one user-supplied name and rejects invalid calls.

## Context

This is a standalone fixture. Do not inspect or reuse application code from the repository.

The command accepts exactly one argument. It converts ASCII uppercase letters to lowercase,
replaces each sequence of non-ASCII-alphanumeric characters with one hyphen, and removes a
leading or trailing hyphen. A normalized value containing no alphanumeric character is invalid.

Use Bash and existing shell utilities only. The script must use `set -euo pipefail`, guard clauses,
and an explanatory comment for the empty-result check.

## States to handle

- zero or more than one argument: print `usage: normalize-name <name>` to stderr and exit 64
- an input that normalizes to an empty string: print `name has no alphanumeric characters` to
  stderr and exit 1
- valid input: print only the normalized value and a newline to stdout

## Files to touch

| Path | Action |
| --- | --- |
| `bench-fixture/mechanical/normalize-name` | create, chmod +x |

## Acceptance criteria

- [ ] the command passes Bash syntax validation and is executable
- [ ] `Hello World` normalizes to `hello-world`
- [ ] repeated punctuation is collapsed and edge punctuation is removed
- [ ] an invalid argument count reports usage on stderr and exits 64
- [ ] punctuation-only input reports the empty-result failure and exits 1

## Verification

```bash
bash -n bench-fixture/mechanical/normalize-name && test -x bench-fixture/mechanical/normalize-name
test "$(bench-fixture/mechanical/normalize-name 'Hello World')" = "hello-world"
test "$(bench-fixture/mechanical/normalize-name '  Alpha___Beta!!!  ')" = "alpha-beta"
set +e; output="$(bench-fixture/mechanical/normalize-name 2>&1)"; status=$?; set -e; test "$status" -eq 64 && test "$output" = "usage: normalize-name <name>"
set +e; output="$(bench-fixture/mechanical/normalize-name '---' 2>&1)"; status=$?; set -e; test "$status" -eq 1 && test "$output" = "name has no alphanumeric characters"
```

## Out of scope

- Unicode transliteration, reading stdin, accepting options, adding dependencies, or modifying
  any other file.
- Committing.
