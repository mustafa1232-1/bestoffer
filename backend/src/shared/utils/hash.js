// src/shared/utils/hash.js
import bcrypt from "bcryptjs";
export const hashPin = async (pin) => bcrypt.hash(pin, 10);
export const verifyPin = async (pin, hash) => bcrypt.compare(pin, hash);