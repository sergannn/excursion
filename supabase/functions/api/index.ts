import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { authAdmin, login, logout, manageIdentity } from "./identity.ts";
import { ticketPdf } from "./ticket.ts";
import {
  managementRoute,
  permissionRead,
  runManagement,
} from "./management.ts";
import {
  financialContext,
  settlementRead,
  statistics,
  userReport,
} from "./reports.ts";
import {
  ApiError,
  bookingChanges,
  bool,
  clockTime,
  createBookingArgs,
  databaseError,
  dateOnly,
  normalizePath,
  positiveInt,
  readBody,
  text,
} from "./http.ts";
import {
  assignedTo,
  bookingSelect,
  bookingShape,
  excursionData,
  expandSlots,
  hhmm,
  one,
  profileSelect,
  type Row,
  rows,
  userShape,
  usersWithBalances,
  weekdays,
} from "./data.ts";

type Dependencies = {
  env?: (name: string) => string | undefined;
  client?: typeof createClient;
  now?: () => Date;
};

const publicPaths = new Set(["/app", "/schedule", "/stops", "/excursions"]);
const knownRoots = new Set([
  "app",
  "auth",
  "excursions",
  "schedule",
  "stops",
  "bookings",
  "users",
  "roles",
  "buses",
  "settlements",
  "seat-permissions",
  "seat-access-requests",
]);

