import * as service from "./auth.service.js";
import {
  validateAddressCreate,
  validateAddressUpdate,
  validateLogin,
  validateRegister,
  validateUpdateAccount,
} from "./auth.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

export async function register(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };

    const v = validateRegister(body);
    if (!v.ok) return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });

    const out = await service.register(body);
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function login(req, res, next) {
  try {
    const v = validateLogin(req.body);
    if (!v.ok) return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });

    const out = await service.login(req.body);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAccount(req, res, next) {
  try {
    const v = validateUpdateAccount(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateAccount(req.userId, req.body || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listAddresses(req, res, next) {
  try {
    const out = await service.getAddresses(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createAddress(req, res, next) {
  try {
    const v = validateAddressCreate(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.createAddress(req.userId, req.body || {});
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAddress(req, res, next) {
  try {
    const v = validateAddressUpdate(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateAddress(
      req.userId,
      req.params.addressId,
      req.body || {}
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function setDefaultAddress(req, res, next) {
  try {
    const out = await service.setDefaultAddress(req.userId, req.params.addressId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteAddress(req, res, next) {
  try {
    await service.deleteAddress(req.userId, req.params.addressId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}
