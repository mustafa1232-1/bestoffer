import { toAppError } from "../utils/errors.js";
import { verifySignedRequest } from "../../modules/security/security.service.js";

export function requireSignedRequest() {
  return async function requireSignedRequestMiddleware(req, res, next) {
    try {
      await verifySignedRequest(req);
      return next();
    } catch (error) {
      return next(toAppError(error, "REQUEST_SIGNATURE_INVALID"));
    }
  };
}
