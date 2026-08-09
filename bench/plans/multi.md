# Add a promotion to the orders domain

## What to do

All paths are under `bench/fixtures/orders/`.

**1. Create `PromotionPolicy.php`** — namespace `Bench\Fixture\Orders`:

- `interface PromotionPolicy` with two methods: `discountFor(Money $subtotal): Money` and `label(): string`.
- `final class TierPromotion implements PromotionPolicy`. Constructor takes `float $rate`.
  `discountFor()` returns `$subtotal->percentage($rate)`. `label()` returns e.g. `10.0% off` for `0.10`.
- `final class NoPromotion implements PromotionPolicy`. `discountFor()` returns zero money in the
  subtotal's currency. `label()` returns `none`.

**2. Edit `Order.php`** — add a 4th constructor parameter `?PromotionPolicy $promotion = null`.
Store it, defaulting to `new NoPromotion()`. Then add three methods and change one:

- `promotion(): Money` — returns `$this->promotion->discountFor($this->subtotal())`.
- `promotionLabel(): string` — returns the policy's label.
- `taxableBase(): Money` — returns `subtotal()` minus `promotion()`.
- `tax()` — change it to use `taxableBase()` instead of `subtotal()`.

Leave `subtotal()` exactly as it is. `total()` already returns `subtotal() + tax()`; change it to
return `taxableBase() + tax()`.

**3. Edit `OrderReport.php`** — in `summaryRows()`, insert one row between the subtotal row and
the tax row: `sprintf('Promotion (%s): %s', $this->order->promotionLabel(), $this->order->promotion()->format())`.

**4. Edit `Invoice.php`** — in `chargeLines()`, insert one row before the `Goods:` row:
`sprintf('Promotion: %s', $this->order->promotion()->format())`.

## Do not change

`Money.php`, `LineItem.php`, `Catalog.php`, `TaxPolicy.php`, `Address.php`, `Customer.php`,
`ShippingPolicy.php`, `AuditLog.php`, `InvoiceNumber.php`, `PricingRules.php`,
`OrderRepository.php`.

## The one trap

Tax must be charged on `taxableBase()`, not on `subtotal()`.

On a 100.00 order with a 10% promotion and 20% tax:

- correct: promotion 10.00, tax 18.00, total 108.00
- wrong: tax 20.00, total 110.00

Both parse. Only the numbers tell you which you wrote.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/orders/PromotionPolicy.php` | create |
| `bench/fixtures/orders/Order.php` | modify |
| `bench/fixtures/orders/OrderReport.php` | modify |
| `bench/fixtures/orders/Invoice.php` | modify |

Four files. One created, three modified. Nothing else.

## Acceptance criteria

- [ ] Every file in the orders fixture parses
- [ ] With no promotion, a 100.00 order at 20% tax still totals 120.00
- [ ] `TierPromotion(0.10)` on a 100.00 subtotal gives a 10.00 promotion
- [ ] Tax is 18.00, not 20.00
- [ ] `total()` is 108.00
- [ ] `OrderReport::summaryRows()` returns 4 rows: subtotal, promotion, tax, total
- [ ] `Invoice::chargeLines()` returns 4 rows, the first mentioning `Promotion`
- [ ] The eleven untouched files are byte-identical
- [ ] Exactly four files created or modified

## Verification

```bash
for f in bench/fixtures/orders/*.php; do php -l "$f" >/dev/null || exit 1; done
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("A", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->total()->amount()===12000 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("B", new Bench\Fixture\Orders\FlatRateTax(0.20), "EUR", new Bench\Fixture\Orders\TierPromotion(0.10)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->promotion()->amount()===1000 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("C", new Bench\Fixture\Orders\FlatRateTax(0.20), "EUR", new Bench\Fixture\Orders\TierPromotion(0.10)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->tax()->amount()===1800 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("D", new Bench\Fixture\Orders\FlatRateTax(0.20), "EUR", new Bench\Fixture\Orders\TierPromotion(0.10)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->total()->amount()===10800 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $o=new Bench\Fixture\Orders\Order("E", new Bench\Fixture\Orders\FlatRateTax(0.20), "EUR", new Bench\Fixture\Orders\TierPromotion(0.10)); $o->addLine($c->makeLine("W",2)); $r=(new Bench\Fixture\Orders\OrderReport($o))->summaryRows(); exit((count($r)===4 && str_contains($r[0],"Subtotal") && str_contains($r[1],"Promotion") && str_contains($r[2],"Tax") && str_contains($r[3],"Total")) ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $a=new Bench\Fixture\Orders\Address("1 St","Town","1000","RO"); $cu=new Bench\Fixture\Orders\Customer("C1","Ann","standard",$a); $o=new Bench\Fixture\Orders\Order("F", new Bench\Fixture\Orders\FlatRateTax(0.20), "EUR", new Bench\Fixture\Orders\TierPromotion(0.10)); $o->addLine($c->makeLine("W",2)); $i=new Bench\Fixture\Orders\Invoice(new Bench\Fixture\Orders\InvoiceNumber(2026,1), $o, $cu, new Bench\Fixture\Orders\FreeShipping()); $l=$i->chargeLines(); exit((count($l)===4 && str_contains($l[0],"Promotion")) ? 0 : 1);'
git diff --quiet HEAD -- bench/fixtures/orders/Money.php bench/fixtures/orders/LineItem.php bench/fixtures/orders/Catalog.php bench/fixtures/orders/TaxPolicy.php bench/fixtures/orders/Address.php bench/fixtures/orders/Customer.php bench/fixtures/orders/ShippingPolicy.php bench/fixtures/orders/AuditLog.php bench/fixtures/orders/InvoiceNumber.php bench/fixtures/orders/PricingRules.php bench/fixtures/orders/OrderRepository.php
test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq 4
```

## Out of scope

Tests, other directories, refactoring, committing.