export function createHandler(deps: Dependencies = {}) {
  const env = deps.env ?? Deno.env.get;
  return async (req: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
      "Vary": "Origin",
      "Access-Control-Allow-Headers":
        "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
      "Access-Control-Allow-Methods": "GET, HEAD, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Expose-Headers": "x-request-id, content-disposition",
      "Access-Control-Max-Age": "86400",
    });
    const origin = req.headers.get("origin");
    const allowed = (env("API_ALLOWED_ORIGINS") ?? "*").split(",").map((s) =>
      s.trim()
    ).filter(Boolean);
    if (allowed.includes("*")) headers.set("Access-Control-Allow-Origin", "*");
    else if (origin && allowed.includes(origin)) {
      headers.set("Access-Control-Allow-Origin", origin);
    }
    const json = (body: unknown, status = 200) =>
      new Response(req.method === "HEAD" ? null : JSON.stringify(body), {
        status,
        headers,
      });
    try {
      if (origin && !allowed.includes("*") && !allowed.includes(origin)) {
        throw new ApiError(403, "origin_not_allowed", "Origin is not allowed");
      }
      if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers });
      }
      const url = new URL(req.url);
      let path = normalizePath(url.pathname);
      const method = req.method === "HEAD" ? "GET" : req.method;
      if (!["GET", "POST", "PUT", "DELETE"].includes(method)) {
        headers.set("Allow", "GET, POST, PUT, DELETE, OPTIONS");
        throw new ApiError(405, "method_not_allowed", "Method not allowed");
      }
      if (!knownRoots.has(path.split("/")[1])) {
        throw new ApiError(404, "not_found", "API route not found");
      }
      const supabaseUrl = env("SUPABASE_URL");
      const key = env("SUPABASE_ANON_KEY");
      if (!supabaseUrl || !key) {
        throw new ApiError(500, "configuration_error", "API is not configured");
      }
      // Never accept a caller-supplied apikey as the database key. Never create
      // an admin client for domain operations. Every query/RPC uses caller RLS.
      const authorization = req.headers.get("authorization");
      const db = (deps.client ?? createClient)(supabaseUrl, key, {
        global: {
          headers: authorization ? { Authorization: authorization } : {},
          fetch: (input, init) =>
            fetch(input, { ...init, signal: AbortSignal.timeout(15000) }),
        },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      });
      const publicAccess = (method === "GET" &&
        (publicPaths.has(path) || /^\/excursions\/\d+$/.test(path))) ||
        (method === "POST" && path === "/auth/login");
      let caller: Row | null = null;
      if (authorization) {
        const match = /^Bearer\s+(\S+)$/i.exec(authorization);
        if (!match) {
          throw new ApiError(
            401,
            "unauthenticated",
            "Expected a Bearer access token",
          );
        }
        const { data, error } = await db.auth.getUser(match[1]);
        if (error || !data.user) {
          throw new ApiError(
            401,
            "unauthenticated",
            "Invalid or expired access token",
          );
        }
        const { data: profile, error: profileError } = await db.from("profiles")
          .select(profileSelect).eq("auth_user_id", data.user.id).maybeSingle();
        if (profileError) databaseError(profileError);
        if (!profile) {
          throw new ApiError(
            403,
            "profile_required",
            "No application profile is linked to this user",
          );
        }
        caller = profile;
      } else if (!publicAccess) {
        throw new ApiError(401, "unauthenticated", "Authentication required");
      }
      const query = url.searchParams;

      if (method === "POST" && path === "/auth/login") {
        return json(
          await login(
            authAdmin(supabaseUrl, key, deps.client ?? createClient),
            req,
          ),
        );
      }
      if (method === "POST" && path === "/auth/logout") {
        return json(
          await logout(db, authorization!.replace(/^Bearer\s+/i, "")),
        );
      }
      const pdfMatch = /^\/bookings\/(\d+)\/ticket-pdf$/.exec(path);
      if (method === "GET" && pdfMatch) {
        const id = positiveInt(pdfMatch[1], "id");
        const pdf = await ticketPdf(db, caller!, id, query);
        headers.set("Content-Type", "application/pdf");
        headers.set(
          "Content-Disposition",
          `attachment; filename="ticket-${id}.pdf"`,
        );
        return new Response(req.method === "HEAD" ? null : pdf as BodyInit, {
          headers,
        });
      }

      const operation = managementRoute(method, path);
      if (operation) {
        const data =
          operation.rpc === "manage_user" && operation.action !== "color"
            ? await manageIdentity(db, caller!, req, operation, () => {
              const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
              if (!serviceKey) {
                throw new ApiError(
                  503,
                  "configuration_error",
                  "User administration is not configured",
                );
              }
              return authAdmin(
                supabaseUrl,
                serviceKey,
                deps.client ?? createClient,
              );
            })
            : await runManagement(db, req, operation);
        return json(data, operation.created ? 201 : 200);
      }
      if (
        method === "GET" &&
        [
          "/seat-permissions",
          "/seat-permissions/check",
          "/seat-access-requests",
          "/seat-access-requests/my",
        ].includes(path)
      ) {
        return json(await permissionRead(db, caller!, path, query));
      }
      if (
        method === "GET" &&
        /^\/settlements(?:\/seller\/\d+|\/sellers(?:\/\d+\/(?:sales|calendar-status))?)?$/
          .test(path)
      ) {
        return json(await settlementRead(db, caller!, path, query));
      }
      const reportMatch = /^\/users\/(\d+)\/(wallet|sales|profit|staff-profit)$/
        .exec(path);
      if (method === "GET" && reportMatch) {
        return json(
          userReport(
            await financialContext(
              db,
              caller!,
              positiveInt(reportMatch[1], "id"),
            ),
            reportMatch[2],
          ),
        );
      }
      if (method === "GET" && path === "/excursions/statistics") {
        return json(await statistics(db, caller!));
      }
      if (method === "GET" && path === "/excursions/cancelled-dates") {
        if (caller!.role_id !== 1) {
          throw new ApiError(403, "forbidden", "Administrator required");
        }
        const data = await rows(
          db,
          "cancelled_excursion_dates",
          "*,excursion:excursions(title)",
        );
        return json({
          data: data.sort((a, b) => b.date_time.localeCompare(a.date_time)).map(
            (r) => {
              const dt = new Date(Date.parse(r.date_time) + 3 * 3600000)
                .toISOString();
              return {
                id: r.id,
                excursion_id: r.excursion_id,
                excursion_title: r.excursion.title,
                date_time: r.date_time,
                date: dt.slice(0, 10),
                time: dt.slice(11, 16),
                created_at: r.created_at,
              };
            },
          ),
        });
      }
      if (method === "GET" && path === "/excursions/check-new-assignments") {
        const since = query.get("last_checked");
        if (since && !Number.isFinite(Date.parse(since))) {
          throw new ApiError(422, "validation_error", "Invalid last_checked");
        }
        const data = await rows(
          db,
          "excursion_user",
          "*,excursion:excursions(id,title,description,date_time)",
          { user_id: caller!.id },
        );
        const assignments = data.filter((a) =>
          !since || Date.parse(a.created_at) > Date.parse(since)
        ).sort((a, b) => b.created_at.localeCompare(a.created_at)).map((a) => ({
          excursion_id: a.excursion_id,
          title: a.excursion?.title,
          description: a.excursion?.description,
          date_time: a.excursion?.date_time,
          role_in_excursion: a.role_in_excursion,
          assigned_at: a.created_at,
        }));
        return json({
          has_new: assignments.length > 0,
          count: assignments.length,
          assignments,
        });
      }
      const assignedMatch = /^\/users\/(\d+)\/assigned-excursions$/.exec(path);
      if (method === "GET" && assignedMatch) {
        query.set("assigned_to", String(positiveInt(assignedMatch[1], "id")));
        path = "/excursions";
      }

      if (method === "GET" && path === "/app") {
        // Laravel's /app was a web redirect, not a data bootstrap. Return an
        // explicit capability document rather than inventing application data.
        return json({
          data: {
            name: "Excursion compatibility API",
            version: 1,
            authentication: "supabase",
            timezone: "Europe/Moscow",
            booking_rpc: true,
          },
        });
      }
      if (method === "GET" && path === "/auth/me") {
        return json({ user: userShape(caller!) });
      }
      if (method === "GET" && path === "/schedule") {
        const [templates, days] = await Promise.all([
          rows(db, "schedule_templates"),
          rows(db, "schedule_days"),
        ]);
        return json({
          data: templates.map((t) => ({
            ...t,
            description: t.description ?? "",
            schedule: days.filter((d) => d.schedule_template_id === t.id).sort((
              a,
              b,
            ) => a.weekday - b.weekday).map((d) => ({
              day_number: d.weekday,
              day_name: weekdays[d.weekday],
              time: hhmm(d.time),
            })),
          })),
        });
      }
      if (method === "GET" && path === "/stops") {
        return json({ stops: sortStops(await rows(db, "stops")) });
      }
      let match = /^\/excursions\/(\d+)\/(photos|stops)$/.exec(path);
      if (method === "GET" && match) {
        const id = positiveInt(match[1], "id");
        const excursion = await one(db, "excursions", id);
        if (match[2] === "photos") {
          const photos = (await rows(
            db,
            "excursion_photos",
            "id,storage_path,title,sort_order,is_active",
            { excursion_id: id },
          )).filter((p) => p.is_active);
          const signed = await Promise.all(photos.map(async (photo) => {
            const { data, error } = await db.storage.from("excursion-photos")
              .createSignedUrl(photo.storage_path, 3600);
            if (error || !data) {
              throw new ApiError(
                502,
                "photo_unavailable",
                "Unable to sign an excursion photo",
              );
            }
            return {
              id: photo.id,
              title: photo.title,
              sort_order: photo.sort_order,
              image_url: data.signedUrl,
            };
          }));
          return json({
            data: signed.sort((a, b) =>
              a.sort_order - b.sort_order || a.id - b.id
            ),
          });
        }
        let stops = await rows(db, "stops");
        if ([3, 5].includes(caller!.role_id)) {
          const assigned = await rows(db, "excursion_user", "id", {
            excursion_id: id,
            user_id: caller!.id,
          });
          if (!assigned.length) {
            throw new ApiError(
              403,
              "forbidden",
              "You are not assigned to this excursion",
            );
          }
          const bookings = await rows(db, "bookings", "id,stop_id", {
            excursion_id: id,
          });
          const ids = new Set(bookings.map((b) => b.stop_id));
          stops = stops.filter((s) => ids.has(s.id));
        }
        return json({
          stops: sortStops(stops, excursion.direction === "east"),
        });
      }
      match = /^\/excursions\/(\d+)$/.exec(path);
      if (method === "GET" && (path === "/excursions" || match)) {
        const id = match ? positiveInt(match[1], "id") : undefined;
        const status = query.get("status") ??
          (query.has("include_past") &&
              bool(query.get("include_past"), "include_past")
            ? "all"
            : "upcoming");
        if (!["all", "upcoming", "past"].includes(status)) {
          throw new ApiError(
            422,
            "validation_error",
            "status must be upcoming, past or all",
          );
        }
        const now = deps.now?.() ?? new Date();
        const data = await excursionData(db, caller, id);
        const includeDetails = query.has("include_booking_details")
          ? bool(
            query.get("include_booking_details"),
            "include_booking_details",
          )
          : true;
        const targetDate = query.has("date")
          ? dateOnly(query.get("date"))
          : null;
        const targetTime = query.has("time")
          ? clockTime(query.get("time"))
          : null;
        const weekday = query.has("weekday")
          ? positiveInt(query.get("weekday"), "weekday", 7)
          : null;
        const assignedId = query.has("assigned_to")
          ? positiveInt(query.get("assigned_to"), "assigned_to")
          : null;
        const expanded: Row[] = [];
        for (const excursion of data.excursions) {
          const scheduled = expandSlots(
            excursion,
            data.days,
            data.extra,
            data.cancelled,
            status !== "upcoming",
            now,
          );
          for (const target of scheduled) {
            const past = Date.parse(target.date_time) < now.getTime();
            if (
              (status === "upcoming" && past) || (status === "past" && !past)
            ) continue;
            if (
              targetDate && target.date !== targetDate ||
              targetTime && target.time !== targetTime ||
              weekday && target.weekday !== weekday
            ) continue;
            const staffId = caller && [3, 5].includes(caller.role_id)
              ? caller.id
              : null;
            if (
              [staffId, assignedId].some((userId) =>
                userId &&
                !data.staff.some((a) =>
                  a.excursion_id === excursion.id && a.user_id === userId &&
                  assignedTo(a, target)
                )
              )
            ) continue;
            expanded.push({
              ...data.render(excursion, target, includeDetails),
              schedule_by_date: scheduled,
            });
          }
        }
        expanded.sort((a, b) =>
          a.date_time.localeCompare(b.date_time) ||
          a.title.localeCompare(b.title)
        );
        if (id) {
          // A detail is a single slot. With no explicit slot, choose the first
          // filtered occurrence; never attach global bookings to an arbitrary day.
          if (!expanded.length) {
            throw new ApiError(
              404,
              "slot_not_found",
              "No matching excursion occurrence in the schedule window",
            );
          }
          return json({ data: expanded[0] });
        }
        return json({ data: expanded });
      }
      if (
        method === "GET" &&
        (path === "/bookings" || path === "/bookings/driver")
      ) {
        let bookings = await rows(db, "bookings", bookingSelect);
        if (path.endsWith("/driver")) {
          if (![1, 3, 5].includes(caller!.role_id)) {
            throw new ApiError(403, "forbidden", "Staff role required");
          }
          const assignments = await rows(db, "excursion_user", "*", {
            user_id: caller!.id,
          });
          bookings = bookings.filter((b) =>
            assignments.some((a) =>
              a.excursion_id === b.excursion_id &&
              assignedTo(a, { date: b.excursion_date, time: hhmm(b.time) })
            )
          );
        } else if (caller!.role_id !== 1) {
          bookings = bookings.filter((b) => b.booked_by === caller!.id);
        }
        return json({
          bookings: bookings.sort((a, b) => b.id - a.id).map(bookingShape),
        });
      }
      if (method === "POST" && path === "/bookings") {
        const args = createBookingArgs(await readBody(req));
        if (
          args.p_booked_by !== null && args.p_booked_by !== caller!.id &&
          caller!.role_id !== 1
        ) {
          throw new ApiError(
            403,
            "forbidden",
            "Only an administrator may book for another user",
          );
        }
        const { data, error } = await db.rpc("create_bookings", args);
        if (error) databaseError(error);
        return json({ message: "Bookings created", ...data }, 201);
      }
      match = /^\/bookings\/(\d+)$/.exec(path);
      if (match && (method === "PUT" || method === "DELETE")) {
        const id = positiveInt(match[1], "id");
        const body = await readBody(req);
        if (method === "PUT") {
          const changes = bookingChanges(body);
          if (!Object.keys(changes).length) {
            throw new ApiError(
              422,
              "validation_error",
              "Provide at least one booking field",
            );
          }
          const { data, error } = await db.rpc("update_booking", {
            p_booking_id: id,
            p_changes: changes,
          });
          if (error) databaseError(error);
          return json({ message: "Booking updated", booking: data });
        }
        const reason = text(body.reason, "reason", 5000);
        const { data, error } = await db.rpc("cancel_booking", {
          p_booking_id: id,
          p_reason: reason,
        });
        if (error) databaseError(error);
        return json({ message: "Booking cancelled", ...data });
      }
      if (method === "GET" && (path === "/users/roles" || path === "/roles")) {
        return json({ roles: await rows(db, "app_roles", "id,name") });
      }
      match = /^\/users\/(\d+)$/.exec(path);
      if (method === "GET" && (path === "/users" || match)) {
        let users = await usersWithBalances(db, caller!);
        if (match) {
          const user = users.find((u) => u.id === positiveInt(match![1], "id"));
          if (!user) throw new ApiError(404, "not_found", "User not found");
          return json({ user });
        }
        if (query.has("role_id")) {
          const roleId = positiveInt(query.get("role_id"), "role_id");
          users = users.filter((u) => u.role_id === roleId);
        }
        const search = query.get("search")?.toLocaleLowerCase();
        if (search) {
          users = users.filter((u) =>
            `${u.name} ${u.email}`.toLocaleLowerCase().includes(search)
          );
        }
        const page = query.has("page")
          ? positiveInt(query.get("page"), "page", 100000)
          : 1;
        const perPage = query.has("per_page")
          ? positiveInt(query.get("per_page"), "per_page", 100)
          : 15;
        return json({
          users: users.slice((page - 1) * perPage, page * perPage),
          pagination: {
            current_page: page,
            per_page: perPage,
            total: users.length,
            last_page: Math.max(1, Math.ceil(users.length / perPage)),
          },
        });
      }
      match = /^\/buses\/(\d+)$/.exec(path);
      if (method === "GET" && (path === "/buses" || match)) {
        return json(
          await busesResponse(
            db,
            query,
            match ? positiveInt(match[1], "id") : undefined,
          ),
        );
      }

      throw new ApiError(404, "not_found", "API route not found");
    } catch (error) {
      const failure = error instanceof ApiError
        ? error
        : new ApiError(500, "internal_error", "Internal server error");
      if (!(error instanceof ApiError)) {
        console.error(
          "api unexpected failure",
          requestId,
          error instanceof Error ? error.name : "unknown",
        );
      }
      return json({
        message: failure.message,
        error: { code: failure.code, message: failure.message },
        errors: [failure.message],
        request_id: requestId,
      }, failure.status);
    }
  };
}

function sortStops(stops: Row[], reverse = false): Row[] {
  return stops.sort((a, b) =>
    (a.order - b.order || a.id - b.id) * (reverse ? -1 : 1)
  );
}

async function busesResponse(
  db: SupabaseClient,
  query: URLSearchParams,
  id?: number,
) {
  const [buses, drivers] = await Promise.all([
    id ? one(db, "buses", id).then((bus) => [bus]) : rows(db, "buses"),
    rows(db, "profiles", profileSelect, { role_id: 3 }),
  ]);
  const active = query.has("is_active")
    ? bool(query.get("is_active"), "is_active")
    : null;
  const search = query.get("search")?.toLocaleLowerCase();
  const result = buses.filter((b) =>
    id ||
    ((active === null || b.is_active === active) &&
      (!search ||
        `${b.number} ${b.model ?? ""} ${b.license_plate ?? ""}`
          .toLocaleLowerCase().includes(search)))
  )
    .map((b) => ({
      ...b,
      drivers: drivers.filter((d) => d.bus_id === b.id).map((d) =>
        userShape(d)
      ),
    }));
  return id ? { bus: result[0] } : { buses: result };
}

if (import.meta.main) Deno.serve(createHandler());
