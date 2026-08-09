<?php

namespace Bench\Fixture\Orders;

/**
 * In-memory order store, keyed by reference. Queries return copies of the internal list so a
 * caller cannot mutate the repository by holding on to a result.
 */
final class OrderRepository
{
    /** @var array<string, Order> */
    private array $orders = [];

    public function save(Order $order): void
    {
        $this->orders[$order->reference()] = $order;
    }

    public function has(string $reference): bool
    {
        return isset($this->orders[$reference]);
    }

    public function get(string $reference): Order
    {
        if (! isset($this->orders[$reference])) {
            throw new \OutOfBoundsException(sprintf('no order %s', $reference));
        }

        return $this->orders[$reference];
    }

    public function remove(string $reference): void
    {
        unset($this->orders[$reference]);
    }

    public function count(): int
    {
        return count($this->orders);
    }

    /** @return list<Order> */
    public function all(): array
    {
        return array_values($this->orders);
    }

    /** @return list<Order> */
    public function withSku(string $sku): array
    {
        return array_values(array_filter(
            $this->orders,
            static fn (Order $o): bool => $o->hasSku($sku)
        ));
    }

    public function totalOf(string $reference): Money
    {
        return $this->get($reference)->total();
    }

    /** @return list<string> */
    public function references(): array
    {
        $refs = array_keys($this->orders);
        sort($refs);

        return $refs;
    }
}
