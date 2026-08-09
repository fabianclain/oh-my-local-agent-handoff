<?php

namespace Bench\Fixture;

/**
 * Aggregates invoice lines. Deliberately ordinary code: the benchmark measures whether a model
 * can make a small, contained change here without regenerating the file.
 */
class InvoiceTotals
{
    /** @var array<int, array{description: string, quantity: int, unit_price: float}> */
    private array $lines = [];

    public function addLine(string $description, int $quantity, float $unitPrice): void
    {
        $this->lines[] = [
            'description' => $description,
            'quantity' => $quantity,
            'unit_price' => $unitPrice,
        ];
    }

    public function lineCount(): int
    {
        return count($this->lines);
    }

    public function subtotal(): float
    {
        $total = 0.0;

        foreach ($this->lines as $line) {
            $total += $line['quantity'] * $line['unit_price'];
        }

        return $total;
    }

    public function tax(float $rate): float
    {
        return $this->subtotal() * $rate;
    }

    public function total(float $rate): float
    {
        return $this->subtotal() + $this->tax($rate);
    }

    public function heaviestLine(): ?string
    {
        $best = null;
        $bestValue = -1.0;

        foreach ($this->lines as $line) {
            $value = $line['quantity'] * $line['unit_price'];

            if ($value > $bestValue) {
                $bestValue = $value;
                $best = $line['description'];
            }
        }

        return $best;
    }

    public function describe(): string
    {
        return sprintf('%d line(s), subtotal %.2f', $this->lineCount(), $this->subtotal());
    }
}
