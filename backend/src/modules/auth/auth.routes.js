// src/modules/auth/auth.routes.js
import { Router } from "express";
import * as c from "./auth.controller.js";

export const authRouter = Router();
authRouter.post("/register", c.register);
authRouter.post("/login", c.login);