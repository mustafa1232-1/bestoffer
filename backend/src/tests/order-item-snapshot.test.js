import assert from "node:assert/strict";
import test from "node:test";

import {
  __ordersRepoTestables,
} from "../modules/orders/orders.repo.js";
import {
  ORDER_ITEM_DISPLAY_SNAPSHOT_VERSION,
  buildOrderItemDisplaySnapshot,
  hydrateOrderItemDisplaySnapshot,
} from "../modules/orders/order-item-snapshot.logic.js";

const {
  buildOrderTrackingEnvelope,
} = __ordersRepoTestables;

test("snapshot builder emits a stable v1 display snapshot", () => {
  const snapshot = buildOrderItemDisplaySnapshot({
    productId: 42,
    productName: "Tee Shirt",
    productImageUrl: "https://cdn.example.com/product.jpg",
    thumbnailUrl: "https://cdn.example.com/thumb.jpg",
    sku: "TSH-001",
    variantId: 99,
    variantName: "Black / XL",
    variantSku: "TSH-001-BLK-XL",
    quantity: 2,
    unitPrice: 5000,
    lineTotal: 10000,
    currency: "IQD",
    selectedColor: {
      label: "Color",
      value: "Black",
      hex: "#000000",
    },
    selectedSize: {
      label: "Size",
      value: "XL",
    },
    specs: [
      { label: "Fabric", value: "Cotton" },
      { label: "Department", value: "Men" },
    ],
    options: [{ label: "Gift wrap", value: "Yes" }],
    addons: [{ label: "Hanger", value: "Included" }],
    removals: [{ label: "Tag", value: "Removed" }],
    userNote: "Please pack neatly",
    activityType: "fashion_clothing",
    storeId: 7,
    storeName: "Fashion Hub",
  });

  assert.equal(snapshot.version, ORDER_ITEM_DISPLAY_SNAPSHOT_VERSION);
  assert.equal(snapshot.productId, 42);
  assert.equal(snapshot.productName, "Tee Shirt");
  assert.equal(snapshot.productImageUrl, "https://cdn.example.com/product.jpg");
  assert.equal(snapshot.thumbnailUrl, "https://cdn.example.com/thumb.jpg");
  assert.equal(snapshot.variantId, 99);
  assert.equal(snapshot.variantSku, "TSH-001-BLK-XL");
  assert.equal(snapshot.quantity, 2);
  assert.equal(snapshot.unitPrice, 5000);
  assert.equal(snapshot.lineTotal, 10000);
  assert.equal(snapshot.selectedColor?.value, "Black");
  assert.equal(snapshot.selectedColor?.hex, "#000000");
  assert.equal(snapshot.selectedSize?.value, "XL");
  assert.equal(snapshot.specs.length, 2);
  assert.equal(snapshot.options.length, 1);
  assert.equal(snapshot.addons.length, 1);
  assert.equal(snapshot.removals.length, 1);
  assert.equal(snapshot.userNote, "Please pack neatly");
  assert.equal(snapshot.activityType, "fashion_clothing");
  assert.equal(snapshot.storeId, 7);
  assert.equal(snapshot.storeName, "Fashion Hub");
});

test("legacy order items hydrate from fallback fields when no snapshot exists", () => {
  const hydrated = hydrateOrderItemDisplaySnapshot(
    {
      id: 9,
      order_id: 11,
      product_id: 42,
      product_name: "Legacy Shirt",
      quantity: 3,
      unit_price: 4800,
      line_total: 14400,
      selected_variant_json: {
        variantId: 77,
        sku: "LEG-77",
        signature: "color:black|size:xl",
        colorLabel: "Black",
        colorHex: "#000000",
        sizeLabel: "XL",
        selections: [
          { groupCode: "color", label: "Color", value: "Black" },
          { groupCode: "size", label: "Size", value: "XL" },
        ],
      },
      selected_variant_options_json: [
        { groupCode: "color", label: "Color", value: "Black" },
        { groupCode: "size", label: "Size", value: "XL" },
      ],
      selected_modifiers_json: [],
      pricing_breakdown_json: {},
      display_snapshot_json: null,
    },
    {
      id: 11,
      merchant_id: 7,
      merchant_name: "Fashion Hub",
      merchant_activity_type: "fashion_clothing",
    }
  );

  assert.equal(hydrated.display_snapshot_json.version, 1);
  assert.equal(hydrated.display_snapshot_json.productName, "Legacy Shirt");
  assert.equal(hydrated.display_snapshot_json.selectedColor?.value, "Black");
  assert.equal(hydrated.display_snapshot_json.selectedSize?.value, "XL");
  assert.equal(hydrated.display_snapshot_json.storeId, 7);
  assert.equal(hydrated.display_snapshot_json.storeName, "Fashion Hub");
});

