// src/modules/auth/auth.controller.js
import * as service from "./auth.service.js";

export async function register(req, res, next) {
  try {
    const { fullName, phone, pin, block, buildingNumber, apartment } = req.body;
    const out = await service.register({ fullName, phone, pin, block, buildingNumber, apartment });
    res.status(201).json(out);
  } catch (e) { next(e); }
}

export async function login(req, res, next) {
  try {
    const { phone, pin } = req.body;
    const out = await service.login({ phone, pin });
    res.json(out);
  } catch (e) { next(e); }
}