import * as service from "./cars.service.js";
import { validateBrowseCars, validateSmartSearch } from "./cars.validators.js";

export async function listBrands(req, res, next) {
  try {
    const out = service.listBrands({
      search: req.query.search || "",
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listModels(req, res, next) {
  try {
    const out = service.listModels(req.query.brand || "", {
      search: req.query.search || "",
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function browse(req, res, next) {
  try {
    const v = validateBrowseCars(req.query || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }

    const out = service.browseCars(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function smartSearch(req, res, next) {
  try {
    const v = validateSmartSearch(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }

    const out = service.smartSearch(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}
