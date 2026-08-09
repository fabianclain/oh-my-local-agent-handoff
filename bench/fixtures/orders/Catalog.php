<?php

namespace Bench\Fixture\Orders;

/**
 * In-memory product catalog. Prices are stored in minor units.
 */
final class Catalog
{
    /** @var array<string, array{description: string, price: int}> */
    private array $products = [];

    public function add(string $sku, string $description, int $priceMinorUnits): void
    {
        if (isset($this->products[$sku])) {
            throw new \InvalidArgumentException(sprintf('duplicate sku %s', $sku));
        }
        $this->products[$sku] = ['description' => $description, 'price' => $priceMinorUnits];
    }

    public function has(string $sku): bool
    {
        return isset($this->products[$sku]);
    }

    public function priceOf(string $sku): Money
    {
        $this->assertKnown($sku);

        return new Money($this->products[$sku]['price']);
    }

    public function descriptionOf(string $sku): string
    {
        $this->assertKnown($sku);

        return $this->products[$sku]['description'];
    }

    public function makeLine(string $sku, int $quantity): LineItem
    {
        $this->assertKnown($sku);

        return new LineItem($sku, $this->descriptionOf($sku), $quantity, $this->priceOf($sku));
    }

    public function skuCount(): int
    {
        return count($this->products);
    }

    /** @return list<string> */
    public function skus(): array
    {
        $skus = array_keys($this->products);
        sort($skus);

        return $skus;
    }

    private function assertKnown(string $sku): void
    {
        if (! isset($this->products[$sku])) {
            throw new \OutOfBoundsException(sprintf('unknown sku %s', $sku));
        }
    }
}
