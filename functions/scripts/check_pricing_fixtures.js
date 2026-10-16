'use strict';

// Owner-runnable parity gate for the trusted pricing mirror. NOT executed by any sub-agent
// (only the main agent runs node). From the repo root:
//
//   node functions/scripts/check_pricing_fixtures.js
//
// It loads test/data/slab_fixtures.json — the identical file the Dart test
// test/backend_pricing_parity_test.dart consumes — runs functions/lib/pricing.js over every
// case, and exits non-zero on the first mismatch. Because both engines are checked against the
// same expected figures, Dart engine == fixture == pricing.js establishes three-way parity.

const fs = require('node:fs');
const path = require('node:path');
const {
  priceFor,
  cartTotals,
  validateSlabGrid,
  AmbiguousSlabError,
} = require('../lib/pricing');

const fixturePath = path.resolve(__dirname, '../../test/data/slab_fixtures.json');
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));

let failures = 0;
function fail(msg) {
  failures += 1;
  console.error(`FAIL ${msg}`);
}
function ok(msg) {
  console.log(`PASS ${msg}`);
}

for (const testCase of fixture.priceCases) {
  if (testCase.expectThrow) {
    let threw = false;
    try {
      priceFor({
        product: testCase.product,
        qty: testCase.qty,
        variant: testCase.variant ?? null,
        customerOverrideUnitPricePaise: testCase.customerOverrideUnitPricePaise ?? null,
      });
    } catch (error) {
      threw = error instanceof AmbiguousSlabError;
    }
    threw ? ok(`priceFor ${testCase.id} threw`) : fail(`priceFor ${testCase.id} should throw`);
    continue;
  }

  const result = priceFor({
    product: testCase.product,
    qty: testCase.qty,
    variant: testCase.variant ?? null,
    customerOverrideUnitPricePaise: testCase.customerOverrideUnitPricePaise ?? null,
  });
  const e = testCase.expected;
  if (result.unitPricePaise !== e.unitPricePaise) {
    fail(`${testCase.id} unitPricePaise ${result.unitPricePaise} != ${e.unitPricePaise}`);
  } else if (result.lineTotalPaise !== e.lineTotalPaise) {
    fail(`${testCase.id} lineTotalPaise ${result.lineTotalPaise} != ${e.lineTotalPaise}`);
  } else if (result.savedPaise !== e.savedPaise) {
    fail(`${testCase.id} savedPaise ${result.savedPaise} != ${e.savedPaise}`);
  } else {
    ok(`priceFor ${testCase.id}`);
  }
}

for (const gridCase of fixture.gridCases) {
  let threw = false;
  try {
    validateSlabGrid(gridCase.slabs);
  } catch (error) {
    threw = error instanceof AmbiguousSlabError;
  }
  const wanted = gridCase.expectThrow;
  if (threw === wanted) {
    ok(`validateSlabGrid ${gridCase.id}`);
  } else {
    fail(`validateSlabGrid ${gridCase.id} threw=${threw} expected=${wanted}`);
  }
}

for (const taxCase of fixture.taxCases) {
  const line = {
    qty: taxCase.qty,
    lineTotalPaise: taxCase.lineTotalPaise,
    savedPaise: 0,
  };
  const t = cartTotals([line], {
    couponDiscountPaise: taxCase.couponDiscountPaise,
    shippingPaise: taxCase.shippingPaise,
    taxRateBps: taxCase.taxRateBps,
    taxInclusive: taxCase.taxInclusive,
  });
  const e = taxCase.expected;
  if (
    t.subtotalPaise !== e.subtotalPaise ||
    t.couponDiscountPaise !== e.couponDiscountPaise ||
    t.taxPaise !== e.taxPaise ||
    t.grandTotalPaise !== e.grandTotalPaise ||
    t.payableRoundedPaise !== e.payableRoundedPaise
  ) {
    fail(
      `cartTotals ${taxCase.id} got ` +
        `${JSON.stringify({ subtotalPaise: t.subtotalPaise, couponDiscountPaise: t.couponDiscountPaise, taxPaise: t.taxPaise, grandTotalPaise: t.grandTotalPaise, payableRoundedPaise: t.payableRoundedPaise })}`,
    );
  } else {
    ok(`cartTotals ${taxCase.id}`);
  }
}

if (failures > 0) {
  console.error(`\n${failures} pricing parity failure(s).`);
  process.exit(1);
}
console.log('\nAll pricing.js fixture cases match the shared expected figures.');
