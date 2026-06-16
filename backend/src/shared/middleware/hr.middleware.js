import { requireRoles } from "./role.middleware.js";

export const requireHr = requireRoles("hr", "FORBIDDEN_HR_ONLY");
