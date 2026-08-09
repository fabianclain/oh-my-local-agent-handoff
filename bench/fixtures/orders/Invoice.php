<?php

namespace Bench\Fixture\Orders;

/**
 * A billing document derived from an order.
 *
 * The invoice never recomputes money. Every figure is asked of the Order, so an invoice cannot
 * disagree with the order it was raised from — if a new charge or deduction is added to Order,
 * it must be surfaced here too or the document silently understates what happened.
 */
final class Invoice
{
    private InvoiceNumber $number;
    private Order $order;
    private Customer $customer;
    private ShippingPolicy $shipping;

    public function __construct(InvoiceNumber $number, Order $order, Customer $customer, ShippingPolicy $shipping)
    {
        $this->number = $number;
        $this->order = $order;
        $this->customer = $customer;
        $this->shipping = $shipping;
    }

    public function number(): InvoiceNumber
    {
        return $this->number;
    }

    public function order(): Order
    {
        return $this->order;
    }

    public function customer(): Customer
    {
        return $this->customer;
    }

    public function shippingCost(): Money
    {
        return $this->shipping->costFor(
            $this->order->itemCount(),
            $this->customer->shippingAddress(),
            $this->order->currency()
        );
    }

    public function goodsTotal(): Money
    {
        return $this->order->total();
    }

    public function grandTotal(): Money
    {
        return $this->goodsTotal()->plus($this->shippingCost());
    }

    /** @return list<string> */
    public function chargeLines(): array
    {
        return [
            sprintf('Goods: %s', $this->goodsTotal()->format()),
            sprintf('Shipping (%s): %s', $this->shipping->label(), $this->shippingCost()->format()),
            sprintf('Grand total: %s', $this->grandTotal()->format()),
        ];
    }

    public function render(): string
    {
        $parts = [
            sprintf('Invoice %s', $this->number->toString()),
            $this->customer->describe(),
            $this->customer->shippingAddress()->oneLine(),
            '',
        ];

        foreach ($this->chargeLines() as $line) {
            $parts[] = $line;
        }

        return implode("\n", $parts);
    }
}
