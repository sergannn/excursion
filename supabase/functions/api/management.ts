import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ApiError,
  bool,
  clockTime,
  databaseError,
  dateOnly,
  object,
  positiveInt,
  readBody,
  text,
} from "./http.ts";
import { expandSlots, hhmm, type Row, rows, weekdays } from "./data.ts";

export type Operation = {
  rpc: string;
  action: string;
  id?: number;
  child?: number;
  created?: boolean;
};

// Explicit routes, not a catch-all dispatcher: typos never invoke an RPC.
export function managementRoute(
  method: string,
  path: string,
): Operation | null {
  const roots: Record<string, string> = {
    excursions: "manage_excursion",
    buses: "manage_bus",
    users: "manage_user",
    settlements: "manage_settlement",
  };
  let m = /^\/(excursions|buses|users|settlements)(?:\/(\d+))?$/.exec(path);
  if (
    m &&
    ((method === "POST" && !m[2]) ||
      ((method === "PUT" || method === "DELETE") && m[2] &&
        (m[1] !== "settlements" || method === "DELETE")))
  ) {
    return {
      rpc: roots[m[1]],
      action: method === "POST"
        ? "create"
        : method === "PUT"
        ? "update"
        : "delete",
      id: m[2] ? positiveInt(m[2], "id") : undefined,
      created: method === "POST",
    };
  }
  m =
    /^\/excursions\/(\d+)\/(prices|staff-prices|actual-amount|unscheduled-date|cancel-date|assign)(?:\/(\d+))?$/
      .exec(path);
  if (m) {
    const mutation = ["prices", "staff-prices", "actual-amount"].includes(m[2]);
    if (
      (!m[3] && method === (mutation ? "PUT" : "POST")) ||
      (m[3] && method === "DELETE" && !mutation)
    ) {
      const action = method !== "DELETE" ? m[2] : ({
        "unscheduled-date": "delete-unscheduled-date",
        "cancel-date": "restore-date",
        assign: "unassign",
      } as Record<string, string>)[m[2]];
      return {
        rpc: "manage_excursion",
        action,
        id: positiveInt(m[1], "id"),
        child: m[3] ? positiveInt(m[3], "id") : undefined,
        created: method === "POST" && m[2] !== "assign",
      };
    }
  }
  m =
    /^\/buses\/(\d+)\/(assign-driver|unassign-driver|assign-excursion|unassign-excursion)$/
      .exec(path);
  if (m && method === "POST") {
    return {
      rpc: "manage_bus",
      action: m[2],
      id: positiveInt(m[1], "id"),
      created: m[2] === "assign-excursion",
    };
  }
  m = /^\/users\/(\d+)\/color$/.exec(path);
  if (m && method === "PUT") {
    return { rpc: "manage_user", action: "color", id: positiveInt(m[1], "id") };
  }
  m = /^\/settlements\/(\d+)\/remove-booking$/.exec(path);
  if (m && method === "POST") {
    return {
      rpc: "manage_settlement",
      action: "remove-booking",
      id: positiveInt(m[1], "id"),
    };
  }
  if (
    method === "POST" &&
    ["/seat-permissions", "/seat-access-requests"].includes(path)
  ) {
    return {
      rpc: "manage_seat_access",
      action: path === "/seat-permissions" ? "permission" : "request",
      created: true,
    };
  }
  m = /^\/seat-permissions\/(\d+)$/.exec(path);
  if (m && method === "DELETE") {
    return {
      rpc: "manage_seat_access",
      action: "delete-permission",
      id: positiveInt(m[1], "id"),
    };
  }
  m = /^\/seat-access-requests\/(\d+)\/(approve|reject)$/.exec(path);
  if (m && method === "POST") {
    return {
      rpc: "manage_seat_access",
      action: m[2],
      id: positiveInt(m[1], "id"),
    };
  }
  return null;
}

