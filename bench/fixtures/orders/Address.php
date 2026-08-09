<?php

namespace Bench\Fixture\Orders;

/**
 * A postal address. Country codes are ISO 3166-1 alpha-2 and always stored upper case.
 */
final class Address
{
    private string $line1;
    private string $line2;
    private string $city;
    private string $postcode;
    private string $country;

    public function __construct(string $line1, string $city, string $postcode, string $country, string $line2 = '')
    {
        if ($line1 === '') {
            throw new \InvalidArgumentException('line1 must not be empty');
        }
        if (strlen($country) !== 2) {
            throw new \InvalidArgumentException('country must be a two-letter code');
        }
        $this->line1 = $line1;
        $this->line2 = $line2;
        $this->city = $city;
        $this->postcode = $postcode;
        $this->country = strtoupper($country);
    }

    public function line1(): string
    {
        return $this->line1;
    }

    public function line2(): string
    {
        return $this->line2;
    }

    public function city(): string
    {
        return $this->city;
    }

    public function postcode(): string
    {
        return $this->postcode;
    }

    public function country(): string
    {
        return $this->country;
    }

    public function isDomestic(string $homeCountry): bool
    {
        return $this->country === strtoupper($homeCountry);
    }

    /** @return list<string> */
    public function lines(): array
    {
        $lines = [$this->line1];

        if ($this->line2 !== '') {
            $lines[] = $this->line2;
        }

        $lines[] = sprintf('%s %s', $this->postcode, $this->city);
        $lines[] = $this->country;

        return $lines;
    }

    public function oneLine(): string
    {
        return implode(', ', $this->lines());
    }
}
