// src/app.js
import express from "express";
import cors from "cors";
import { authRouter } from "./modules/auth/auth.routes.js";
import { requireAuth } from "./shared/middleware/auth.middleware.js";
import { getUserPublicById } from "./modules/auth/auth.repo.js";

export const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_, res) => res.json({ ok: true }));

app.use("/api/auth", authRouter);

app.get("/api/me", requireAuth, async (req, res) => {
  const user = await getUserPublicById(req.userId);
  res.json({ user });
});

// error handler
app.use((err, req, res, next) => {
  const status = err.status || 500;
  res.status(status).json({ message: err.message || "SERVER_ERROR" });
});