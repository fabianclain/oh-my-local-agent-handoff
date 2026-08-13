# Add three posting methods to the ledger

## What to do

Edit one existing file, `bench/fixtures/ledger/Ledger.php`. Create nothing.

It already has six posting methods — `postDebit`, `postCredit`, `postAdjustment`, `postFee`,
`postRefund`, `postInterest` — which are deliberately near-identical: same docblock shape, same
guard, same append, same return. Read the file before editing it, and anchor each insertion on the
**docblock** of the method you are told to follow, not on the method name alone.

Add three methods. Each takes `(string $memo, int $minor)`, returns the running balance as `int`,
throws `\InvalidArgumentException` when `$minor` is not positive, appends one entry to
`$this->entries` with the given `kind`, and adjusts `$this->balance`.

| Method | Insert immediately after | `kind` | Effect on the balance |
| --- | --- | --- | --- |
| `postBonus` | the whole of `postCredit` | `bonus` | adds |
| `postChargeback` | the whole of `postRefund` | `chargeback` | subtracts |
| `postWriteOff` | the whole of `postInterest` | `writeoff` | subtracts |

Each new method gets a docblock in the same shape as the ones around it: a one-line summary, then
`@param`, `@return` and `@throws`.

**"Immediately after the whole of X" means after X's closing brace** — not between X's docblock and
X itself. A method inserted there compiles, passes `php -l`, and leaves X's docblock describing
your new method instead of X.

## Do not change

Every existing method's body, signature and docblock, byte for byte. The constructor, the
properties, `currency()`, `balance()`, `entries()`, `count()`, `totalOf()` and `summary()`. Every
file outside `bench/fixtures/ledger/`.

## The traps

- **Six near-identical methods.** `postFee` and `postRefund` differ by one character in the guard
  message and one in the operator. An edit anchored on `$this->balance += $minor;` has six
  candidates, and five of them are wrong.
- **A stolen docblock parses.** Inserting between a docblock and its method is valid PHP and a
  clean `php -l`. It is checked here against the base, and it is the failure this fixture exists
  for.
- **Editing the same file three times.** After the first insertion every line below it has moved.
  Anchors read once and used three times are stale by the second edit.
- **The subtracting methods subtract.** `postChargeback` and `postWriteOff` reduce the balance;
  `postBonus` increases it. Copying the nearest method wholesale gets one of the three wrong.

## States to handle

- **A non-positive amount.** Zero and negative both throw `\InvalidArgumentException`, before any
  entry is appended and before the balance moves. A guard that appends first and throws second
  leaves the ledger dirty and still passes a test that only checks the exception.
- **The balance going negative.** Permitted. A chargeback against an empty ledger returns a
  negative balance rather than throwing.
- **An empty memo.** Permitted and stored as given. Do not validate it.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/ledger/Ledger.php` | modify |

One file. Modified, not created. Nothing else.

## Acceptance criteria

- [ ] The file parses and declares all three new methods
- [ ] `postBonus` adds and returns the running balance
- [ ] `postChargeback` subtracts
- [ ] `postWriteOff` subtracts
- [ ] All three throw on a non-positive amount, leaving the ledger untouched
- [ ] Each new method records its own `kind` and stores the memo as given, empty included
- [ ] Every docblock still sits on the declaration it sat on before
- [ ] The change is confined to three insertion points
- [ ] No more than 70 lines are added
- [ ] Existing behaviour is unchanged, and exactly one file is modified

## Verification

```bash
php -l bench/fixtures/ledger/Ledger.php >/dev/null && php -r 'require "bench/fixtures/ledger/Ledger.php"; $r=new ReflectionClass("Bench\\Fixture\\Ledger\\Ledger"); exit(($r->hasMethod("postBonus") && $r->hasMethod("postChargeback") && $r->hasMethod("postWriteOff")) ? 0 : 1);'
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); exit($l->postBonus("m",500)===500 && $l->balance()===500 ? 0 : 1);'
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); $l->postCredit("m",1000); exit($l->postChargeback("m",250)===750 ? 0 : 1);'
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); $l->postCredit("m",1000); exit($l->postWriteOff("m",400)===600 ? 0 : 1);'
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); $n=0; foreach (["postBonus","postChargeback","postWriteOff"] as $m) { try { $l->$m("m",0); } catch (\InvalidArgumentException $e) { $n++; } } exit(($n===3 && $l->count()===0 && $l->balance()===0) ? 0 : 1);'
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); $l->postBonus("",100); $l->postChargeback("m",50); $l->postWriteOff("m",25); $e=$l->entries(); exit(($l->totalOf("bonus")===100 && $l->totalOf("chargeback")===50 && $l->totalOf("writeoff")===25 && $e[0]["memo"]==="" && $e[0]["kind"]==="bonus") ? 0 : 1);'
tools/docblock-anchor --base HEAD bench/fixtures/ledger/Ledger.php
tools/patch-shape HEAD bench/fixtures/ledger/Ledger.php --max-hunks 3
tools/patch-shape HEAD bench/fixtures/ledger/Ledger.php --max-added 70
php -r 'require "bench/fixtures/ledger/Ledger.php"; $l=new Bench\Fixture\Ledger\Ledger("EUR"); $l->postDebit("m",300); $l->postCredit("m",1000); exit(($l->balance()===700 && $l->count()===2 && $l->summary()==="EUR ledger: 2 entries, balance 700") ? 0 : 1);' && test "$(git status --porcelain --untracked-files=all -- . ':(exclude).handoff' ':(exclude).omc' ':(exclude)vendor' ':(exclude)node_modules' | wc -l)" -eq 1
```

## Out of scope

New files, tests, other fixtures, refactoring the existing methods, committing, and any file
outside `bench/fixtures/ledger/`.
