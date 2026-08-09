<?php

namespace Bench\Fixture\Orders;

/**
 * A customer with a billing address and an optional separate shipping address.
 *
 * Tier drives nothing on its own — policies read it and decide. Keeping the decision out of here
 * is deliberate: this class is data, not rules.
 */
final class Customer
{
    public const TIER_STANDARD = 'standard';
    public const TIER_BUSINESS = 'business';
    public const TIER_PARTNER = 'partner';

    private string $id;
    private string $name;
    private string $tier;
    private Address $billing;
    private ?Address $shipping;
    private bool $taxExempt;

    public function __construct(
        string $id,
        string $name,
        string $tier,
        Address $billing,
        ?Address $shipping = null,
        bool $taxExempt = false
    ) {
        if (! in_array($tier, self::tiers(), true)) {
            throw new \InvalidArgumentException(sprintf('unknown tier %s', $tier));
        }
        $this->id = $id;
        $this->name = $name;
        $this->tier = $tier;
        $this->billing = $billing;
        $this->shipping = $shipping;
        $this->taxExempt = $taxExempt;
    }

    /** @return list<string> */
    public static function tiers(): array
    {
        return [self::TIER_STANDARD, self::TIER_BUSINESS, self::TIER_PARTNER];
    }

    public function id(): string
    {
        return $this->id;
    }

    public function name(): string
    {
        return $this->name;
    }

    public function tier(): string
    {
        return $this->tier;
    }

    public function billingAddress(): Address
    {
        return $this->billing;
    }

    public function shippingAddress(): Address
    {
        return $this->shipping ?? $this->billing;
    }

    public function shipsToBillingAddress(): bool
    {
        return $this->shipping === null;
    }

    public function isTaxExempt(): bool
    {
        return $this->taxExempt;
    }

    public function isAtLeast(string $tier): bool
    {
        $order = array_flip(self::tiers());

        return $order[$this->tier] >= $order[$tier];
    }

    public function describe(): string
    {
        return sprintf('%s (%s, %s)', $this->name, $this->id, $this->tier);
    }
}
