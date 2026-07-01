import { Router } from "express";
import * as c from "./products.controller.js";

export const productsRouter = Router();

productsRouter.get("/:productId/summary", c.summary);
productsRouter.get("/:productId/details", c.details);
