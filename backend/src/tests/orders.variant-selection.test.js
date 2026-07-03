import assert from "node:assert/strict";
import test from "node:test";

import {
  __ordersRepoTestables,
} from "../modules/orders/orders.repo.js";
import {
  __ordersServiceTestables,
} from "../modules/orders/orders.service.js";

const {
  resolveVariantSelectionForItem,
  shouldApplyProductInventoryGate,
} = __ordersRepoTestables;

const { normalizeItems } = __ordersServiceTestables;

function buildVariantCatalog() {
  const groups = [
    {
      groupId: 1,
      groupCode: "color",
      labelAr: "اللون",
      labelEn: "Color",
      displayMode: "swatches",
      selectionMode: "single",
      required: true,
      sortOrder: 0,
      metadata: {},
      options: [
        {
          optionId: 11,
          optionCode: "red",
          labelAr: "أحمر",
          labelEn: "Red",
          swatchHex: "#FF0000",
          priceDelta: 0,
          imageUrl: "/red.jpg",
          isAvailable: true,
          sortOrder: 0,
          metadata: {},
        },
        {
          optionId: 12,
          optionCode: "blue",
          labelAr: "أزرق",
          labelEn: "Blue",
          swatchHex: "#0000FF",
          priceDelta: 0,
          imageUrl: "/blue.jpg",
          isAvailable: true,
          sortOrder: 1,
          metadata: {},
        },
      ],
    },
    {
      groupId: 2,
      groupCode: "size",
      labelAr: "المقاس",
      labelEn: "Size",
      displayMode: "chips",
      selectionMode: "single",
      required: true,
      sortOrder: 1,
      metadata: {},
      options: [
        {
          optionId: 21,
          optionCode: "s",
          labelAr: "S",
          labelEn: "S",
          swatchHex: null,
          priceDelta: 0,
          imageUrl: null,
          isAvailable: true,
          sortOrder: 0,
          metadata: {},
        },
        {
          optionId: 22,
          optionCode: "m",
          labelAr: "M",
          labelEn: "M",
          swatchHex: null,
          priceDelta: 0,
          imageUrl: null,
          isAvailable: true,
          sortOrder: 1,
          metadata: {},
        },
      ],
    },
  ];

  const groupByCode = new Map();
  for (const group of groups) {
    groupByCode.set(group.groupCode, {
      ...group,
      optionByCode: new Map(group.options.map((option) => [option.optionCode, option])),
      optionById: new Map(group.options.map((option) => [option.optionId, option])),
    });
  }

  return {
    groups: groups.map((group) => ({
      ...group,
      optionByCode: new Map(group.options.map((option) => [option.optionCode, option])),
      optionById: new Map(group.options.map((option) => [option.optionId, option])),
    })),
    groupByCode,
    variants: [
      {
        variantId: 101,
        signature: "color:red|size:m",
        selections: [
          { groupCode: "color", optionCode: "red" },
          { groupCode: "size", optionCode: "m" },
        ],
        sku: "RED-M",
        barcode: "BARCODE-RED-M",
        material: "cotton",
        priceOverride: null,
        discountedPriceOverride: null,
        stockQuantity: 4,
        imageUrl: "/red.jpg",
        isAvailable: true,
      },
      {
        variantId: 102,
        signature: "color:blue|size:s",
        selections: [
          { groupCode: "color", optionCode: "blue" },
          { groupCode: "size", optionCode: "s" },
        ],
        sku: "BLUE-S",
        barcode: "BARCODE-BLUE-S",
        material: "cotton",
        priceOverride: null,
        discountedPriceOverride: null,
        stockQuantity: 2,
        imageUrl: "/blue.jpg",
        isAvailable: true,
      },
    ],
  };
}

test("variantId takes precedence when payload carries exact selections", () => {
  const result = resolveVariantSelectionForItem(
    { id: 9, name: "Tee" },
    {
      quantity: 1,
      selectedVariant: {
        variantId: 101,
        selections: [
          { groupCode: "color", optionCode: "red" },
          { groupCode: "size", optionCode: "m" },
        ],
      },
    },
    buildVariantCatalog()
  );

  assert.equal(result.variantId, 101);
  assert.equal(result.selectedVariantSnapshot.variantId, 101);
  assert.equal(result.selectedVariantSnapshot.colorCode, "red");
  assert.equal(result.selectedVariantSnapshot.sizeCode, "m");
  assert.equal(result.selectedVariantSnapshot.imageUrl, "/red.jpg");
});

test("variantId and selection mismatch is rejected", () => {
  assert.throws(
    () =>
      resolveVariantSelectionForItem(
        { id: 9, name: "Tee" },
        {
          quantity: 1,
          selectedVariant: {
            variantId: 101,
            selections: [
              { groupCode: "color", optionCode: "blue" },
              { groupCode: "size", optionCode: "s" },
            ],
          },
        },
        buildVariantCatalog()
      ),
    (error) => error?.message === "PRODUCT_VARIANT_SELECTION_INVALID"
  );
});

