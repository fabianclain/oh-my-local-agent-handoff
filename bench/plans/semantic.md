# Prorate an invoice without losing a cent

## Goal

Add proration to the billing fixture. The arithmetic is fully specified below — implement it
exactly as written. Do not choose your own rounding.

## Background

`bench/fixtures/billing/` has four classes: `Money` (integer cents), `Period` (a half-open day
range — the start day counts, the end day does not), `Subscription` (a monthly fee plus the period
it is active), and `Invoice` (a billing period plus subscription lines).

`Subscription::activeDaysWithin($billing)` already returns the days of a line that fall inside the
billing period. Use it.

## The change

### 1. Create `bench/fixtures/billing/Proration.php`

Namespace `Bench\Fixture\Billing`. One class:

```php
final class Proration
{
    public function __construct(private Invoice $invoice) {}

    public function subtotal(): Money;

    /** @return array<string, Money> keyed by line name, in the order the lines were added */
    public function allocation(): array;
}
```

Write out the real method bodies; the block above is the required shape, not the code.

### 2. How to compute them

Let `D` be `$invoice->billing()->days()`. For each line, let `f` be its monthly fee in cents and
`d` be `activeDaysWithin($invoice->billing())`. The line's **exact share** is the rational number
`f * d / D`.

**`subtotal()`** — add the exact shares together first, then round once, half up:

    subtotal = floor( (sum of f*d for every line) / D + 1/2 )

Compute it in integer arithmetic. Do not round the lines individually and add the results.

**`allocation()`** — largest remainder:

1. Each line provisionally gets `floor(f * d / D)` cents.
2. Add those floors up. The difference between `subtotal()` and that sum is the number of cents
   still to hand out. It is never negative.
3. Hand out one cent at a time to the lines with the largest remainder `(f * d) mod D`, largest
   first. If two lines have the same remainder, the one added to the invoice first wins.
4. Return every line, in the order it was added, including lines that get zero.

### 3. Modify `bench/fixtures/billing/Invoice.php`

Add one method, and change nothing else:

```php
public function proration(): Proration
```

It returns a `Proration` for this invoice.

## Why this matters, in one sentence

Rounding each line and adding the results is the obvious implementation, and it is wrong: three
lines of `1000 * 10 / 30` each round to 333 and sum to 999 against a true total of 1000.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/billing/Proration.php` | create |
| `bench/fixtures/billing/Invoice.php` | modify |

Two files. Changing any other file fails this round.

## Acceptance criteria

- [ ] Every file in `bench/fixtures/billing/` parses
- [ ] Three lines of 1000 cents, each active 10 days of a 30-day period: `subtotal()` is 1000
- [ ] The same case: `allocation()` is `[334, 333, 333]` in line order
- [ ] The same case: the allocation sums to exactly `subtotal()`
- [ ] Two lines of 999 cents, each active 15 days of 30: `subtotal()` is 999 and the allocation is
      `[500, 499]`
- [ ] A line active zero days in the period appears in the allocation with 0 cents
- [ ] `Invoice::proration()` returns a `Proration`, and the existing `Invoice` methods still work
- [ ] Exactly two files changed: one created, one modified

## Verification

```bash
for f in bench/fixtures/billing/*.php; do php -l "$f" >/dev/null || exit 1; done
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); foreach (["a","b","c"] as $n) { $i->addLine(new B\Subscription($n, new B\Money(1000), new B\Period(0,10))); } exit($i->proration()->subtotal()->cents()===1000 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); foreach (["a","b","c"] as $n) { $i->addLine(new B\Subscription($n, new B\Money(1000), new B\Period(0,10))); } $a=array_map(fn($m)=>$m->cents(), $i->proration()->allocation()); exit(array_values($a)===[334,333,333] && array_keys($a)===["a","b","c"] ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); foreach (["a","b","c"] as $n) { $i->addLine(new B\Subscription($n, new B\Money(1000), new B\Period(0,10))); } $pr=$i->proration(); $sum=0; foreach ($pr->allocation() as $m) { $sum += $m->cents(); } exit($sum===$pr->subtotal()->cents() ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); foreach (["x","y"] as $n) { $i->addLine(new B\Subscription($n, new B\Money(999), new B\Period(0,15))); } $pr=$i->proration(); $a=array_map(fn($m)=>$m->cents(), $pr->allocation()); exit($pr->subtotal()->cents()===999 && array_values($a)===[500,499] ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); $i->addLine(new B\Subscription("live", new B\Money(3000), new B\Period(0,30))); $i->addLine(new B\Subscription("gone", new B\Money(3000), new B\Period(40,50))); $a=array_map(fn($m)=>$m->cents(), $i->proration()->allocation()); exit((count($a)===2 && $a["gone"]===0 && $a["live"]===3000) ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/billing/*.php") as $f) { require_once $f; } use Bench\Fixture\Billing as B; $p=new B\Period(0,30); $i=new B\Invoice($p); $s=new B\Subscription("a", new B\Money(1000), new B\Period(0,10)); $i->addLine($s); exit(($i->proration() instanceof B\Proration && count($i->lines())===1 && $i->billing()->days()===30) ? 0 : 1);'
test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq 2
```

## Out of scope

Tests, other fixtures, refactoring anything not named above, committing.
