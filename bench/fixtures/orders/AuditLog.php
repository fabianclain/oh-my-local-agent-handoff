<?php

namespace Bench\Fixture\Orders;

/**
 * Append-only record of what happened to an order.
 *
 * Entries are immutable once written. Nothing in this class interprets an entry; callers decide
 * what is worth recording and the log simply keeps it in order.
 */
final class AuditLog
{
    /** @var list<array{event: string, detail: string, sequence: int}> */
    private array $entries = [];
    private int $sequence = 0;

    public function record(string $event, string $detail = ''): void
    {
        if ($event === '') {
            throw new \InvalidArgumentException('event must not be empty');
        }
        $this->sequence++;
        $this->entries[] = ['event' => $event, 'detail' => $detail, 'sequence' => $this->sequence];
    }

    /** @return list<array{event: string, detail: string, sequence: int}> */
    public function entries(): array
    {
        return $this->entries;
    }

    public function count(): int
    {
        return count($this->entries);
    }

    public function has(string $event): bool
    {
        foreach ($this->entries as $entry) {
            if ($entry['event'] === $event) {
                return true;
            }
        }

        return false;
    }

    public function detailFor(string $event): ?string
    {
        foreach ($this->entries as $entry) {
            if ($entry['event'] === $event) {
                return $entry['detail'];
            }
        }

        return null;
    }

    /** @return list<string> */
    public function eventNames(): array
    {
        return array_map(static fn (array $e): string => $e['event'], $this->entries);
    }

    public function render(): string
    {
        $lines = [];

        foreach ($this->entries as $entry) {
            $lines[] = $entry['detail'] === ''
                ? sprintf('%d. %s', $entry['sequence'], $entry['event'])
                : sprintf('%d. %s — %s', $entry['sequence'], $entry['event'], $entry['detail']);
        }

        return implode("\n", $lines);
    }
}
