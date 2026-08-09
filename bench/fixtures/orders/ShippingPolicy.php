<?php

namespace Bench\Fixture\Orders;

/**
 * What shipping costs. Implementations see the order's item count and taxable weight class only;
 * they must not reach into pricing.
 */
interface ShippingPolicy
{
    public function costFor(int $itemCount, Address $destination, string $currency): Money;

    public function label(): string;
}

/**
 * One flat fee regardless of destination.
 */
final class FlatShipping implements ShippingPolicy
{
    private int $feeMinorUnits;

    public function __construct(int $feeMinorUnits)
    {
        if ($feeMinorUnits < 0) {
            throw new \InvalidArgumentException('fee must not be negative');
        }
        $this->feeMinorUnits = $feeMinorUnits;
    }

    public function costFor(int $itemCount, Address $destination, string $currency): Money
    {
        return new Money($this->feeMinorUnits, $currency);
    }

    public function label(): string
    {
        return 'flat shipping';
    }
}

/**
 * A per-item fee with a surcharge for anything leaving the home country.
 */
final class PerItemShipping implements ShippingPolicy
{
    private int $perItem;
    private int $internationalSurcharge;
    private string $homeCountry;

    public function __construct(int $perItem, int $internationalSurcharge, string $homeCountry)
    {
        $this->perItem = $perItem;
        $this->internationalSurcharge = $internationalSurcharge;
        $this->homeCountry = strtoupper($homeCountry);
    }

    public function costFor(int $itemCount, Address $destination, string $currency): Money
    {
        $cost = new Money($this->perItem * $itemCount, $currency);

        if (! $destination->isDomestic($this->homeCountry)) {
            $cost = $cost->plus(new Money($this->internationalSurcharge, $currency));
        }

        return $cost;
    }

    public function label(): string
    {
        return sprintf('per-item from %s', $this->homeCountry);
    }
}

/**
 * Free shipping. Kept as its own policy so "free" is an explicit decision, not a zero fee.
 */
final class FreeShipping implements ShippingPolicy
{
    public function costFor(int $itemCount, Address $destination, string $currency): Money
    {
        return new Money(0, $currency);
    }

    public function label(): string
    {
        return 'free shipping';
    }
}
