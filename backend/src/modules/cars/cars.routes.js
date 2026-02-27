import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireCustomer } from "../../shared/middleware/customer.middleware.js";
import * as c from "./cars.controller.js";

export const carsRouter = Router();

carsRouter.use(requireAuth, requireCustomer);

carsRouter.get("/brands", c.listBrands);
carsRouter.get("/models", c.listModels);
carsRouter.get("/browse", c.browse);
carsRouter.post("/smart-search", c.smartSearch);
