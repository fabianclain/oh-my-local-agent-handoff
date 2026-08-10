<?php

namespace Bench\Fixture\Billing;

/**
 * One subscription line on an invoice: a monthly fee, active for part of the billing period.
 */
final class Subscription
{
    public function __construct(
        private string $name,
        private Money $monthlyFee,
        private Period $active,
    ) {
    }

    public function name(): string
    {
        return $this->name;
    }

    public function monthlyFee(): Money
    {
        return $this->monthlyFee;
    }

    public function active(): Period
    {
        return $this->active;
    }

    /**
     * Days of this subscription that fall inside the billing period, on the half-open convention.
     */
    public function activeDaysWithin(Period $billing): int
    {
        $start = max($this->active->startDay(), $billing->startDay());
        $end = min($this->active->endDay(), $billing->endDay());

        return $end > $start ? $end - $start : 0;
    }
}
