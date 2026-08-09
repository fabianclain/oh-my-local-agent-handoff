# Add currency conversion across the orders domain

## What to do

All paths are under `bench/fixtures/orders/`. One new file, five edited.

**1. Create `ExchangeRate.php`** — namespace `Bench\Fixture\Orders`:

- `final class ExchangeRate`.
- `add(string $from, string $to, float $rate): void` stores a rate.
- `rateFor(string $from, string $to): float` returns it. Returns `1.0` when `$from === $to`.
  Throws `\OutOfBoundsException` if the pair is unknown.
- `has(string $from, string $to): bool`.

**2. Edit `Money.php`** — add one method, change nothing else:

- `convertTo(string $currency, ExchangeRate $rates): Money` — returns a new `Money` whose amount is
  `(int) round($this->amount * $rates->rateFor($this->currency, $currency))`, in `$currency`.

**3. Edit `Order.php`** — add two methods:

- `subtotalIn(string $currency, ExchangeRate $rates): Money` — `subtotal()` converted.
- `totalIn(string $currency, ExchangeRate $rates): Money` — `total()` converted.

Convert the finished figure once. Do not convert the individual lines and re-sum them.

**4. Edit `Invoice.php`** — add one method:

- `grandTotalIn(string $currency, ExchangeRate $rates): Money` — `grandTotal()` converted.

**5. Edit `OrderReport.php`** — add one method:

- `summaryIn(string $currency, ExchangeRate $rates): string` — returns
  `sprintf('Total: %s', $this->order->totalIn($currency, $rates)->format())`.

**6. Edit `PricingRules.php`** — add one method:

- `displayCurrencyFor(Customer $customer): string` — returns `'EUR'` when the customer's billing
  address is domestic to `homeCountry()`, otherwise `'USD'`.

## Do not change

`LineItem.php`, `Catalog.php`, `TaxPolicy.php`, `Address.php`, `Customer.php`,
`ShippingPolicy.php`, `AuditLog.php`, `InvoiceNumber.php`, `OrderRepository.php`.

## The traps

- **Convert once.** Converting each line and re-summing rounds every line separately and drifts.
  Convert the finished total.
- **Do not change existing behaviour.** Every existing method keeps its current signature and
  result. `Money` is used by everything; a change there breaks the whole domain quietly.

On a 100.00 EUR order at 20% tax with EUR→USD of 1.10: total is 120.00 EUR and 132.00 USD.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/orders/ExchangeRate.php` | create |
| `bench/fixtures/orders/Money.php` | modify |
| `bench/fixtures/orders/Order.php` | modify |
| `bench/fixtures/orders/Invoice.php` | modify |
| `bench/fixtures/orders/OrderReport.php` | modify |
| `bench/fixtures/orders/PricingRules.php` | modify |

Six files. One created, five modified. Nothing else.

## Acceptance criteria

- [ ] Every file in the orders fixture parses
- [ ] `rateFor` returns 1.0 for a same-currency pair and throws for an unknown one
- [ ] `Money::convertTo` turns 100.00 EUR into 110.00 USD at rate 1.10
- [ ] Existing behaviour is unchanged: a 100.00 EUR order at 20% tax still totals 120.00 EUR
- [ ] `Order::totalIn('USD', ...)` returns 132.00
- [ ] `Order::subtotalIn('USD', ...)` returns 110.00
- [ ] `Invoice::grandTotalIn` converts the grand total including shipping
- [ ] `OrderReport::summaryIn` renders the converted total
- [ ] `PricingRules::displayCurrencyFor` returns EUR domestic, USD foreign
- [ ] The nine untouched files are byte-identical
- [ ] Exactly six files created or modified

## Verification

```bash
for f in bench/fixtures/orders/*.php; do php -l "$f" >/dev/null || exit 1; done
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); if (abs($r->rateFor("EUR","EUR")-1.0)>0.0001) exit(1); try { $r->rateFor("EUR","GBP"); exit(1); } catch (\OutOfBoundsException $e) { exit(0); }'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); $m=new Bench\Fixture\Orders\Money(10000,"EUR"); $c=$m->convertTo("USD",$r); exit(($c->amount()===11000 && $c->currency()==="USD") ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("A", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->total()->amount()===12000 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("B", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->totalIn("USD",$r)->amount()===13200 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $c->add("G","G",1000); $o=new Bench\Fixture\Orders\Order("C", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $o->addLine($c->makeLine("G",5)); exit($o->subtotalIn("USD",$r)->amount()===11000 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $a=new Bench\Fixture\Orders\Address("1 St","Town","1000","RO"); $cu=new Bench\Fixture\Orders\Customer("C1","Ann","standard",$a); $o=new Bench\Fixture\Orders\Order("D", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $i=new Bench\Fixture\Orders\Invoice(new Bench\Fixture\Orders\InvoiceNumber(2026,1), $o, $cu, new Bench\Fixture\Orders\FlatShipping(1000)); exit($i->grandTotalIn("USD",$r)->amount()===7700 ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $r=new Bench\Fixture\Orders\ExchangeRate(); $r->add("EUR","USD",1.10); $c=new Bench\Fixture\Orders\Catalog(); $c->add("W","W",2500); $o=new Bench\Fixture\Orders\Order("E", new Bench\Fixture\Orders\FlatRateTax(0.20)); $o->addLine($c->makeLine("W",2)); $s=(new Bench\Fixture\Orders\OrderReport($o))->summaryIn("USD",$r); exit((str_contains($s,"Total:") && str_contains($s,"USD")) ? 0 : 1);'
php -r 'foreach (glob("bench/fixtures/orders/*.php") as $f) { require_once $f; } $p=new Bench\Fixture\Orders\PricingRules("RO"); $home=new Bench\Fixture\Orders\Address("1 St","Town","1000","RO"); $away=new Bench\Fixture\Orders\Address("2 Ave","City","2000","US"); $a=new Bench\Fixture\Orders\Customer("C1","Ann","standard",$home); $b=new Bench\Fixture\Orders\Customer("C2","Bob","standard",$away); exit(($p->displayCurrencyFor($a)==="EUR" && $p->displayCurrencyFor($b)==="USD") ? 0 : 1);'
git diff --quiet HEAD -- bench/fixtures/orders/LineItem.php bench/fixtures/orders/Catalog.php bench/fixtures/orders/TaxPolicy.php bench/fixtures/orders/Address.php bench/fixtures/orders/Customer.php bench/fixtures/orders/ShippingPolicy.php bench/fixtures/orders/AuditLog.php bench/fixtures/orders/InvoiceNumber.php bench/fixtures/orders/OrderRepository.php
test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq 6
```

## Out of scope

Tests, other directories, refactoring, committing.
