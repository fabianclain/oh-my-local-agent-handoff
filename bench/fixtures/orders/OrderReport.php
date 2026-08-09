<?php

namespace Bench\Fixture\Orders;

/**
 * Renders an order as plain text. Presentation only — it must never recompute money itself,
 * always asking the Order for figures so the two cannot disagree.
 */
final class OrderReport
{
    private Order $order;

    public function __construct(Order $order)
    {
        $this->order = $order;
    }

    public function header(): string
    {
        return sprintf('Order %s (%s)', $this->order->reference(), $this->order->currency());
    }

    /** @return list<string> */
    public function lineRows(): array
    {
        $rows = [];

        foreach ($this->order->lines() as $line) {
            $rows[] = sprintf('%-8s %-24s %s', $line->sku(), $line->description(), $line->lineTotal()->format());
        }

        return $rows;
    }

    /** @return list<string> */
    public function summaryRows(): array
    {
        return [
            sprintf('Subtotal: %s', $this->order->subtotal()->format()),
            sprintf('Tax (%s): %s', $this->order->taxLabel(), $this->order->tax()->format()),
            sprintf('Total: %s', $this->order->total()->format()),
        ];
    }

    public function render(): string
    {
        $parts = [$this->header(), ''];

        foreach ($this->lineRows() as $row) {
            $parts[] = $row;
        }

        $parts[] = '';

        foreach ($this->summaryRows() as $row) {
            $parts[] = $row;
        }

        return implode("\n", $parts);
    }

    public function shortSummary(): string
    {
        return sprintf('%s: %d item(s), %s',
            $this->order->reference(), $this->order->itemCount(), $this->order->total()->format());
    }
}
