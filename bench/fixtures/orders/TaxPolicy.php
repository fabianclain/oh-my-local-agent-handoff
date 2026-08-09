<?php

namespace Bench\Fixture\Orders;

/**
 * How much tax an order owes. Implementations must be pure: same input, same output.
 */
interface TaxPolicy
{
    public function taxFor(Money $taxableBase): Money;

    public function label(): string;
}

/**
 * A single flat rate applied to the whole taxable base.
 */
final class FlatRateTax implements TaxPolicy
{
    private float $rate;

    public function __construct(float $rate)
    {
        if ($rate < 0.0 || $rate > 1.0) {
            throw new \InvalidArgumentException('rate must be between 0 and 1');
        }
        $this->rate = $rate;
    }

    public function taxFor(Money $taxableBase): Money
    {
        return $taxableBase->percentage($this->rate);
    }

    public function label(): string
    {
        return sprintf('flat %.1f%%', $this->rate * 100);
    }
}

/**
 * No tax at all. Useful for exempt customers and for tests.
 */
final class ZeroTax implements TaxPolicy
{
    public function taxFor(Money $taxableBase): Money
    {
        return new Money(0, $taxableBase->currency());
    }

    public function label(): string
    {
        return 'exempt';
    }
}
