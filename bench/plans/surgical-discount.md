# Add a discount to the invoice subtotal

## Goal

One contained change to one existing file.

## The change

In `bench/fixtures/surgical/InvoiceTotals.php`:

1. Add a private property `$discountRate` of type `float`, defaulting to `0.0`.
2. Add a public method `setDiscountRate(float $rate): void` that assigns it.
3. Change `subtotal()` so the returned value has the discount applied:
   `subtotal = sum(quantity * unit_price) * (1 - discountRate)`.

Nothing else changes. `tax()` and `total()` already build on `subtotal()` and must keep working
through it — do not duplicate the discount into them, or it will be applied twice.

## This is a surgical edit

**Modify the existing file in place. Do not rewrite it.**

Every other method — `addLine`, `lineCount`, `tax`, `total`, `heaviestLine`, `describe` — must
survive **byte-identical**. The docblock at the top stays. The file should grow by roughly ten
lines, not be replaced by a new version that happens to contain similar code.

A round that reproduces the file from scratch fails even if the result is correct, because the
thing being measured is whether a contained change can be made without regenerating everything
around it.

## Output discipline

- One implementation. No earlier attempt left beside a later one.
- No commentary about your own process in the code.
- Write real newlines, not the characters `\` and `n`.
- Run `php -l bench/fixtures/surgical/InvoiceTotals.php` and confirm it parses.
- Never report a command as passing unless you ran it and saw it pass.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/surgical/InvoiceTotals.php` | modify |

Exactly one file. Creating any file fails this round.

## Acceptance criteria

- [ ] The file parses
- [ ] `setDiscountRate(0.10)` then `subtotal()` on lines 2x10.00 and 1x5.00 returns 22.50
- [ ] With no discount set, `subtotal()` on those lines still returns 25.00
- [ ] `total(0.2)` with a 0.10 discount returns 27.00 — the discount is applied once, via subtotal
- [ ] `heaviestLine()` and `describe()` still behave as before
- [ ] Exactly one file changed, none created

## Verification

```bash
php -l bench/fixtures/surgical/InvoiceTotals.php
php -r 'require "bench/fixtures/surgical/InvoiceTotals.php"; $i=new Bench\Fixture\InvoiceTotals; $i->addLine("a",2,10.0); $i->addLine("b",1,5.0); $i->setDiscountRate(0.10); if (abs($i->subtotal()-22.5)>0.001) exit(1); if (abs($i->total(0.2)-27.0)>0.001) exit(1); echo "ok";'
```

## Out of scope

Tests, other files, refactoring anything not named above, committing.
