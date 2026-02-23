// src/modules/auth/auth.service.js
import { createUser, findUserByPhone } from "./auth.repo.js";
import { hashPin, verifyPin } from "../../shared/utils/hash.js";
import { signAccessToken } from "../../shared/utils/jwt.js";

export async function register(dto) {
  const exists = await findUserByPhone(dto.phone);
  if (exists) throw Object.assign(new Error("PHONE_EXISTS"), { status: 409 });

  const pinHash = await hashPin(dto.pin);
  const user = await createUser({
    fullName: dto.fullName,
    phone: dto.phone,
    pinHash,
    block: dto.block,
    buildingNumber: dto.buildingNumber,
    apartment: dto.apartment,
  });

  const token = signAccessToken({ sub: user.id });
  return { token, user: mapUser(user) };
}

export async function login({ phone, pin }) {
  const user = await findUserByPhone(phone);
  if (!user) throw Object.assign(new Error("INVALID_CREDENTIALS"), { status: 401 });

  const ok = await verifyPin(pin, user.pin_hash);
  if (!ok) throw Object.assign(new Error("INVALID_CREDENTIALS"), { status: 401 });

  const token = signAccessToken({ sub: user.id });
  return {
    token,
    user: {
      id: user.id,
      fullName: user.full_name,
      phone: user.phone,
      block: user.block,
      buildingNumber: user.building_number,
      apartment: user.apartment,
    }
  };
}

function mapUser(u) {
  return {
    id: u.id,
    fullName: u.full_name,
    phone: u.phone,
    block: u.block,
    buildingNumber: u.building_number,
    apartment: u.apartment,
  };
}