function fields(body: Row, allowed: string[]) {
  for (const k of Object.keys(body)) {
    if (!allowed.includes(k)) {
      throw new ApiError(422, "validation_error", `Unsupported field: ${k}`);
    }
  }
}
function money(v: unknown, field: string, nullable = false): number | null {
  if (nullable && v === null) return null;
  if (
    (typeof v !== "number" && typeof v !== "string") ||
    String(v).trim() === "" || !Number.isFinite(Number(v)) || Number(v) < 0 ||
    Number(v) > 99999999.99
  ) {
    throw new ApiError(
      422,
      "validation_error",
      `${field} must be a non-negative amount`,
    );
  }
  return Number(v);
}
export function managementBody(op: Operation, value: unknown): Row {
  const b: Row = { ...object(value) };
  let allowed: string[];
  if (op.rpc === "manage_excursion") {
    const sets: Record<string, string[]> = {
      create: [
        "schedule_template_id",
        "title",
        "description",
        "direction",
        "price",
        "max_seats",
        "is_active",
      ],
      update: [
        "schedule_template_id",
        "title",
        "description",
        "direction",
        "price",
        "max_seats",
        "is_active",
      ],
      prices: ["prices"],
      "staff-prices": ["staff_prices"],
      "actual-amount": ["actual_amount"],
      "unscheduled-date": ["date_time"],
      "cancel-date": ["date_time"],
      assign: ["assignments", "excursion_date", "time", "slot_max_seats"],
    };
    allowed = sets[op.action] ?? [];
    if (op.action === "create") {
      for (const k of ["schedule_template_id", "title", "price", "max_seats"]) {
        if (!(k in b)) {
          throw new ApiError(422, "validation_error", `${k} required`);
        }
      }
    }
    if ("prices" in b) {
      const tariffs = object(b.prices);
      fields(tariffs, [
        "adult",
        "child",
        "senior",
        "disabled",
        "special",
        "concession",
      ]);
      for (
        const type of [
          "adult",
          "child",
          "senior",
          "disabled",
          "special",
          "concession",
        ]
      ) {
        const p = object(tariffs[type]);
        fields(p, [
          "price",
          "price_without_entry",
          "price_with_entry",
          "seller_commission_percent",
          "partner_commission_percent",
        ]);
        for (
          const k of [
            "price",
            "seller_commission_percent",
            "partner_commission_percent",
          ]
        ) p[k] = money(p[k], k);
        for (const k of ["price_without_entry", "price_with_entry"]) {
          if (k in p) p[k] = money(p[k], k, true);
        }
        if (
          Number(p.seller_commission_percent) > 100 ||
          Number(p.partner_commission_percent) > 100
        ) {
          throw new ApiError(
            422,
            "validation_error",
            "Commission must be 0–100",
          );
        }
      }
    }
    for (const key of ["assignments", "staff_prices"]) {
      if (key in b) {
        if (!Array.isArray(b[key])) {
          throw new ApiError(
            422,
            "validation_error",
            `${key} must be an array`,
          );
        }
        b[key] = b[key].map((v: unknown) => {
          const item = object(v);
          fields(
            item,
            key === "assignments"
              ? ["user_id", "role_in_excursion", "manual_amount"]
              : ["staff_type", "min_passengers", "max_passengers", "price"],
          );
          const role = key === "assignments"
            ? "role_in_excursion"
            : "staff_type";
          if (
            !["driver", "guide"].includes(item[role] as string)
          ) {
            throw new ApiError(422, "validation_error", "Invalid staff role");
          }
          if (key === "assignments") {
            item.user_id = positiveInt(item.user_id, "user_id");
          } else {
            item.price = money(item.price, "price");
            for (const k of ["min_passengers", "max_passengers"]) {
              if (k === "min_passengers" || item[k] != null) {
                if (
                  !Number.isSafeInteger(item[k]) || Number(item[k]) < 0
                ) {
                  throw new ApiError(
                    422,
                    "validation_error",
                    "Invalid passenger range",
                  );
                }
              }
            }
            if (
              item.max_passengers != null &&
              Number(item.max_passengers) < Number(item.min_passengers)
            ) {
              throw new ApiError(
                422,
                "validation_error",
                "Invalid passenger range",
              );
            }
          }
          if ("manual_amount" in item) {
            item.manual_amount = money(
              item.manual_amount,
              "manual_amount",
              true,
            );
          }
          return item;
        });
      }
    }
  } else if (op.rpc === "manage_bus") {
    allowed = ["create", "update"].includes(op.action)
      ? ["number", "model", "capacity", "license_plate", "is_active"]
      : op.action.endsWith("driver")
      ? ["driver_id"]
      : op.action.endsWith("excursion")
      ? ["excursion_id", "driver_id", "excursion_date", "time"]
      : [];
    if (["create", "update"].includes(op.action)) {
      b.number = text(b.number, "number");
      b.capacity = positiveInt(b.capacity, "capacity");
    }
  } else if (op.rpc === "manage_user") {
    allowed = op.action === "color"
      ? ["color"]
      : op.action === "delete"
      ? []
      : ["name", "email", "role_id", "color", "bus_id"];
    if (op.action === "create" || "name" in b) b.name = text(b.name, "name");
    if (op.action === "create" || "email" in b) {
      b.email = text(b.email, "email", 190);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(b.email)) {
        throw new ApiError(422, "validation_error", "Invalid email");
      }
    }
    if (op.action === "create") b.role_id = positiveInt(b.role_id, "role_id");
    if ("color" in b) {
      if (b.color === "") b.color = null;
      if (
        b.color !== null &&
        (typeof b.color !== "string" || !/^#[0-9a-f]{6}$/i.test(b.color))
      ) throw new ApiError(422, "validation_error", "Invalid HEX color");
    }
  } else if (op.rpc === "manage_settlement") {
    allowed = op.action === "create"
      ? ["seller_id", "booking_ids", "notes", "date_from", "date_to"]
      : op.action === "remove-booking"
      ? ["booking_id"]
      : [];
    if (op.action === "create") {
      b.seller_id = positiveInt(b.seller_id, "seller_id");
      if (!Array.isArray(b.booking_ids) || !b.booking_ids.length) {
        throw new ApiError(422, "validation_error", "booking_ids required");
      }
      b.booking_ids = b.booking_ids.map((id: unknown) =>
        positiveInt(id, "booking_id")
      );
      if (new Set(b.booking_ids).size !== b.booking_ids.length) {
        throw new ApiError(422, "validation_error", "Duplicate booking_ids");
      }
    }
    if (op.action === "remove-booking") {
      b.booking_id = positiveInt(b.booking_id, "booking_id");
    }
  } else {
    allowed = op.action === "permission"
      ? ["excursion_id", "user_id", "excursion_date", "seat_number"]
      : op.action === "request"
      ? ["excursion_id", "excursion_date", "seat_number", "reason"]
      : [];
    if (["permission", "request"].includes(op.action)) {
      b.excursion_id = positiveInt(b.excursion_id, "excursion_id");
      b.excursion_date = dateOnly(b.excursion_date);
      b.seat_number = positiveInt(b.seat_number, "seat_number", 2);
      if (op.action === "permission") {
        b.user_id = positiveInt(b.user_id, "user_id");
      }
      if (
        b.reason != null &&
        (typeof b.reason !== "string" || b.reason.length > 500)
      ) throw new ApiError(422, "validation_error", "Invalid reason");
    }
  }
  fields(b, allowed);
  for (
    const k of [
      "schedule_template_id",
      "role_id",
      "bus_id",
      "driver_id",
      "excursion_id",
      "user_id",
    ]
  ) if (k in b && b[k] !== null) b[k] = positiveInt(b[k], k);
  for (const k of ["date_from", "date_to", "excursion_date"]) {
    if (k in b && b[k] !== null) b[k] = dateOnly(b[k]);
  }
  if (b.date_from && b.date_to && b.date_from > b.date_to) {
    throw new ApiError(422, "validation_error", "Invalid date range");
  }
  if (b.time != null) b.time = clockTime(b.time);
  if (
    "date_time" in b &&
    (typeof b.date_time !== "string" ||
      !/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}/.test(b.date_time) ||
      !Number.isFinite(Date.parse(b.date_time)))
  ) throw new ApiError(422, "validation_error", "Invalid date_time");
  if ("max_seats" in b) {
    b.max_seats = positiveInt(b.max_seats, "max_seats", 100);
  }
  if (b.slot_max_seats != null) {
    b.slot_max_seats = positiveInt(b.slot_max_seats, "slot_max_seats");
  }
  for (const k of ["price", "actual_amount"]) {
    if (k in b) b[k] = money(b[k], k, k === "actual_amount");
  }
  if ("title" in b) b.title = text(b.title, "title");
  if ("direction" in b && !["east", "west"].includes(b.direction)) {
    throw new ApiError(422, "validation_error", "Invalid direction");
  }
  if ("is_active" in b) b.is_active = bool(b.is_active, "is_active");
  return b;
}

