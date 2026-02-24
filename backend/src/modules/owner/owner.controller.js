import * as service from "./owner.service.js";
import {
  validateOwnerAssignDelivery,
  validateOwnerCategoryCreate,
  validateOwnerCategoryUpdate,
  validateOwnerMerchantUpdate,
  validateOwnerOrderStatusUpdate,
  validateOwnerProductCreate,
  validateOwnerProductUpdate,
  validateOwnerRegister,
} from "./owner.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

function parseBooleanInput(value) {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return undefined;
  const lowered = value.trim().toLowerCase();
  if (lowered === "true") return true;
  if (lowered === "false") return false;
  return undefined;
}

export async function register(req, res, next) {
  try {
    const body = {
      ...req.body,
      ownerImageUrl:
        buildUploadedFileUrl(req, req.files?.ownerImageFile?.[0]) ||
        req.body?.ownerImageUrl,
      merchantImageUrl:
        buildUploadedFileUrl(req, req.files?.merchantImageFile?.[0]) ||
        req.body?.merchantImageUrl,
    };

    const v = validateOwnerRegister(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.registerOwner(body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function getMerchant(req, res, next) {
  try {
    const merchant = await service.getOwnerMerchant(req.userId);
    res.json({ merchant });
  } catch (e) {
    next(e);
  }
}

export async function updateMerchant(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
      isOpen:
        req.body?.isOpen === undefined
          ? undefined
          : parseBooleanInput(req.body?.isOpen),
    };

    const v = validateOwnerMerchantUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const merchant = await service.updateOwnerMerchant(req.userId, body);
    res.json({ merchant });
  } catch (e) {
    next(e);
  }
}

export async function listProducts(req, res, next) {
  try {
    const data = await service.listOwnerProducts(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listCategories(req, res, next) {
  try {
    const data = await service.listOwnerCategories(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function createCategory(req, res, next) {
  try {
    const v = validateOwnerCategoryCreate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const category = await service.createOwnerCategory(req.userId, req.body);
    res.status(201).json(category);
  } catch (e) {
    next(e);
  }
}

export async function updateCategory(req, res, next) {
  try {
    const v = validateOwnerCategoryUpdate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const category = await service.updateOwnerCategory(
      req.userId,
      Number(req.params.categoryId),
      req.body
    );
    res.json(category);
  } catch (e) {
    next(e);
  }
}

export async function deleteCategory(req, res, next) {
  try {
    await service.deleteOwnerCategory(req.userId, Number(req.params.categoryId));
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function createProduct(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
      freeDelivery:
        req.body?.freeDelivery === undefined
          ? undefined
          : parseBooleanInput(req.body?.freeDelivery),
      isAvailable:
        req.body?.isAvailable === undefined
          ? undefined
          : parseBooleanInput(req.body?.isAvailable),
    };

    const v = validateOwnerProductCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const product = await service.createOwnerProduct(req.userId, body);
    res.status(201).json(product);
  } catch (e) {
    next(e);
  }
}

export async function updateProduct(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
      freeDelivery:
        req.body?.freeDelivery === undefined
          ? undefined
          : parseBooleanInput(req.body?.freeDelivery),
      isAvailable:
        req.body?.isAvailable === undefined
          ? undefined
          : parseBooleanInput(req.body?.isAvailable),
    };

    const v = validateOwnerProductUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const product = await service.updateOwnerProduct(
      req.userId,
      Number(req.params.productId),
      body
    );
    res.json(product);
  } catch (e) {
    next(e);
  }
}

export async function deleteProduct(req, res, next) {
  try {
    await service.deleteOwnerProduct(req.userId, Number(req.params.productId));
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function listDeliveryAgents(req, res, next) {
  try {
    const data = await service.listDeliveryAgents();
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listCurrentOrders(req, res, next) {
  try {
    const data = await service.listCurrentOrders(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function listOrderHistory(req, res, next) {
  try {
    const data = await service.listOrderHistory(req.userId, req.query.date);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function updateOrderStatus(req, res, next) {
  try {
    const v = validateOwnerOrderStatusUpdate(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.updateOrderStatus(
      req.userId,
      req.params.orderId,
      req.body.status,
      req.body.estimatedPrepMinutes,
      req.body.estimatedDeliveryMinutes
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function assignDelivery(req, res, next) {
  try {
    const v = validateOwnerAssignDelivery(req.body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.assignDelivery(
      req.userId,
      req.params.orderId,
      req.body.deliveryUserId
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function analytics(req, res, next) {
  try {
    const out = await service.ownerAnalytics(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function printOrdersReport(req, res, next) {
  try {
    const out = await service.printOrdersReport(req.userId, req.query?.period);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function settlementSummary(req, res, next) {
  try {
    const out = await service.settlementSummary(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function requestSettlement(req, res, next) {
  try {
    const out = await service.requestSettlement(req.userId, req.body?.note);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}
