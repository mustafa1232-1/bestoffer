// src/modules/auth/auth.repo.js
import { q } from "../../config/db.js";

export async function findUserByPhone(phone) {
  const r = await q(`SELECT * FROM app_user WHERE phone=$1`, [phone]);
  return r.rows[0] || null;
}

export async function createUser({ fullName, phone, pinHash, block, buildingNumber, apartment }) {
  const r = await q(
    `INSERT INTO app_user (full_name, phone, pin_hash, block, building_number, apartment)
     VALUES ($1,$2,$3,$4,$5,$6)
     RETURNING id, full_name, phone, block, building_number, apartment`,
    [fullName, phone, pinHash, block, buildingNumber, apartment]
  );
  return r.rows[0];
}

export async function getUserPublicById(id) {
  const r = await q(
    `SELECT id, full_name, phone, block, building_number, apartment
     FROM app_user WHERE id=$1`,
    [id]
  );
  return r.rows[0] || null;
}