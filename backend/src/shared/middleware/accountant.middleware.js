import { requireRoles } from "./role.middleware.js";

export const requireAccountant = requireRoles(
  ["accountant", "owner"],
  "FORBIDDEN_ACCOUNTANT_OR_OWNER_ONLY"
);
