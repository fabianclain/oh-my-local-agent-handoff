<?php

namespace Bench\Fixture\Billing;

/**
 * An invoice over one billing period.
 */
final class Invoice
{
    /** @var list<Subscription> */
    private array $lines = [];

    public function __construct(private Period $billing)
    {
    }

    public function addLine(Subscription $line): void
    {
        $this->lines[] = $line;
    }

    /** @return list<Subscription> */
    public function lines(): array
    {
        return $this->lines;
    }

    public function billing(): Period
    {
        return $this->billing;
    }
}
