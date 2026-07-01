import * as repo from "./products.repo.js";

export async function summary(req, res, next) {
  try {
    const productId = Number(req.params.productId);
    if (!Number.isInteger(productId) || productId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["productId"] });
    }
    const product = await repo.loadProductRichCatalogById(productId);
    if (!product) {
      return res.status(404).json({ message: "PRODUCT_NOT_FOUND" });
    }
    res.json({ product });
  } catch (error) {
    next(error);
  }
}

export async function details(req, res, next) {
  try {
    const productId = Number(req.params.productId);
    if (!Number.isInteger(productId) || productId <= 0) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: ["productId"] });
    }
    const product = await repo.loadProductRichCatalogById(productId);
    if (!product) {
      return res.status(404).json({ message: "PRODUCT_NOT_FOUND" });
    }
    res.json({ product });
  } catch (error) {
    next(error);
  }
}
