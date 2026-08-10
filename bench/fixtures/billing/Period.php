<?php

namespace Bench\Fixture\Billing;

/**
 * A half-open date range: the start day counts, the end day does not.
 *
 * Stored as day numbers rather than dates so the fixture has no timezone behaviour to argue about.
 */
final class Period
{
    public function __construct(private int $startDay, private int $endDay)
    {
        if ($endDay < $startDay) {
            throw new \InvalidArgumentException('period ends before it starts');
        }
    }

    public function startDay(): int
    {
        return $this->startDay;
    }

    public function endDay(): int
    {
        return $this->endDay;
    }

    public function days(): int
    {
        return $this->endDay - $this->startDay;
    }
}
