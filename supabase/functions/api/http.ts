export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

export function normalizePath(pathname: string): string {
  // Remove only complete, anchored mount segments. Never replace an arbitrary
  // occurrence of "api" inside a resource name or decode encoded separators.
  let path = pathname.replace(/\/$/, "");
  if (path === "/functions/v1/api") path = "";
  else if (path.startsWith("/functions/v1/api/")) {
    path = path.slice("/functions/v1/api".length);
  }
  // Supabase may expose the runtime pathname as /api/api/foo: the first
  // segment is the function name and the second is the legacy Laravel prefix.
  // Strip at most those two complete mount segments, never an arbitrary match.
  for (let index = 0; index < 2; index++) {
    if (path === "/api") path = "";
    else if (path.startsWith("/api/")) path = path.slice(4);
    else break;
  }
  if (/%|\\|\/\//.test(path)) {
    throw new ApiError(400, "invalid_path", "Invalid API path");
  }
  return path || "/";
}

export function positiveInt(
  value: unknown,
  field: string,
  max = Number.MAX_SAFE_INTEGER,
): number {
  if (
    (typeof value !== "number" && typeof value !== "string") ||
    !/^[1-9]\d*$/.test(String(value))
  ) {
    throw new ApiError(
      422,
      "validation_error",
      `${field} must be a positive integer`,
    );
  }
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number > max) {
    throw new ApiError(422, "validation_error", `${field} is out of range`);
  }
  return number;
}

export function bool(value: unknown, field: string): boolean {
  if (value === true || value === "true" || value === "1") return true;
  if (value === false || value === "false" || value === "0") return false;
  throw new ApiError(422, "validation_error", `${field} must be a boolean`);
}

export function text(value: unknown, field: string, max = 255): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new ApiError(
      422,
      "validation_error",
      `${field} must be a non-empty string (max ${max})`,
    );
  }
  return value.trim();
}

export function dateOnly(value: unknown): string {
  if (
    typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(Date.parse(value)) ||
    new Date(value).toISOString().slice(0, 10) !== value
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "excursion_date must be a valid YYYY-MM-DD date",
    );
  }
  return value;
}

export function clockTime(value: unknown): string {
  if (
    typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d(:00)?$/.test(value)
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "time must be HH:mm (optional :00 seconds)",
    );
  }
  return value.slice(0, 5);
}

export function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(422, "validation_error", "Expected a JSON object");
  }
  return value as Record<string, unknown>;
}

export async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (
    !/^application\/json(?:\s*;|$)/i.test(req.headers.get("content-type") ?? "")
  ) {
    throw new ApiError(
      415,
      "unsupported_media_type",
      "Content-Type must be application/json",
    );
  }
  const reader = req.body?.getReader();
  if (!reader) throw new ApiError(400, "invalid_json", "JSON body is required");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 65536) {
      await reader.cancel();
      throw new ApiError(413, "payload_too_large", "JSON body exceeds 64 KiB");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new ApiError(400, "invalid_json", "Malformed JSON body");
  }
  return object(parsed);
}

const passengerTypes = new Set([
  "adult",
  "child",
  "senior",
  "disabled",
  "special",
  "concession",
]);

