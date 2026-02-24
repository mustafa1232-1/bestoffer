import { Router } from "express";
import * as c from "./auth.controller.js";
import { imageUpload } from "../../shared/utils/upload.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";

export const authRouter = Router();

authRouter.post("/register", imageUpload.single("imageFile"), c.register);
authRouter.post("/login", c.login);
authRouter.patch("/account", requireAuth, c.updateAccount);
authRouter.get("/account/addresses", requireAuth, c.listAddresses);
authRouter.post("/account/addresses", requireAuth, c.createAddress);
authRouter.put("/account/addresses/:addressId", requireAuth, c.updateAddress);
authRouter.patch(
  "/account/addresses/:addressId/default",
  requireAuth,
  c.setDefaultAddress
);
authRouter.delete("/account/addresses/:addressId", requireAuth, c.deleteAddress);
