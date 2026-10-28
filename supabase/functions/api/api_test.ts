import { createClient } from "@supabase/supabase-js";
import { createHandler } from "./index.ts";
import { expandSlots, type Row } from "./data.ts";
import { ApiError, createBookingArgs, normalizePath } from "./http.ts";
import { managementBody, managementRoute } from "./management.ts";
import { userReport } from "./reports.ts";

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  );
}

const profile = {
  id: 7,
  role_id: 2,
  name: "Seller",
  email: "seller@example.test",
  color: "#112233",
  bus_id: 1,
  app_roles: { name: "Продавец" },
  bus: { id: 1, number: "A" },
};
const excursion = {
  id: 1,
  title: "Tour",
  description: null,
  schedule_template_id: 1,
  direction: "east",
  is_active: true,
  max_seats: 10,
  price: 100,
};
const booking = {
  id: 9,
  excursion_id: 1,
  bus_seat_id: 1,
  booked_by: 7,
  excursion_date: "2026-10-28",
  weekday: 3,
  time: "12:00:00",
  price: 100,
  debt: 0,
  stop_id: 1,
  customer_name: "Customer",
  customer_phone: "123",
  passenger_type: "adult",
  booked_at: "2026-10-27T10:00:00Z",
  excursion,
  bus_seat: { id: 1, seat_number: 1 },
  stop: { id: 1, name: "Stop", order: 1 },
  owner: { id: 7, name: "Seller", color: "#112233" },
};

