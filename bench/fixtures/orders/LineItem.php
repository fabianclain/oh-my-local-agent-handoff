<?php

namespace Bench\Fixture\Orders;

/**
 * A single ordered product line. Quantity is always positive.
 */
final class LineItem
{
    private string $sku;
    private string $description;
    private int $quantity;
    private Money $unitPrice;

    public function __construct(string $sku, string $description, int $quantity, Money $unitPrice)
    {
        if ($quantity < 1) {
            throw new \InvalidArgumentException('quantity must be at least 1');
        }
        $this->sku = $sku;
        $this->description = $description;
        $this->quantity = $quantity;
        $this->unitPrice = $unitPrice;
    }

    public function sku(): string
    {
        return $this->sku;
    }

    public function description(): string
    {
        return $this->description;
    }

    public function quantity(): int
    {
        return $this->quantity;
    }

    public function unitPrice(): Money
    {
        return $this->unitPrice;
    }

    public function lineTotal(): Money
    {
        return $this->unitPrice->times($this->quantity);
    }

    public function describe(): string
    {
        return sprintf('%s x%d @ %s', $this->sku, $this->quantity, $this->unitPrice->format());
    }
}
