<?php

namespace Bench\Fixture\Billing;

/**
 * An amount in minor units. Integer cents throughout — floats are not money.
 */
final class Money
{
    public function __construct(private int $cents)
    {
    }

    public function cents(): int
    {
        return $this->cents;
    }

    public function plus(Money $other): Money
    {
        return new Money($this->cents + $other->cents);
    }

    public function minus(Money $other): Money
    {
        return new Money($this->cents - $other->cents);
    }

    public function isZero(): bool
    {
        return $this->cents === 0;
    }

    public function format(): string
    {
        $sign = $this->cents < 0 ? '-' : '';
        $abs = abs($this->cents);

        return sprintf('%s%d.%02d', $sign, intdiv($abs, 100), $abs % 100);
    }
}
