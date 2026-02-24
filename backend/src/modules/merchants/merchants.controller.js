import * as service from "./merchants.service.js";
import { validateCreateMerchant } from "./merchants.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

export async function create(req, res, next) {
  try {
    const ownerFromFields =
      req.body?.ownerFullName ||
      req.body?.ownerPhone ||
      req.body?.ownerPin ||
      req.body?.ownerBlock ||
      req.body?.ownerBuildingNumber ||
      req.body?.ownerApartment ||
      req.body?.ownerImageUrl
        ? {
            fullName: req.body?.ownerFullName,
            phone: req.body?.ownerPhone,
            pin: req.body?.ownerPin,
            block: req.body?.ownerBlock,
            buildingNumber: req.body?.ownerBuildingNumber,
            apartment: req.body?.ownerApartment,
            imageUrl: req.body?.ownerImageUrl,
          }
        : null;

    const body = {
      ...req.body,
      imageUrl:
        buildUploadedFileUrl(req, req.files?.merchantImageFile?.[0]) ||
        req.body?.imageUrl,
      owner: req.body?.owner ?? ownerFromFields,
    };

    if (body.owner && typeof body.owner === "string") {
      try {
        body.owner = JSON.parse(body.owner);
      } catch (_) {
        body.owner = null;
      }
    }

    if (body.owner && typeof body.owner === "object") {
      body.owner = {
        ...body.owner,
        imageUrl:
          buildUploadedFileUrl(req, req.files?.ownerImageFile?.[0]) ||
          body.owner.imageUrl,
      };
    }

    const v = validateCreateMerchant(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const merchant = await service.createMerchant(body, req.userId);
    res.status(201).json(merchant);
  } catch (e) {
    next(e);
  }
}

export async function list(req, res, next) {
  try {
    const data = await service.listMerchants(req.query.type);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listProducts(req, res, next) {
  try {
    const data = await service.listMerchantProducts(Number(req.params.merchantId));
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listCategories(req, res, next) {
  try {
    const data = await service.listMerchantCategories(Number(req.params.merchantId));
    res.json(data);
  } catch (e) {
    next(e);
  }
}