test("selection-only payload still resolves the exact variant", () => {
  const result = resolveVariantSelectionForItem(
    { id: 9, name: "Tee" },
    {
      quantity: 1,
      selectedVariantSelections: [
        { groupCode: "color", optionCode: "blue" },
        { groupCode: "size", optionCode: "s" },
      ],
    },
    buildVariantCatalog()
  );

  assert.equal(result.variantId, 102);
  assert.equal(result.selectedVariantSnapshot.variantId, 102);
  assert.equal(result.selectedVariantSnapshot.colorCode, "blue");
  assert.equal(result.selectedVariantSnapshot.sizeCode, "s");
});

test("variant stock equal to requested quantity previews successfully", () => {
  const result = resolveVariantSelectionForItem(
    { id: 9, name: "Tee" },
    { quantity: 4, selectedVariant: { variantId: 101 } },
    buildVariantCatalog()
  );

  assert.equal(result.variantId, 101);
  assert.equal(result.selectedVariantSnapshot.stockQuantity, 4);
});

test("zero-stock variant returns PRODUCT_OUT_OF_STOCK with structured details", () => {
  const catalog = buildVariantCatalog();
  catalog.variants[0].stockQuantity = 0;

  assert.throws(
    () =>
      resolveVariantSelectionForItem(
        { id: 9, name: "mm" },
        { quantity: 1, selectedVariant: { variantId: 101 } },
        catalog
      ),
    (error) => {
      assert.equal(error.message, "PRODUCT_OUT_OF_STOCK");
      assert.equal(error.status, 400);
      assert.deepEqual(error.details, {
        reason: "OUT_OF_STOCK",
        productId: 9,
        productName: "mm",
        variantId: 101,
        colorName: "أحمر",
        size: "M",
        requestedQuantity: 1,
        availableQuantity: 0,
      });
      return true;
    }
  );
});

test("requesting more than variant stock is rejected with available quantity", () => {
  assert.throws(
    () =>
      resolveVariantSelectionForItem(
        { id: 9, name: "Tee" },
        { quantity: 5, selectedVariant: { variantId: 101 } },
        buildVariantCatalog()
      ),
    (error) => {
      assert.equal(error.message, "PRODUCT_OUT_OF_STOCK");
      assert.equal(error.details.requestedQuantity, 5);
      assert.equal(error.details.availableQuantity, 4);
      return true;
    }
  );
});

test("typo in display labels does not break resolution when variantId is valid", () => {
  const result = resolveVariantSelectionForItem(
    { id: 9, name: "mm" },
    {
      quantity: 1,
      selectedVariant: {
        variantId: 101,
        selections: [
          { groupCode: "color", optionCode: "red", optionLabel: "purpel!!" },
          { groupCode: "size", optionCode: "m", optionLabel: "XLLL" },
        ],
      },
    },
    buildVariantCatalog()
  );

  assert.equal(result.variantId, 101);
  assert.equal(result.selectedVariantSnapshot.colorLabel, "أحمر");
});

test("simple product without variants previews without variant errors", () => {
  const result = resolveVariantSelectionForItem(
    { id: 5, name: "Simple" },
    { quantity: 3 },
    null
  );

  assert.equal(result.hasVariants, false);
  assert.equal(result.selectedVariantSnapshot, null);
});

test("product-level inventory gate is skipped when a concrete variant is resolved", () => {
  assert.equal(
    shouldApplyProductInventoryGate({
      variantResolution: { hasVariants: true, variantId: 101 },
      inventoryEnabled: true,
      inventoryQuantity: 0,
    }),
    false
  );
});

test("product-level inventory gate still applies to simple tracked products", () => {
  assert.equal(
    shouldApplyProductInventoryGate({
      variantResolution: { hasVariants: false, variantId: null },
      inventoryEnabled: true,
      inventoryQuantity: 2,
    }),
    true
  );
  assert.equal(
    shouldApplyProductInventoryGate({
      variantResolution: { hasVariants: false, variantId: null },
      inventoryEnabled: true,
      inventoryQuantity: null,
    }),
    false
  );
  assert.equal(
    shouldApplyProductInventoryGate({
      variantResolution: { hasVariants: false, variantId: null },
      inventoryEnabled: false,
      inventoryQuantity: 5,
    }),
    false
  );
});

test("normalizeItems keeps separate variants separate in checkout payloads", () => {
  const items = normalizeItems([
    {
      productId: 9,
      quantity: 1,
      selectedVariantId: 101,
      selectedVariantSelections: [
        { groupCode: "color", optionCode: "red" },
        { groupCode: "size", optionCode: "m" },
      ],
    },
    {
      productId: 9,
      quantity: 2,
      selectedVariantId: 102,
      selectedVariantSelections: [
        { groupCode: "color", optionCode: "blue" },
        { groupCode: "size", optionCode: "s" },
      ],
    },
  ]);

  assert.equal(items.length, 2);
  assert.equal(items[0].selectedVariant.variantId, 101);
  assert.equal(items[1].selectedVariant.variantId, 102);
});