export async function runManagement(
  db: SupabaseClient,
  req: Request,
  op: Operation,
) {
  const hasBody = req.body !== null;
  const payload = managementBody(op, hasBody ? await readBody(req) : {});
  const args: Row = { action: op.action, target_id: op.id ?? null, payload };
  if (op.rpc === "manage_excursion") args.child_id = op.child ?? null;
  const { data, error } = await db.rpc(op.rpc, args);
  if (error) databaseError(error);
  if (
    op.rpc === "manage_excursion" && data?.data &&
    "__schedule_days" in data.data
  ) {
    // Render the transaction's own snapshot. Never read again after commit:
    // a later read error must not turn a successful write into a retryable 500.
    const {
      __schedule_days: days,
      __cancelled_dates: cancelled,
      ...excursion
    } = data.data;
    const extra = excursion.unscheduled_dates ?? [];
    excursion.schedule = days.map((d: Row) => ({
      weekday: d.weekday,
      weekday_name: weekdays[d.weekday],
      time: hhmm(d.time),
    }));
    excursion.weekdays = days.map((d: Row) => d.weekday);
    excursion.schedule_by_date = expandSlots(
      excursion,
      days,
      extra,
      cancelled,
      true,
      new Date(),
    );
    excursion.has_unscheduled = extra.length > 0;
    const wall = excursion.date_time
      ? new Date(Date.parse(excursion.date_time) + 3 * 3600000).toISOString()
      : null;
    excursion.date = wall?.slice(0, 10) ?? null;
    excursion.time = wall?.slice(11, 16) ?? null;
    data.data = excursion;
  }
  return data;
}

