<?php
// Fuzz one candidate Proration against a reference implementation of the plan's own words.
//
// The plan's six acceptance criteria test six hand-picked cases. The question this answers is a
// different one: does an implementation that passes those six agree with the specification
// everywhere else? A plausible-wrong answer is precisely one that satisfies the examples.
//
// Reference, straight from the plan text:
//   subtotal   = floor( (sum of f*d) / D + 1/2 )
//   allocation = floor(f*d/D) each, then hand out (subtotal - sum of floors) cents one at a time
//                to the largest remainder (f*d) mod D, ties going to the line added first.

$dir = $argv[1];
foreach (glob("$dir/*.php") as $f) { require_once $f; }
use Bench\Fixture\Billing as B;

function reference(array $lines, int $D): array {
    // $lines: [name, fee, activeDays]
    $sum = 0; $floors = []; $rems = [];
    foreach ($lines as $idx => [$name, $f, $d]) {
        $prod = $f * $d;
        $sum += $prod;
        $floors[$idx] = intdiv($prod, $D);
        $rems[$idx] = $prod % $D;
    }
    $subtotal = (int) floor($sum / $D + 0.5);
    // integer form, to avoid float error at large values
    $subtotal = intdiv(2 * $sum + $D, 2 * $D);
    $left = $subtotal - array_sum($floors);
    $order = array_keys($floors);
    usort($order, function ($a, $b) use ($rems) {
        if ($rems[$a] !== $rems[$b]) { return $rems[$b] <=> $rems[$a]; }
        return $a <=> $b;                       // added first wins
    });
    $alloc = $floors;
    for ($k = 0; $k < $left; $k++) { $alloc[$order[$k % count($order)]]++; }
    return [$subtotal, $alloc];
}

mt_srand(20260811);
$failures = 0; $checked = 0;
for ($trial = 0; $trial < 4000; $trial++) {
    $D = mt_rand(1, 31);
    $n = mt_rand(1, 5);
    $period = new B\Period(0, $D);
    $invoice = new B\Invoice($period);
    $spec = [];
    for ($i = 0; $i < $n; $i++) {
        $fee = mt_rand(0, 5000);
        $days = mt_rand(0, $D);
        $name = "l$i";
        $invoice->addLine(new B\Subscription($name, new B\Money($fee), new B\Period(0, $days)));
        $spec[] = [$name, $fee, $days];
    }

    [$wantSub, $wantAllocIdx] = reference($spec, $D);
    $want = [];
    foreach ($spec as $idx => [$name, , ]) { $want[$name] = $wantAllocIdx[$idx]; }

    try {
        $pr = $invoice->proration();
        $gotSub = $pr->subtotal()->cents();
        $gotAlloc = [];
        foreach ($pr->allocation() as $name => $money) { $gotAlloc[$name] = $money->cents(); }
    } catch (\Throwable $e) {
        $failures++;
        if ($failures <= 3) { echo "  THREW  D=$D " . json_encode($spec) . " : " . $e->getMessage() . "\n"; }
        continue;
    }
    $checked++;

    if ($gotSub !== $wantSub || $gotAlloc !== $want) {
        $failures++;
        if ($failures <= 3) {
            echo "  DIFFER D=$D lines=" . json_encode($spec) . "\n";
            echo "         subtotal want $wantSub got $gotSub\n";
            echo "         alloc    want " . json_encode($want) . "\n";
            echo "                  got  " . json_encode($gotAlloc) . "\n";
        }
    }
}
printf("%s: %d/%d trials disagree with the specification\n", basename($dir), $failures, 4000);