type Call = {
  url: URL;
  method: string;
  authorization: string | null;
  body: Row | null;
};
function fixture(
  options: {
    role?: number;
    authFails?: boolean;
    rpcError?: string;
    origins?: string;
    pageCap?: number;
    rpcData?: Row;
    tables?: Record<string, Row[]>;
  } = {},
) {
  const calls: Call[] = [];
  const caller = { ...profile, role_id: options.role ?? 2 };
  const tables: Record<string, Row[]> = {
    profiles: [caller],
    app_roles: [{ id: 2, name: "Продавец" }],
    excursions: [excursion],
    schedule_templates: [{ id: 1, title: "Weekly", description: null }],
    schedule_days: [{
      id: 1,
      schedule_template_id: 1,
      weekday: 3,
      time: "12:00:00",
    }],
    stops: [{ id: 1, name: "First", order: 1 }, {
      id: 2,
      name: "Second",
      order: 2,
    }],
    bus_seats: [{ id: 1, excursion_id: 1, seat_number: 1, status: "booked" }, {
      id: 2,
      excursion_id: 1,
      seat_number: 2,
      status: "booked",
    }, { id: 3, excursion_id: 1, seat_number: 3, status: "available" }],
    bookings: [booking],
    wallet_transactions: [{ id: 1, user_id: 7, amount: 100 }, {
      id: 2,
      user_id: 7,
      amount: -20,
    }],
    buses: [{ id: 1, number: "A", capacity: 10, is_active: true }],
    excursion_photos: [{
      id: 1,
      excursion_id: 1,
      storage_path: "tour/a.jpg",
      title: "Photo",
      sort_order: 0,
      is_active: true,
    }],
    ...options.tables,
  };
  const mockFetch: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const rawBody = await request.text();
    const body = rawBody ? JSON.parse(rawBody) : null;
    calls.push({
      url,
      method: request.method,
      authorization: request.headers.get("authorization"),
      body,
    });
    const response = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (url.pathname === "/auth/v1/user") {
      return options.authFails
        ? response({ message: "bad jwt" }, 401)
        : response({
          id: "11111111-1111-4111-8111-111111111111",
          email: caller.email,
        });
    }
    if (url.pathname === "/auth/v1/logout") {
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/auth/v1/token") {
      return response({
        access_token: "login-jwt",
        refresh_token: "refresh-test",
        token_type: "bearer",
        expires_in: 3600,
        user: {
          id: "11111111-1111-4111-8111-111111111111",
          email: caller.email,
        },
      });
    }
    if (url.pathname.includes("/auth/v1/admin/users")) {
      return response({ user: { id: "created-auth" } });
    }
    if (url.pathname.includes("/storage/v1/object/sign/")) {
      return response({
        signedURL: "/object/sign/excursion-photos/tour/a.jpg?token=signed",
      });
    }
    if (url.pathname.includes("/rpc/")) {
      if (options.rpcError) {
        return response({
          code: options.rpcError,
          message: "sensitive SQL details",
        }, 400);
      }
      if (url.pathname.endsWith("/begin_identity_operation")) {
        return response({
          operation_id: "op",
          target_id: 8,
          auth_user_id: "22222222-2222-4222-8222-222222222222",
          result: options.rpcData ?? { message: "Saved", user: { id: 8 } },
        });
      }
      if (url.pathname.endsWith("/identity_auth_email")) {
        return response("user@test.local");
      }
      if (url.pathname.endsWith("/resolve_auth_login_email")) {
        return response(caller.email);
      }
      if (url.pathname.endsWith("/finish_identity_operation")) {
        return response({ message: "Completed" });
      }
      if (options.rpcData) return response(options.rpcData);
      if (url.pathname.endsWith("/create_bookings")) {
        return response({ bookings: [booking] });
      }
      if (url.pathname.endsWith("/update_booking")) return response(booking);
      if (url.pathname.endsWith("/cancel_booking")) {
        return response({ cancelled_booking_id: 9 });
      }
      throw new Error("Unexpected RPC");
    }
    const table = url.pathname.split("/").at(-1)!;
    let result = tables[table] ?? [];
    for (const [key, value] of url.searchParams) {
      if (key === "auth_user_id") {
        result = result.filter((r) => r.id === 7);
      } else if (value.startsWith("eq.")) {
        result = result.filter((r) => String(r[key]) === value.slice(3));
      }
    }
    if (options.pageCap) {
      const offset = Number(url.searchParams.get("offset") ?? 0);
      const page = result.slice(offset, offset + options.pageCap);
      return new Response(JSON.stringify(page), {
        headers: {
          "content-type": "application/json",
          "content-range": `${offset}-${
            offset + page.length - 1
          }/${result.length}`,
        },
      });
    }
    return response(result);
  };
  const client: typeof createClient = (url, key, options) =>
    createClient(url, key, {
      ...options,
      global: { ...options?.global, fetch: mockFetch },
    });
  const handler = createHandler({
    env: (
      name,
    ) => ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "public-anon-key",
      SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
      API_ALLOWED_ORIGINS: options.origins,
    }[name]),
    client,
    now: () => new Date("2026-10-28T06:00:00Z"),
  });
  const request = async (
    path: string,
    method = "GET",
    body?: unknown,
    authenticated = true,
    extra: HeadersInit = {},
  ) => {
    const headers = new Headers(extra);
    if (authenticated) headers.set("authorization", "Bearer user-jwt");
    if (body !== undefined) headers.set("content-type", "application/json");
    const response = await handler(
      new Request(`https://local.test${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
    );
    return {
      response,
      body: response.status === 204
        ? null
        : response.headers.get("content-type")?.includes("application/pdf")
        ? new Uint8Array(await response.arrayBuffer())
        : await response.json(),
    };
  };
  return { calls, request, handler };
}

Deno.test("mount normalization preserves resource boundaries", () => {
  for (
    const path of [
      "/functions/v1/api/api/excursions",
      "/functions/v1/api/excursions",
      "/api/excursions",
      "/excursions/",
    ]
  ) equal(normalizePath(path), "/excursions");
  equal(normalizePath("/apiary/foo"), "/apiary/foo");
  equal(normalizePath("/foo/api/bar"), "/foo/api/bar");
  for (
    const path of ["/api//bookings", "/api/bookings%2f9", "/api/\\bookings"]
  ) {
    let rejected = false;
    try {
      normalizePath(path);
    } catch (error) {
      rejected = error instanceof ApiError;
    }
    assert(rejected, path);
  }
});

Deno.test("runtime function mount and legacy api prefix are both removed", () => {
  equal(normalizePath("/api/api/app"), "/app");
  equal(normalizePath("/functions/v1/api/api/app"), "/app");
});

Deno.test("CORS preflight is public and protected routes authenticate", async () => {
  const f = fixture();
  const preflight = await f.request(
    "/functions/v1/api/api/bookings",
    "OPTIONS",
    undefined,
    false,
    { origin: "https://app.test" },
  );
  equal(preflight.response.status, 204);
  equal(preflight.response.headers.get("access-control-allow-origin"), "*");
  equal(f.calls.length, 0);
  const missing = await f.request("/api/bookings", "GET", undefined, false);
  equal(missing.response.status, 401);
  equal(missing.body.error.code, "unauthenticated");
  equal(missing.response.headers.get("cache-control"), "no-store");
  const invalid = await fixture({ authFails: true }).request("/api/auth/me");
  equal(invalid.response.status, 401);
  const denied = await fixture({ origins: "https://allowed.test" }).request(
    "/api/app",
    "GET",
    undefined,
    false,
    { origin: "https://other.test" },
  );
  equal(denied.response.status, 403);
});

Deno.test("all database requests preserve caller authorization and auth/me shape", async () => {
  const f = fixture();
  const { response, body } = await f.request("/functions/v1/api/api/auth/me");
  equal(response.status, 200);
  equal(body.user.id, 7);
  equal(body.user.role, "Продавец");
  equal(body.user.is_super_user, false);
  assert(!("auth_user_id" in body.user));
  assert(!("password" in body.user));
  assert(f.calls.length >= 2);
  for (const call of f.calls) equal(call.authorization, "Bearer user-jwt");
});

Deno.test("public schedule, stops and app return their specific envelopes", async () => {
  const f = fixture();
  const schedule = await f.request("/api/schedule", "GET", undefined, false);
  equal(schedule.response.status, 200);
  equal(schedule.body.data[0].description, "");
  equal(schedule.body.data[0].schedule[0], {
    day_number: 3,
    day_name: "Среда",
    time: "12:00",
  });
  const stops = await f.request("/api/stops", "GET", undefined, false);
  equal(stops.body.stops.map((s: Row) => s.id), [1, 2]);
  const app = await f.request("/api/app", "GET", undefined, false);
  equal(app.body.data.authentication, "supabase");
});

Deno.test("occurrences keep date-specific bookings and signal incomplete seller occupancy", async () => {
  const f = fixture();
  const result = await f.request("/api/excursions?date=2026-10-28&time=12:00");
  equal(result.response.status, 200);
  equal(result.body.data.length, 1);
  const row = result.body.data[0];
  equal(row.date_time, "2026-10-28T12:00:00+03:00");
  equal(row.occupancy_complete, false);
  equal(row.available_seats_count, null);
  equal(row.bus_seats.map((s: Row) => s.status), [
    "booked",
    "reserved",
    "available",
  ]);
  equal(row.bus_seats[0].booking.customer_name, "Customer");
  equal(row.bus_seats[1].booking, undefined);
  const nextSlot = await f.request(
    "/api/excursions/1?date=2026-11-04&time=12:00",
  );
  equal(nextSlot.body.data.bus_seats[0].status, "reserved");
  equal(nextSlot.body.data.bus_seats[0].booking, undefined);
  const admin = await fixture({ role: 1 }).request(
    "/api/excursions/1?date=2026-10-28&time=12:00",
  );
  equal(admin.body.data.available_seats_count, 9);
  const publicResult = await f.request(
    "/api/excursions/1",
    "GET",
    undefined,
    false,
  );
  equal(publicResult.response.status, 200);
  equal(publicResult.body.data.bus_seats, []);
  const invalid = await f.request("/api/excursions?status=garbage");
  equal(invalid.response.status, 422);
});

Deno.test("schedule deduplicates unscheduled dates and retains cancellations", () => {
  const result = expandSlots(
    excursion,
    [{ schedule_template_id: 1, weekday: 3, time: "12:00:00" }],
    [{ id: 8, excursion_id: 1, date_time: "2026-10-28T09:00:00Z" }, {
      id: 10,
      excursion_id: 1,
      date_time: "2026-10-28T10:00:00Z",
      deleted_at: "2026-10-27",
    }],
    [{ excursion_id: 1, date_time: "2026-10-28T09:00:00Z" }],
    false,
    new Date("2026-10-28T06:00:00Z"),
  );
  const firstDay = result.filter((s) => s.date === "2026-10-28");
  equal(firstDay.length, 1);
  equal(firstDay[0].is_cancelled, true);
  equal(firstDay[0].unscheduled_date_id, 8);
});

Deno.test("bookings nest the selected occurrence, staff sees only assigned slots", async () => {
  const result = await fixture().request("/api/bookings");
  equal(
    result.body.bookings[0].excursion.date_time,
    "2026-10-28T12:00:00+03:00",
  );
  equal(result.body.bookings[0].booked_by_name, "Seller");
  equal(result.body.bookings[0].bus_seat.seat_number, 1);
  const hidden = await fixture({
    tables: { bookings: [{ ...booking, excursion: null }] },
  }).request("/api/bookings");
  equal(hidden.body.bookings[0].excursion_visible, false);
  equal(hidden.body.bookings[0].excursion.title, "Unavailable excursion");
  equal(
    hidden.body.bookings[0].excursion.date_time,
    "2026-10-28T12:00:00+03:00",
  );
  const forbidden = await fixture().request("/api/bookings/driver");
  equal(forbidden.response.status, 403);
  const staff = fixture({
    role: 3,
    tables: {
      excursion_user: [{
        id: 1,
        user_id: 7,
        excursion_id: 1,
        excursion_date: "2026-10-28",
        time: "12:00",
      }],
    },
  });
  const driver = await staff.request("/api/bookings/driver");
  equal(driver.body.bookings.length, 1);
  const stops = await staff.request("/api/excursions/1/stops");
  equal(stops.body.stops.map((s: Row) => s.id), [1]);
});

const payload = {
  excursion_id: 1,
  excursion_date: "2026-10-28",
  time: "12:00",
  stop_id: 1,
  customer_name: "Customer",
  customer_phone: "123",
  seats: [{ seat_number: 3, passenger_type: "adult", debt: 10 }],
};
Deno.test("booking creation uses RPC, merges per-seat customers and supports legacy seat_numbers", async () => {
  const f = fixture();
  const result = await f.request("/api/bookings", "POST", payload);
  equal(result.response.status, 201);
  equal(result.body.bookings[0].id, 9);
  const rpc = f.calls.find((c) =>
    c.url.pathname.endsWith("/rpc/create_bookings")
  )!;
  assert(rpc);
  equal(rpc.body!.p_weekday, 3);
  equal(rpc.body!.p_seats[0].customer_name, "Customer");
  equal(rpc.body!.p_seats[0].debt, 10);
  assert(
    !("price" in rpc.body!.p_seats[0]),
    "Missing prices must be computed by SQL",
  );
  assert(
    !f.calls.some((c) =>
      c.method !== "GET" && !c.url.pathname.includes("/rpc/")
    ),
  );
  const legacy = createBookingArgs({
    ...payload,
    seats: undefined,
    seat_numbers: [4],
    passenger_type: "child",
  });
  equal(legacy.p_seats[0].passenger_type, "child");
  const denied = await f.request("/api/bookings", "POST", {
    ...payload,
    booked_by_id: 99,
  });
  equal(denied.response.status, 403);
});

Deno.test("invalid booking input fails before writes", async () => {
  for (
    const change of [
      { excursion_date: "2026-02-30" },
      { excursion_date: null },
      { time: "24:00" },
      { weekday: 2 },
      { seats: [payload.seats[0], payload.seats[0]] },
      { seats: [{ seat_number: 3, passenger_type: "adult", price: -1 }] },
      { seats: [{ seat_number: 3, passenger_type: "invalid" }] },
      { customer_name: null },
      {
        seats: [{
          seat_number: 3,
          passenger_type: "adult",
          with_entry: "false",
        }],
      },
    ]
  ) {
    const f = fixture();
    const result = await f.request("/api/bookings", "POST", {
      ...payload,
      ...change,
    });
    equal(result.response.status, 422);
    assert(!f.calls.some((c) => c.url.pathname.includes("/rpc/")));
  }
});

Deno.test("updates and cancellation use the exact RPC contracts", async () => {
  const f = fixture();
  const updated = await f.request("/api/bookings/9", "PUT", {
    price: 120,
    debt: 20,
    comment: "",
  });
  equal(updated.response.status, 200);
  equal(f.calls.at(-1)!.body, {
    p_booking_id: 9,
    p_changes: { price: 120, debt: 20, comment: "" },
  });
  const deleted = await f.request("/api/bookings/9", "DELETE", {
    reason: "Customer cancelled",
  });
  equal(deleted.body.cancelled_booking_id, 9);
  equal(f.calls.at(-1)!.body, {
    p_booking_id: 9,
    p_reason: "Customer cancelled",
  });
  for (
    const body of [{ stop_id: null }, { booked_by: 99 }, { price: null }, {}]
  ) {
    equal(
      (await f.request("/api/bookings/9", "PUT", body)).response.status,
      422,
    );
  }
  equal(
    (await f.request("/api/bookings/9", "DELETE", { reason: " " })).response
      .status,
    422,
  );
});

Deno.test("database failures map to HTTP errors without SQL details", async () => {
  for (
    const [code, status] of [["23505", 409], ["42501", 403], ["23514", 422], [
      "P0002",
      404,
    ], ["XX000", 500]] as const
  ) {
    const result = await fixture({ rpcError: code }).request(
      "/api/bookings",
      "POST",
      payload,
    );
    equal(result.response.status, status);
    assert(!JSON.stringify(result.body).includes("sensitive SQL details"));
    assert(result.body.request_id);
  }
});

Deno.test("users, roles, buses and photos keep Flutter envelopes without secrets", async () => {
  const f = fixture({
    tables: {
      profiles: [profile, { ...profile, id: 8, email: "other@example.test" }],
    },
  });
  const users = await f.request("/api/users?per_page=100");
  equal(users.body.users[0].balance, 80);
  equal(users.body.users[1].balance, null);
  equal(users.body.users[1].balance_visible, false);
  equal(users.body.pagination.total, 2);
  equal((await f.request("/api/users/7")).body.user.id, 7);
  equal((await f.request("/api/users/999")).response.status, 404);
  equal((await f.request("/api/users/roles")).body.roles[0].name, "Продавец");
  equal((await f.request("/api/roles")).response.status, 200);
  equal(
    (await f.request("/api/buses?is_active=true&search=A")).body.buses[0]
      .capacity,
    10,
  );
  equal((await f.request("/api/buses/1")).body.bus.number, "A");
  const photos = await f.request("/api/excursions/1/photos");
  equal(photos.response.status, 200);
  assert(photos.body.data[0].image_url.includes("token=signed"));
});

Deno.test("Auth and PDF are implemented; unknown routes are 404", async () => {
  const f = fixture();
  for (
    const [method, path] of [
      ["GET", "/api/bookings/9/ticket-pdf"],
      ["POST", "/api/auth/login"],
      ["POST", "/api/auth/logout"],
    ]
  ) {
    const result = await f.request(
      path,
      method,
      path.endsWith("login")
        ? { email: profile.email, password: "password" }
        : undefined,
    );
    equal(result.response.status, 200);
  }
  equal((await f.request("/api/nonsense")).response.status, 404);
  equal((await f.request("/api/users/7/typo")).response.status, 404);
  equal((await f.request("/api/bookings", "PATCH")).response.status, 405);
});

Deno.test("ticket PDF checks every requested owner and URL resource before rendering", async () => {
  const hidden = {
    ...booking,
    id: 10,
    booked_by: 99,
    customer_name: "Private Other Customer",
  };
  const f = fixture({ tables: { bookings: [booking, hidden] } });
  for (
    const path of [
      "/api/bookings/9/ticket-pdf?ids[]=9&ids[]=10",
      "/api/bookings/10/ticket-pdf?ids[]=9",
      "/api/bookings/9/ticket-pdf?ids[]=999",
    ]
  ) {
    const r = await f.request(path);
    equal(r.response.status, 404);
    assert(!JSON.stringify(r.body).includes(hidden.customer_name));
  }
  const valid = await f.request("/api/bookings/9/ticket-pdf?ids[]=9&ids[]=9");
  equal(valid.response.status, 200);
  equal(valid.response.headers.get("content-type"), "application/pdf");
  equal(
    valid.response.headers.get("content-disposition"),
    'attachment; filename="ticket-9.pdf"',
  );
  equal(valid.response.headers.get("cache-control"), "no-store");
  equal(new TextDecoder().decode(valid.body.slice(0, 5)), "%PDF-");
  equal(
    (await f.request("/api/bookings/9/ticket-pdf", "HEAD")).response.status,
    200,
  );
  equal(
    (await f.request("/api/bookings/9/ticket-pdf", "GET", undefined, false))
      .response.status,
    401,
  );
  const admin = fixture({ role: 1, tables: { bookings: [booking, hidden] } });
  equal(
    (await admin.request("/api/bookings/9/ticket-pdf?ids[]=9&ids[]=10"))
      .response.status,
    200,
  );
});

Deno.test("user DELETE accepts Flutter's request without a JSON body", async () => {
  const f = fixture({ role: 1, rpcData: { message: "Deleted" } });
  const result = await f.request("/api/users/8", "DELETE");
  equal(result.response.status, 200);
  equal(result.body.message, "Deleted");
});

const tariffs = Object.fromEntries(
  ["adult", "child", "senior", "disabled", "special", "concession"].map(
    (t) => [t, {
      price: 100,
      price_with_entry: null,
      seller_commission_percent: 10,
      partner_commission_percent: 20,
    }],
  ),
);
const mutationCases: [string, string, Row, string, string][] = [
  [
    "POST",
    "/excursions",
    { schedule_template_id: 1, title: "Tour", price: 100, max_seats: 10 },
    "manage_excursion",
    "create",
  ],
  ["PUT", "/excursions/1", { title: "New" }, "manage_excursion", "update"],
  ["DELETE", "/excursions/1", {}, "manage_excursion", "delete"],
  [
    "PUT",
    "/excursions/1/prices",
    { prices: tariffs },
    "manage_excursion",
    "prices",
  ],
  [
    "PUT",
    "/excursions/1/staff-prices",
    {
      staff_prices: [{
        staff_type: "driver",
        min_passengers: 0,
        max_passengers: null,
        price: 30,
      }],
    },
    "manage_excursion",
    "staff-prices",
  ],
  [
    "PUT",
    "/excursions/1/actual-amount",
    { actual_amount: null },
    "manage_excursion",
    "actual-amount",
  ],
  [
    "POST",
    "/excursions/1/unscheduled-date",
    { date_time: "2026-11-01T12:00:00+03:00" },
    "manage_excursion",
    "unscheduled-date",
  ],
  [
    "DELETE",
    "/excursions/1/unscheduled-date/2",
    {},
    "manage_excursion",
    "delete-unscheduled-date",
  ],
  [
    "POST",
    "/excursions/1/cancel-date",
    { date_time: "2026-11-01T12:00:00+03:00" },
    "manage_excursion",
    "cancel-date",
  ],
  [
    "DELETE",
    "/excursions/1/cancel-date/2",
    {},
    "manage_excursion",
    "restore-date",
  ],
  [
    "POST",
    "/excursions/1/assign",
    {
      assignments: [],
      excursion_date: "2026-11-01",
      time: "12:00",
      slot_max_seats: null,
    },
    "manage_excursion",
    "assign",
  ],
  ["DELETE", "/excursions/1/assign/2", {}, "manage_excursion", "unassign"],
  ["POST", "/buses", { number: "A", capacity: 10 }, "manage_bus", "create"],
  [
    "PUT",
    "/buses/1",
    { number: "B", capacity: 10, is_active: false },
    "manage_bus",
    "update",
  ],
  ["DELETE", "/buses/1", {}, "manage_bus", "delete"],
  [
    "POST",
    "/buses/1/assign-driver",
    { driver_id: 2 },
    "manage_bus",
    "assign-driver",
  ],
  [
    "POST",
    "/buses/1/unassign-driver",
    { driver_id: 2 },
    "manage_bus",
    "unassign-driver",
  ],
  [
    "POST",
    "/buses/1/assign-excursion",
    {
      excursion_id: 1,
      driver_id: 2,
      excursion_date: "2026-11-01",
      time: "12:00",
    },
    "manage_bus",
    "assign-excursion",
  ],
  [
    "POST",
    "/buses/1/unassign-excursion",
    { excursion_id: 1, excursion_date: "2026-11-01", time: "12:00" },
    "manage_bus",
    "unassign-excursion",
  ],
  [
    "POST",
    "/users",
    {
      name: "New user",
      email: "new@example.test",
      role_id: 2,
      password: "StrongPass1!",
    },
    "manage_user",
    "create",
  ],
  ["PUT", "/users/7", { name: "Updated" }, "manage_user", "update"],
  ["PUT", "/users/7/color", { color: "" }, "manage_user", "color"],
  ["DELETE", "/users/7", {}, "manage_user", "delete"],
  [
    "POST",
    "/seat-permissions",
    {
      excursion_id: 1,
      user_id: 7,
      excursion_date: "2026-11-01",
      seat_number: 1,
    },
    "manage_seat_access",
    "permission",
  ],
  [
    "DELETE",
    "/seat-permissions/1",
    {},
    "manage_seat_access",
    "delete-permission",
  ],
  [
    "POST",
    "/seat-access-requests",
    {
      excursion_id: 1,
      excursion_date: "2026-11-01",
      seat_number: 2,
      reason: "Access",
    },
    "manage_seat_access",
    "request",
  ],
  [
    "POST",
    "/seat-access-requests/1/approve",
    {},
    "manage_seat_access",
    "approve",
  ],
  [
    "POST",
    "/seat-access-requests/1/reject",
    {},
    "manage_seat_access",
    "reject",
  ],
  [
    "POST",
    "/settlements",
    { seller_id: 7, booking_ids: [9], notes: "Sheet" },
    "manage_settlement",
    "create",
  ],
  ["DELETE", "/settlements/1", {}, "manage_settlement", "delete"],
  [
    "POST",
    "/settlements/1/remove-booking",
    { booking_id: 9 },
    "manage_settlement",
    "remove-booking",
  ],
];
for (const [method, path, payload, rpc, action] of mutationCases) {
  Deno.test(`management contract ${method} ${path}`, async () => {
    const f = fixture({
      role: 1,
      rpcData: {
        message: "Saved",
        data: { id: 1 },
        user: { id: 7 },
        bus: { id: 1 },
        settlement: { id: 1 },
        request: { id: 1 },
        permission: { id: 1 },
      },
    });
    const op = managementRoute(method, path)!;
    assert(op);
    equal(op.rpc, rpc);
    equal(op.action, action);
    const result = await f.request(`/api${path}`, method, payload);
    equal(result.response.status, op.created ? 201 : 200);
    equal(result.body.message, "Saved");
    const identity = rpc === "manage_user" && action !== "color";
    const call = f.calls.find((c) =>
      c.url.pathname.endsWith(
        `/rpc/${identity ? "begin_identity_operation" : rpc}`,
      )
    )!;
    assert(call);
    equal(call.authorization, "Bearer user-jwt");
    equal(call.body!.action, action);
    equal(call.body!.target_id, op.id ?? null);
    assert(
      !f.calls.some((c) =>
        c.method !== "GET" && !c.url.pathname.includes("/rpc/") &&
        !(identity && c.url.pathname.includes("/auth/v1/admin/users"))
      ),
    );
    equal(
      (await fixture().request(`/api${path}`, method, payload, false)).response
        .status,
      401,
    );
  });
}

Deno.test("invalid management values never reach RPC", async () => {
  const bad: [string, string, Row][] = [
    ["POST", "/users", { name: "User", email: "bad", role_id: 1 }],
    ["PUT", "/users/7/color", { color: "red" }],
    ["PUT", "/users/7", { auth_user_id: "forged" }],
    ["POST", "/users", {
      name: "User",
      email: "x@y.test",
      role_id: 2,
      password: "bad\npass",
    }],
    ["POST", "/excursions", { title: "Tour", price: -1, max_seats: 101 }],
    ["PUT", "/excursions/1/staff-prices", {
      staff_prices: [{
        staff_type: "driver",
        min_passengers: 10,
        max_passengers: 2,
        price: 20,
      }],
    }],
    ["POST", "/excursions/1/assign", {
      assignments: [{ user_id: 2, role_in_excursion: "admin" }],
    }],
    ["POST", "/settlements", { seller_id: 7, booking_ids: [1, 1] }],
    ["POST", "/seat-access-requests", {
      excursion_id: 1,
      excursion_date: "2026-02-30",
      seat_number: 2,
    }],
    ["POST", "/seat-access-requests", {
      excursion_id: 1,
      excursion_date: "2026-11-01",
      seat_number: 3,
    }],
    ["POST", "/seat-access-requests", {
      excursion_id: 1,
      excursion_date: "2026-11-01",
      seat_number: 1,
      user_id: 123,
    }],
  ];
  for (const [method, path, b] of bad) {
    const f = fixture({ role: 1 });
    equal((await f.request(`/api${path}`, method, b)).response.status, 422);
    assert(!f.calls.some((c) => c.url.pathname.includes("/rpc/")));
  }
});

Deno.test("every production inventory route has an implementation", async () => {
  const inventory = await Deno.readTextFile(
    new URL("../../../docs/laravel-api-endpoints.tsv", import.meta.url),
  );
  const development = new Set([
    "/api/test",
    "/api/roles-test",
    "/api/test-ids-parsing",
    "/api/test-seating-data",
  ]);
  const f = fixture({
    role: 1,
    rpcData: {
      user: { ...profile, is_partner: false },
      bookings: [],
      transactions: [],
      prices: [],
      staff_prices: [],
      assignments: [],
      staff_slots: [],
    },
  });
  for (const line of inventory.trim().split("\n")) {
    const [verbs, raw] = line.split("\t");
    if (development.has(raw)) continue;
    const path = raw.replace(/\{[^}]+\}/g, "1").replace(
      /^\/api\/users\/1(?=\/|$)/,
      "/api/users/7",
    ).replace(/^\/api\/bookings\/1(?=\/|$)/, "/api/bookings/9");
    const method = verbs.split("|")[0];
    const mutation = mutationCases.find(([m, p]) =>
      m === method &&
      p.replace(/\d+/g, "7") === path.slice(4).replace(/\d+/g, "7")
    );
    const result = await f.request(
      path,
      method,
      mutation?.[2] ??
        (raw.endsWith("login")
          ? { email: profile.email, password: "password" }
          : undefined),
    );
    assert(
      ![404, 500, 501].includes(result.response.status),
      `${method} ${raw}: ${result.response.status}`,
    );
  }
});

Deno.test("financial envelopes use per-ticket rounding, partner rates and automatic guide", () => {
  const c = {
    user: { id: 7, is_partner: true },
    bookings: [{
      ...booking,
      resolved_date_time: "2026-11-01T12:00:00+03:00",
      price: 101,
    }],
    transactions: [{ amount: 81, booking_id: 9 }],
    prices: [{
      excursion_id: 1,
      passenger_type: "adult",
      partner_commission_percent: 12.5,
    }],
    assignments: [{
      user_id: 7,
      excursion_id: 1,
      role_in_excursion: "driver",
      excursion_date: "2026-11-01",
      time: "12:00",
      manual_amount: 999,
    }],
    staff_slots: [{
      excursion_id: 1,
      excursion_date: "2026-11-01",
      time: "12:00",
      passenger_count: 1,
      total_revenue: 101,
    }],
    staff_prices: [{
      excursion_id: 1,
      staff_type: "driver",
      min_passengers: 1,
      max_passengers: null,
      price: 50,
    }, {
      excursion_id: 1,
      staff_type: "guide",
      min_passengers: 0,
      max_passengers: 10,
      price: 20,
    }],
  };
  equal(userReport(c, "wallet").balance, 81);
  equal(userReport(c, "sales").total_sales, 101);
  equal(userReport(c, "profit").total_profit, 12.63);
  const staff = userReport(c, "staff-profit");
  equal(staff.total_profit, 70);
  equal(staff.breakdown[1].is_auto_guide_from_driver, true);
  c.assignments.push({
    ...c.assignments[0],
    user_id: 8,
    role_in_excursion: "guide",
  });
  equal(userReport(c, "staff-profit").total_profit, 50);
});

Deno.test("report authorization and admin permission feeds reject unauthorized callers", async () => {
  for (
    const path of [
      "/users/8/wallet",
      "/users/8/sales",
      "/users/8/profit",
      "/users/8/staff-profit",
      "/seat-permissions",
      "/seat-access-requests",
      "/excursions/statistics",
      "/excursions/cancelled-dates",
      "/settlements/seller/8",
    ]
  ) {
    const f = fixture();
    equal((await f.request(`/api${path}`)).response.status, 403);
    assert(!f.calls.some((c) => c.url.pathname.includes("/rpc/")));
  }
});

Deno.test("management SQL failures retain safe error envelopes", async () => {
  equal(
    managementBody({ rpc: "manage_user", action: "color" }, { color: "" }),
    { color: null },
  );
  for (
    const [code, status] of [["42501", 403], ["P0002", 404], ["23505", 409], [
      "23514",
      422,
    ], ["22023", 422]] as const
  ) {
    const f = fixture({ rpcError: code });
    const r = await f.request("/api/settlements", "POST", {
      seller_id: 7,
      booking_ids: [9],
    });
    equal(r.response.status, status);
    assert(!JSON.stringify(r.body).includes("sensitive SQL"));
  }
});

Deno.test("settlement read envelopes include period statistics and mixed calendar status", async () => {
  const b1 = {
    ...booking,
    resolved_date_time: "2026-11-01T12:00:00+03:00",
    excursion_date: "2026-11-01",
  };
  const b2 = { ...b1, id: 10, price: 50 };
  const sheet = {
    id: 2,
    seller_id: 7,
    total_amount: 100,
    settlement_date: "2026-11-02",
    created_at: "2026-11-02T10:00:00Z",
    seller: { id: 7, name: "Seller", email: profile.email },
    settlement_booking: [{ booking_id: 9 }],
  };
  const f = fixture({
    rpcData: {
      user: { ...profile, is_partner: false },
      bookings: [b1, b2],
      transactions: [],
      prices: [],
      assignments: [],
      staff_slots: [],
      staff_prices: [],
    },
    tables: { settlements: [sheet] },
  });
  const sales = await f.request(
    "/api/settlements/sellers/7/sales?date_from=2026-11-01&date_to=2026-11-01",
  );
  equal(sales.response.status, 200);
  equal(sales.body.total_amount, 50);
  equal(sales.body.sales[0].id, 10);
  equal(sales.body.period_stats, {
    total_sales: 150,
    settled_sales: 100,
    unsettled_sales: 50,
    total_count: 2,
    settled_count: 1,
    unsettled_count: 1,
  });
  const settled = await f.request(
    "/api/settlements/sellers/7/sales?settled=true",
  );
  equal(settled.body.sales[0].settlement, {
    id: 2,
    settlement_date: "2026-11-02",
    total_amount: 100,
  });
  equal(
    (await f.request("/api/settlements/sellers/7/calendar-status")).body
      .days_status,
    { "2026-11-01": "partial" },
  );
  const list = await f.request("/api/settlements/seller/7");
  equal(list.body.settlements[0].bookings_count, 1);
  assert(!("settlement_booking" in list.body.settlements[0]));
});

Deno.test("excursion mutation renders the transaction snapshot without post-commit reads", async () => {
  const f = fixture({
    role: 1,
    rpcData: {
      message: "Updated",
      data: {
        ...excursion,
        __schedule_days: [{
          schedule_template_id: 1,
          weekday: 3,
          time: "12:00:00",
        }],
        __cancelled_dates: [],
        unscheduled_dates: [],
        assigned_staff: [{ id: 3, name: "Driver", email: "driver@test.local" }],
        bus_assignments: [],
      },
    },
  });
  const result = await f.request("/api/excursions/1/actual-amount", "PUT", {
    actual_amount: 1,
  });
  equal(result.response.status, 200);
  equal(result.body.data.schedule[0], {
    weekday: 3,
    weekday_name: "Среда",
    time: "12:00",
  });
  assert(result.body.data.schedule_by_date.length > 0);
  assert(!("__schedule_days" in result.body.data));
  const rpcIndex = f.calls.findIndex((c) =>
    c.url.pathname.endsWith("/rpc/manage_excursion")
  );
  equal(f.calls.length, rpcIndex + 1);
});

Deno.test("permission checks, own requests and assignment feeds preserve filters and envelopes", async () => {
  const f = fixture({
    tables: {
      seat_permissions: [{
        id: 1,
        user_id: 7,
        excursion_id: 1,
        excursion_date: "2026-11-01",
        seat_number: 2,
      }],
      seat_access_requests: [{ id: 1, user_id: 7, status: "pending" }],
      excursion_user: [{
        id: 1,
        user_id: 7,
        excursion_id: 1,
        role_in_excursion: "driver",
        created_at: "2026-10-28T12:00:00Z",
        excursion,
      }],
    },
  });
  const check = await f.request(
    "/api/seat-permissions/check?excursion_id=1&excursion_date=2026-11-01&user_id=8",
  );
  equal(check.body, {
    has_permission_for_seat_1: false,
    has_permission_for_seat_2: true,
    permissions: [2],
  });
  equal(
    (await f.request("/api/seat-access-requests/my")).body.requests.length,
    1,
  );
  const feed = await f.request(
    "/api/excursions/check-new-assignments?last_checked=2026-10-28T11:00:00Z",
  );
  equal(feed.body.count, 1);
  equal(feed.body.assignments[0].title, "Tour");
  equal(
    (await f.request(
      "/api/excursions/check-new-assignments?last_checked=2026-10-28T13:00:00Z",
    )).body.has_new,
    false,
  );
});

Deno.test("HEAD has GET status and headers with no response body", async () => {
  const f = fixture();
  const response = await f.handler(
    new Request("https://local.test/api/stops", { method: "HEAD" }),
  );
  equal(response.status, 200);
  equal(await response.text(), "");
  assert(response.headers.get("content-type")?.includes("json"));
});

Deno.test("server row caps do not silently truncate wallet totals", async () => {
  const f = fixture({
    pageCap: 2,
    tables: {
      wallet_transactions: Array.from(
        { length: 6 },
        (_, i) => ({ id: i + 1, user_id: 7, amount: 10 }),
      ),
    },
  });
  const result = await f.request("/api/users/7");
  equal(result.response.status, 200);
  equal(result.body.user.balance, 60);
  equal(
    f.calls.filter((c) => c.url.pathname.endsWith("/wallet_transactions"))
      .length,
    3,
  );
});

Deno.test("malformed JSON, non-objects and oversized bodies are rejected", async () => {
  const f = fixture();
  for (
    const [body, contentType, expected] of [
      ["{", "application/json", 400],
      ["[]", "application/json", 422],
      ["{}", "text/plain", 415],
      ["x".repeat(65537), "application/json", 413],
    ] as const
  ) {
    const response = await f.handler(
      new Request("https://local.test/api/bookings", {
        method: "POST",
        headers: {
          authorization: "Bearer user-jwt",
          "content-type": contentType,
        },
        body,
      }),
    );
    equal(response.status, expected);
  }
});
