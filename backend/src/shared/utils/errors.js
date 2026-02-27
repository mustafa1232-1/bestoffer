export class AppError extends Error {
  constructor(message, options = {}) {
    super(message || "SERVER_ERROR");
    this.name = "AppError";
    this.status = Number(options.status || 500);
    this.code = options.code || message || "SERVER_ERROR";
    this.details = options.details ?? null;
    this.expose = options.expose !== undefined ? options.expose : this.status < 500;
  }
}

export function toAppError(error, fallbackMessage = "SERVER_ERROR") {
  if (!error) return new AppError(fallbackMessage);
  if (error instanceof AppError) return error;

  const status =
    Number(error.status || error.statusCode || error.httpStatus || 500) || 500;
  const expose = error.expose !== undefined ? error.expose : status < 500;

  const appError = new AppError(error.message || fallbackMessage, {
    status,
    code: error.code || error.message || fallbackMessage,
    details: error.details || null,
    expose,
  });

  if (error.stack) appError.stack = error.stack;
  return appError;
}
