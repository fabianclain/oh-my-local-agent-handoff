<?php

namespace Bench\Fixture\Orders;

/**
 * Invoice numbering: a per-year sequence rendered as INV-<year>-<padded sequence>.
 */
final class InvoiceNumber
{
    private int $year;
    private int $sequence;

    public function __construct(int $year, int $sequence)
    {
        if ($year < 2000 || $year > 2999) {
            throw new \InvalidArgumentException('year out of range');
        }
        if ($sequence < 1) {
            throw new \InvalidArgumentException('sequence must be positive');
        }
        $this->year = $year;
        $this->sequence = $sequence;
    }

    public static function parse(string $value): self
    {
        if (preg_match('/^INV-(\d{4})-(\d{5})$/', $value, $m) !== 1) {
            throw new \InvalidArgumentException(sprintf('malformed invoice number %s', $value));
        }

        return new self((int) $m[1], (int) $m[2]);
    }

    public function year(): int
    {
        return $this->year;
    }

    public function sequence(): int
    {
        return $this->sequence;
    }

    public function next(): self
    {
        return new self($this->year, $this->sequence + 1);
    }

    public function toString(): string
    {
        return sprintf('INV-%04d-%05d', $this->year, $this->sequence);
    }

    public function equals(self $other): bool
    {
        return $this->year === $other->year && $this->sequence === $other->sequence;
    }
}