export function bookingChanges(
  input: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = new Set([
    "customer_name",
    "customer_phone",
    "comment",
    "passenger_type",
    "with_entry",
    "price",
    "debt",
    "stop_id",
  ]);
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (!allowed.has(key)) {
      throw new ApiError(
        422,
        "validation_error",
        `Unsupported booking field: ${key}`,
      );
    }
    if (key === "customer_name" || key === "customer_phone") {
      result[key] = text(value, key);
    } else if (key === "comment") {
      if (
        value !== null && (typeof value !== "string" || value.length > 5000)
      ) {
        throw new ApiError(
          422,
          "validation_error",
          "comment must be a string or null (max 5000)",
        );
      }
      result[key] = value;
    } else if (key === "passenger_type") {
      if (typeof value !== "string" || !passengerTypes.has(value)) {
        throw new ApiError(
          422,
          "validation_error",
          "Unsupported passenger_type",
        );
      }
      result[key] = value;
    } else if (key === "with_entry") {
      if (typeof value !== "boolean") {
        throw new ApiError(
          422,
          "validation_error",
          "with_entry must be a boolean",
        );
      }
      result[key] = value;
    } else if (key === "stop_id") {
      // The current migration declares stop_id NOT NULL. Do not silently ignore
      // Flutter's clearStop request or send it to a guaranteed failing SQL cast.
      if (value === null) {
        throw new ApiError(
          422,
          "validation_error",
          "A stop is required by the current schema",
        );
      }
      result[key] = positiveInt(value, key);
    } else {
      if (
        typeof value !== "number" || !Number.isFinite(value) || value < 0 ||
        value > 99999999.99
      ) {
        throw new ApiError(
          422,
          "validation_error",
          `${key} must be a non-negative number within numeric(10,2)`,
        );
      }
      result[key] = value;
    }
  }
  if (
    typeof result.price === "number" && typeof result.debt === "number" &&
    result.debt > result.price
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "Debt cannot exceed ticket price",
    );
  }
  return result;
}

export function createBookingArgs(body: Record<string, unknown>) {
  const excursionDate = dateOnly(body.excursion_date);
  const weekday = new Date(excursionDate).getUTCDay() || 7;
  if (
    body.weekday != null && positiveInt(body.weekday, "weekday", 7) !== weekday
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "weekday does not match excursion_date",
    );
  }
  let seats = body.seats;
  if (seats === undefined && Array.isArray(body.seat_numbers)) {
    seats = body.seat_numbers.map((seat_number) => ({
      seat_number,
      passenger_type: body.passenger_type,
    }));
  }
  if (!Array.isArray(seats) || seats.length === 0 || seats.length > 500) {
    throw new ApiError(
      422,
      "validation_error",
      "Provide between 1 and 500 seats",
    );
  }
  const seen = new Set<number>();
  const normalized = seats.map<Record<string, unknown>>((value) => {
    const seat = object(value);
    const seatNumber = positiveInt(seat.seat_number, "seat_number");
    if (seen.has(seatNumber)) {
      throw new ApiError(422, "validation_error", "Duplicate seat_number");
    }
    seen.add(seatNumber);
    const { seat_number: _, ...changes } = seat;
    const fields = bookingChanges({
      ...changes,
      passenger_type: seat.passenger_type ?? body.passenger_type,
      customer_name: seat.customer_name ?? body.customer_name,
      customer_phone: seat.customer_phone ?? body.customer_phone,
      with_entry: seat.with_entry ?? false,
    });
    return { ...fields, seat_number: seatNumber };
  });
  return {
    p_excursion_id: positiveInt(body.excursion_id, "excursion_id"),
    p_excursion_date: excursionDate,
    p_time: clockTime(body.time),
    p_weekday: weekday,
    p_stop_id: positiveInt(body.stop_id, "stop_id"),
    p_seats: normalized,
    p_booked_by: body.booked_by_id == null
      ? null
      : positiveInt(body.booked_by_id, "booked_by_id"),
  };
}

export function databaseError(
  error: { code?: string; message?: string },
): never {
  const code = error.code ?? "";
  if (code === "42501") {
    throw new ApiError(403, "forbidden", "Insufficient permissions");
  }
  if (code === "P0002" || code === "PGRST116") {
    throw new ApiError(404, "not_found", "Resource not found or unavailable");
  }
  if (code === "23505") {
    throw new ApiError(409, "conflict", "The seat or record already exists");
  }
  if (
    ["23514", "23503", "23502", "22023", "22P02", "22007", "22008", "22003"]
      .includes(code)
  ) {
    throw new ApiError(
      422,
      "validation_error",
      "Request violates a booking or database constraint",
    );
  }
  if (code === "PGRST301" || code === "PGRST303") {
    throw new ApiError(
      401,
      "unauthenticated",
      "Invalid or expired access token",
    );
  }
  // Do not leak SQL details, row contents, hints, or internal paths to clients.
  console.error("api database failure", code);
  throw new ApiError(500, "database_error", "Database request failed");
}
