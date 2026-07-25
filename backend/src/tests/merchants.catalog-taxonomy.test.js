import assert from "node:assert/strict";
import test from "node:test";

import {
  filterCategoriesForActivity,
  getDefaultCatalogTypeForActivity,
  getAllowedCatalogTypesForActivity,
  isCatalogTypeAllowedForActivity,
  resolveCategoryCatalogType,
} from "../modules/merchants/catalog-taxonomy.js";

test("fashion clothing only allows clothes catalog types", () => {
  assert.deepEqual(getAllowedCatalogTypesForActivity("fashion_clothing"), [
    "clothes",
  ]);
  assert.equal(
    isCatalogTypeAllowedForActivity("fashion_clothing", "electronics"),
    false
  );
  assert.equal(
    isCatalogTypeAllowedForActivity("fashion_clothing", "clothes"),
    true
  );
  assert.equal(
    isCatalogTypeAllowedForActivity("fashion_clothing", "generic"),
    false
  );
});

test("restaurant sections do not keep unrelated catalog types", () => {
  const categories = [
    {
      id: 1,
      name: "Burger",
      catalogType: "restaurant",
    },
    {
      id: 2,
      name: "Chargers",
      catalogType: "electronics",
    },
    {
      id: 3,
      name: "Misc",
      catalogType: "generic",
    },
  ];

  const filtered = filterCategoriesForActivity(categories, "restaurant");
  assert.deepEqual(filtered.map((item) => item.id), [1]);
});

test("default catalog type follows the store activity taxonomy", () => {
  assert.equal(getDefaultCatalogTypeForActivity("restaurant"), "restaurant");
  assert.equal(getDefaultCatalogTypeForActivity("coffee_drinks"), "restaurant");
  assert.equal(getDefaultCatalogTypeForActivity("pharmacy"), "generic");
  assert.equal(getDefaultCatalogTypeForActivity("fashion_clothing"), "clothes");
  assert.equal(getDefaultCatalogTypeForActivity("supermarket"), "grocery");
  assert.equal(getDefaultCatalogTypeForActivity("home_kitchen"), "furniture");
  assert.equal(getDefaultCatalogTypeForActivity("furnishings"), "furniture");
  assert.equal(getDefaultCatalogTypeForActivity("dietary_supplements"), "generic");
  assert.equal(getDefaultCatalogTypeForActivity("smoking_supplies"), "generic");
  assert.equal(getDefaultCatalogTypeForActivity("phone_maintenance"), "electronics");
  assert.equal(getDefaultCatalogTypeForActivity("phones_technology"), "electronics");
});

test("pharmacy accepts generic catalog categories", () => {
  assert.deepEqual(getAllowedCatalogTypesForActivity("pharmacy"), ["generic"]);
  assert.equal(isCatalogTypeAllowedForActivity("pharmacy", "generic"), true);
  assert.equal(isCatalogTypeAllowedForActivity("pharmacy", "restaurant"), false);
});

test("legacy category names can still be inferred from safe names", () => {
  assert.equal(
    resolveCategoryCatalogType({
      name: "cloths",
      catalogType: null,
    }),
    "clothes"
  );
  assert.equal(
    resolveCategoryCatalogType({
      name: "إلكترونيات",
      catalogType: null,
    }),
    "electronics"
  );
  assert.equal(
    resolveCategoryCatalogType({
      name: "cloths",
      catalog_type: "generic",
    }),
    "clothes"
  );
  assert.equal(
    resolveCategoryCatalogType({
      name: "Misc",
      catalog_type: "generic",
    }),
    "generic"
  );
});
