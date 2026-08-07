# Integration fixture: conform to a shell interface

## Goal

Create a tiny formatting interface and a command that consumes it without duplicating its values.

## Context

This is a standalone fixture. Do not inspect or reuse application code from the repository.

Create `record-format.sh` with exactly two public functions:

```bash
record_prefix() { printf '%s' 'record'; }
record_separator() { printf '%s' '::'; }
```

Then implement `render-record`. It must locate and source the interface relative to its own file,
including when invoked from another working directory. It accepts exactly two positional
arguments, a key and a value, and prints this shape with a final newline:

```text
<record_prefix><record_separator><key>=<value>
```

Call both interface functions at runtime. Do not copy `record` or `::` into the command; the
verification temporarily changes the interface to prove the integration is live.

Use Bash only. Both files must pass Bash syntax validation, and the command must use
`set -euo pipefail` plus guard clauses.

## States to handle

- any argument count other than two: print `usage: render-record <key> <value>` to stderr and
  exit 64
- two arguments, including empty strings: render them according to the interface

## Files to touch

| Path | Action |
| --- | --- |
| `bench-fixture/integration/lib/record-format.sh` | create |
| `bench-fixture/integration/bin/render-record` | create, chmod +x |

## Acceptance criteria

- [ ] both files pass Bash syntax validation and the command is executable
- [ ] the command renders the default interface values
- [ ] the command locates the interface when called from a different working directory
- [ ] changing the interface functions changes the command output without editing the command
- [ ] an invalid argument count reports usage on stderr and exits 64

## Verification

```bash
bash -n bench-fixture/integration/lib/record-format.sh bench-fixture/integration/bin/render-record && test -x bench-fixture/integration/bin/render-record
test "$(bench-fixture/integration/bin/render-record color blue)" = "record::color=blue"
test "$(cd bench-fixture/integration && ./bin/render-record color blue)" = "record::color=blue"
( library=bench-fixture/integration/lib/record-format.sh; backup="$(mktemp)"; cp "$library" "$backup"; trap 'cp "$backup" "$library"; rm -f "$backup"' EXIT; printf '%s\n' "record_prefix() { printf '%s' 'changed'; }" "record_separator() { printf '%s' '--'; }" >"$library"; test "$(bench-fixture/integration/bin/render-record key value)" = "changed--key=value" )
set +e; output="$(bench-fixture/integration/bin/render-record only-one 2>&1)"; status=$?; set -e; test "$status" -eq 64 && test "$output" = "usage: render-record <key> <value>"
```

## Out of scope

- Additional interface functions, environment overrides, options, dependencies, or modifications
  outside the two listed files.
- Committing.