function admin(caller: Row) {
  if (caller.role_id !== 1) {
    throw new ApiError(403, "forbidden", "Administrator required");
  }
}
export async function permissionRead(
  db: SupabaseClient,
  caller: Row,
  path: string,
  query: URLSearchParams,
) {
  const permissions = path.startsWith("/seat-permissions");
  if (path === "/seat-permissions" || path === "/seat-access-requests") {
    admin(caller);
  }
  const filters: Record<string, string | number> = {};
  for (const k of ["excursion_id", "user_id"]) {
    if (query.has(k)) filters[k] = positiveInt(query.get(k), k);
  }
  if (query.has("excursion_date")) {
    filters.excursion_date = dateOnly(query.get("excursion_date"));
  }
  if (path === "/seat-permissions/check") {
    filters.excursion_id = positiveInt(
      query.get("excursion_id"),
      "excursion_id",
    );
    filters.excursion_date = dateOnly(query.get("excursion_date"));
    filters.user_id = caller.id;
  }
  if (path.endsWith("/my")) filters.user_id = caller.id;
  if (!permissions && query.has("status")) {
    const status = query.get("status")!;
    if (!["pending", "approved", "rejected"].includes(status)) {
      throw new ApiError(422, "validation_error", "Invalid status");
    }
    filters.status = status;
  }
  const data = await rows(
    db,
    permissions ? "seat_permissions" : "seat_access_requests",
    permissions
      ? "*,user:profiles!user_id(id,name,email),excursion:excursions(id,title)"
      : "*,user:profiles!user_id(id,name,email),excursion:excursions(id,title),reviewer:profiles!reviewed_by(id,name)",
    filters,
  );
  if (path.endsWith("/check")) {
    const seats = data.map((r) => r.seat_number);
    return {
      has_permission_for_seat_1: seats.includes(1),
      has_permission_for_seat_2: seats.includes(2),
      permissions: seats,
    };
  }
  return permissions
    ? { permissions: data }
    : { requests: data.sort((a, b) => b.id - a.id) };
}
