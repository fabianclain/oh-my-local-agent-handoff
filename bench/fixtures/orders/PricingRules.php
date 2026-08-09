<?php

namespace Bench\Fixture\Orders;

/**
 * The one place that decides which policies a given customer gets.
 *
 * Everything here is a lookup from customer attributes to a policy object. No arithmetic happens
 * in this class: it chooses the rule, the rule does the work. Adding a new kind of policy means
 * adding a selector here as well, or orders will silently fall back to the default.
 */
final class PricingRules
{
    private string $homeCountry;
    /** @var array<string, float> */
    private array $tierTaxRates;

    public function __construct(string $homeCountry = 'RO', array $tierTaxRates = [])
    {
        $this->homeCountry = strtoupper($homeCountry);
        $this->tierTaxRates = $tierTaxRates === [] ? [
            Customer::TIER_STANDARD => 0.20,
            Customer::TIER_BUSINESS => 0.19,
            Customer::TIER_PARTNER => 0.15,
        ] : $tierTaxRates;
    }

    public function homeCountry(): string
    {
        return $this->homeCountry;
    }

    public function taxPolicyFor(Customer $customer): TaxPolicy
    {
        if ($customer->isTaxExempt()) {
            return new ZeroTax();
        }

        return new FlatRateTax($this->taxRateFor($customer));
    }

    public function taxRateFor(Customer $customer): float
    {
        return $this->tierTaxRates[$customer->tier()] ?? 0.20;
    }

    public function shippingPolicyFor(Customer $customer, int $itemCount): ShippingPolicy
    {
        if ($customer->isAtLeast(Customer::TIER_PARTNER)) {
            return new FreeShipping();
        }

        if ($itemCount >= 10) {
            return new FlatShipping(500);
        }

        return new PerItemShipping(150, 900, $this->homeCountry);
    }

    public function describeFor(Customer $customer, int $itemCount): string
    {
        return sprintf(
            '%s: tax %s, shipping %s',
            $customer->tier(),
            $this->taxPolicyFor($customer)->label(),
            $this->shippingPolicyFor($customer, $itemCount)->label()
        );
    }
}