test("stored snapshots stay immutable even if the source product changes later", () => {
  const originalSnapshot = buildOrderItemDisplaySnapshot({
    productId: 42,
    productName: "Original Tee",
    productImageUrl: "https://cdn.example.com/original.jpg",
    thumbnailUrl: "https://cdn.example.com/original-thumb.jpg",
    variantId: 1,
    variantSku: "ORIG-1",
    quantity: 1,
    unitPrice: 7000,
    lineTotal: 7000,
    selectedColor: { label: "Color", value: "Black", hex: "#000000" },
    selectedSize: { label: "Size", value: "M" },
    storeId: 7,
    storeName: "Fashion Hub",
  });

  const hydrated = hydrateOrderItemDisplaySnapshot(
    {
      id: 9,
      order_id: 11,
      product_id: 42,
      product_name: "Edited Tee",
      unit_price: 9000,
      line_total: 9000,
      display_snapshot_json: originalSnapshot,
      selected_variant_json: {
        variantId: 2,
        sku: "EDIT-2",
        colorLabel: "Blue",
        sizeLabel: "L",
      },
    },
    {
      id: 11,
      merchant_id: 7,
      merchant_name: "Renamed Fashion Hub",
      merchant_activity_type: "electronics_mobile",
    }
  );

  assert.equal(hydrated.display_snapshot_json.productName, "Original Tee");
  assert.equal(
    hydrated.display_snapshot_json.productImageUrl,
    "https://cdn.example.com/original.jpg"
  );
  assert.equal(hydrated.display_snapshot_json.selectedColor?.value, "Black");
  assert.equal(hydrated.display_snapshot_json.storeName, "Fashion Hub");
});

test("tracking envelopes expose order.items with display data", () => {
  const itemSnapshot = buildOrderItemDisplaySnapshot({
    productId: 42,
    productName: "Sample Tee",
    quantity: 2,
    unitPrice: 5000,
    lineTotal: 10000,
    selectedColor: { label: "Color", value: "Black" },
    storeId: 7,
    storeName: "Fashion Hub",
  });
  const envelope = buildOrderTrackingEnvelope(
    {
      id: 11,
      merchant_id: 7,
      merchant_name: "Fashion Hub",
      merchant_type: "store",
      merchant_activity_type: "fashion_clothing",
      status: "ready_for_delivery",
      total_amount: 10000,
      delivery_fee: 0,
      customer_city: "Basra",
      customer_block: "A1",
      customer_building_number: "12",
      customer_apartment: "3",
      created_at: new Date("2026-07-01T10:00:00.000Z"),
      items: [
        {
          display_snapshot_json: itemSnapshot,
        },
      ],
    },
    {
      viewerMode: "publicReadonly",
      latestLocation: null,
    }
  );

  assert.equal(envelope.order.items.length, 1);
  assert.equal(envelope.items.length, 1);
  assert.equal(envelope.order.items[0].display_snapshot_json.productName, "Sample Tee");
  assert.equal(envelope.order.items[0].display_snapshot_json.selectedColor?.value, "Black");
});

test("null or broken presentation fields do not crash the snapshot builder", () => {
  const snapshot = buildOrderItemDisplaySnapshot({
    productId: 1,
    productName: "Fallback Item",
    productImageUrl: null,
    thumbnailUrl: "   ",
    quantity: 1,
    unitPrice: 0,
    lineTotal: 0,
    specs: null,
    options: null,
    addons: null,
    removals: null,
  });

  assert.equal(snapshot.productImageUrl, null);
  assert.equal(snapshot.thumbnailUrl, null);
  assert.equal(Array.isArray(snapshot.specs), true);
  assert.equal(Array.isArray(snapshot.options), true);
  assert.equal(Array.isArray(snapshot.addons), true);
  assert.equal(Array.isArray(snapshot.removals), true);
});
