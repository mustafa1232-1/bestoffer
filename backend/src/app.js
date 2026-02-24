import cors from "cors";
import express from "express";
import path from "path";

import { adminRouter } from "./modules/admin/admin.routes.js";
import { authRouter } from "./modules/auth/auth.routes.js";
import { getUserPublicById } from "./modules/auth/auth.repo.js";
import { deliveryRouter } from "./modules/delivery/delivery.routes.js";
import { merchantsRouter } from "./modules/merchants/merchants.routes.js";
import { notificationsRouter } from "./modules/notifications/notifications.routes.js";
import { ordersRouter } from "./modules/orders/orders.routes.js";
import { ownerRouter } from "./modules/owner/owner.routes.js";
import { requireAuth } from "./shared/middleware/auth.middleware.js";

export const app = express();

app.set("trust proxy", true);

const corsOrigins = String(process.env.CORS_ORIGINS || "*")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const allowAllOrigins = corsOrigins.length === 0 || corsOrigins.includes("*");

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || allowAllOrigins || corsOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      const error = new Error("CORS_NOT_ALLOWED");
      error.status = 403;
      callback(error);
    },
  })
);
app.use(express.json({ limit: "10mb" }));
app.use((req, res, next) => {
  if (req.path.startsWith("/api/")) {
    res.setHeader("Content-Type", "application/json; charset=utf-8");
  }
  next();
});
app.use("/uploads", express.static(path.resolve(process.cwd(), "uploads")));

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.use("/api/auth", authRouter);
app.use("/api/merchants", merchantsRouter);
app.use("/api/admin", adminRouter);
app.use("/api/owner", ownerRouter);
app.use("/api/orders", ordersRouter);
app.use("/api/delivery", deliveryRouter);
app.use("/api/notifications", notificationsRouter);

app.get("/api/me", requireAuth, async (req, res, next) => {
  try {
    const user = await getUserPublicById(req.userId);
    res.json({ user });
  } catch (e) {
    next(e);
  }
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ message: err.message || "SERVER_ERROR" });
});
