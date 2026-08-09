<?php

namespace Bench\Fixture\Orders;

/**
 * An order is a list of lines plus a tax policy.
 *
 * Money flows in one direction only: subtotal() is the single source of truth for the pre-tax
 * figure, tax() is computed from it, and total() is their sum. Anything that changes the amount
 * a customer owes belongs in subtotal(), never duplicated into tax() or total().
 */
final class Order
{
    private string $reference;
    /** @var list<LineItem> */
    private array $lines = [];
    private TaxPolicy $taxPolicy;
    private string $currency;

    public function __construct(string $reference, TaxPolicy $taxPolicy, string $currency = 'EUR')
    {
        $this->reference = $reference;
        $this->taxPolicy = $taxPolicy;
        $this->currency = $currency;
    }

    public function reference(): string
    {
        return $this->reference;
    }

    public function currency(): string
    {
        return $this->currency;
    }

    public function addLine(LineItem $line): void
    {
        if ($line->unitPrice()->currency() !== $this->currency) {
            throw new \InvalidArgumentException('line currency does not match order currency');
        }
        $this->lines[] = $line;
    }

    /** @return list<LineItem> */
    public function lines(): array
    {
        return $this->lines;
    }

    public function lineCount(): int
    {
        return count($this->lines);
    }

    public function itemCount(): int
    {
        $count = 0;

        foreach ($this->lines as $line) {
            $count += $line->quantity();
        }

        return $count;
    }

    public function subtotal(): Money
    {
        $total = new Money(0, $this->currency);

        foreach ($this->lines as $line) {
            $total = $total->plus($line->lineTotal());
        }

        return $total;
    }

    public function tax(): Money
    {
        return $this->taxPolicy->taxFor($this->subtotal());
    }

    public function total(): Money
    {
        return $this->subtotal()->plus($this->tax());
    }

    public function taxLabel(): string
    {
        return $this->taxPolicy->label();
    }

    public function heaviestLine(): ?LineItem
    {
        $heaviest = null;

        foreach ($this->lines as $line) {
            if ($heaviest === null || $line->lineTotal()->amount() > $heaviest->lineTotal()->amount()) {
                $heaviest = $line;
            }
        }

        return $heaviest;
    }

    public function hasSku(string $sku): bool
    {
        foreach ($this->lines as $line) {
            if ($line->sku() === $sku) {
                return true;
            }
        }

        return false;
    }
}
