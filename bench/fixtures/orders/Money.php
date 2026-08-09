<?php

namespace Bench\Fixture\Orders;

/**
 * Minor-unit money value object. Immutable: every operation returns a new instance.
 */
final class Money
{
    private int $amount;
    private string $currency;

    public function __construct(int $amount, string $currency = 'EUR')
    {
        if ($currency === '') {
            throw new \InvalidArgumentException('currency must not be empty');
        }
        $this->amount = $amount;
        $this->currency = $currency;
    }

    public static function fromFloat(float $units, string $currency = 'EUR'): self
    {
        return new self((int) round($units * 100), $currency);
    }

    public function amount(): int
    {
        return $this->amount;
    }

    public function currency(): string
    {
        return $this->currency;
    }

    public function toFloat(): float
    {
        return $this->amount / 100;
    }

    public function plus(self $other): self
    {
        $this->assertSameCurrency($other);

        return new self($this->amount + $other->amount, $this->currency);
    }

    public function minus(self $other): self
    {
        $this->assertSameCurrency($other);

        return new self($this->amount - $other->amount, $this->currency);
    }

    public function times(int $factor): self
    {
        return new self($this->amount * $factor, $this->currency);
    }

    public function percentage(float $rate): self
    {
        return new self((int) round($this->amount * $rate), $this->currency);
    }

    public function isZero(): bool
    {
        return $this->amount === 0;
    }

    public function equals(self $other): bool
    {
        return $this->amount === $other->amount && $this->currency === $other->currency;
    }

    public function format(): string
    {
        return sprintf('%s %.2f', $this->currency, $this->toFloat());
    }

    private function assertSameCurrency(self $other): void
    {
        if ($other->currency !== $this->currency) {
            throw new \InvalidArgumentException('currency mismatch');
        }
    }
}
