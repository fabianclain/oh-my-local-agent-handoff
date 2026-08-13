<?php

declare(strict_types=1);

namespace Bench\Fixture\Ledger;

/**
 * A double-entry ledger over integer minor units.
 *
 * Every posting method here follows the same shape on purpose: a docblock, a guard, an append,
 * and a return of the running balance. That similarity is the point of the fixture — an edit
 * anchored on a method name rather than on its docblock lands in the wrong one.
 */
final class Ledger
{
    /** @var list<array{kind: string, memo: string, minor: int}> */
    private array $entries = [];

    private int $balance = 0;

    public function __construct(private readonly string $currency)
    {
    }

    public function currency(): string
    {
        return $this->currency;
    }

    public function balance(): int
    {
        return $this->balance;
    }

    /**
     * @return list<array{kind: string, memo: string, minor: int}>
     */
    public function entries(): array
    {
        return $this->entries;
    }

    public function count(): int
    {
        return count($this->entries);
    }

    /**
     * Post a debit of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postDebit(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a debit must be positive');
        }

        $this->entries[] = ['kind' => 'debit', 'memo' => $memo, 'minor' => $minor];
        $this->balance -= $minor;

        return $this->balance;
    }

    /**
     * Post a credit of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postCredit(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a credit must be positive');
        }

        $this->entries[] = ['kind' => 'credit', 'memo' => $memo, 'minor' => $minor];
        $this->balance += $minor;

        return $this->balance;
    }

    /**
     * Post a adjustment of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postAdjustment(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a adjustment must be positive');
        }

        $this->entries[] = ['kind' => 'adjustment', 'memo' => $memo, 'minor' => $minor];
        $this->balance += $minor;

        return $this->balance;
    }

    /**
     * Post a fee of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postFee(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a fee must be positive');
        }

        $this->entries[] = ['kind' => 'fee', 'memo' => $memo, 'minor' => $minor];
        $this->balance -= $minor;

        return $this->balance;
    }

    /**
     * Post a refund of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postRefund(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a refund must be positive');
        }

        $this->entries[] = ['kind' => 'refund', 'memo' => $memo, 'minor' => $minor];
        $this->balance += $minor;

        return $this->balance;
    }

    /**
     * Post a interest of the given minor units.
     *
     * @param  string  $memo  A short human-readable note stored with the entry.
     * @param  int  $minor  The amount in minor units. Must be positive.
     * @return int The running balance after the posting.
     *
     * @throws \InvalidArgumentException when the amount is not positive.
     */
    public function postInterest(string $memo, int $minor): int
    {
        if ($minor <= 0) {
            throw new \InvalidArgumentException('a interest must be positive');
        }

        $this->entries[] = ['kind' => 'interest', 'memo' => $memo, 'minor' => $minor];
        $this->balance += $minor;

        return $this->balance;
    }

    /**
     * The total of every entry of one kind.
     */
    public function totalOf(string $kind): int
    {
        $total = 0;
        foreach ($this->entries as $entry) {
            if ($entry['kind'] === $kind) {
                $total += $entry['minor'];
            }
        }

        return $total;
    }

    /**
     * A one-line summary, used by the reporting layer.
     */
    public function summary(): string
    {
        return sprintf('%s ledger: %d entries, balance %d', $this->currency, count($this->entries), $this->balance);
    }
}
