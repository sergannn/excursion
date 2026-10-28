import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ApiError,
  bool,
  databaseError,
  dateOnly,
  positiveInt,
} from "./http.ts";
import { type Row, rows } from "./data.ts";

const round = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;
const sum = (data: Row[], field: string) =>
  round(data.reduce((n, r) => n + Number(r[field] ?? 0), 0));
function own(caller: Row, id: number) {
  if (caller.id !== id && caller.role_id !== 1) {
    throw new ApiError(403, "forbidden", "Own financial reports only");
  }
}
export async function financialContext(
  db: SupabaseClient,
  caller: Row,
  id: number,
): Promise<Row> {
  own(caller, id);
  const { data, error } = await db.rpc("financial_context", { target_id: id });
  if (error) databaseError(error);
  return data;
}
export function sale(b: Row): Row {
  return {
    id: b.id,
    excursion: {
      id: b.excursion_id,
      title: b.excursion.title,
      date_time: b.resolved_date_time,
    },
    customer_name: b.customer_name,
    customer_phone: b.customer_phone,
    passenger_type: b.passenger_type,
    price: Number(b.price),
    stop: b.stop ? { id: b.stop.id, name: b.stop.name } : null,
    booked_at: b.booked_at,
  };
}
export function userReport(c: Row, kind: string): Row {
  const bookings: Row[] = c.bookings;
  if (kind === "wallet") {
    return {
      user: c.user,
      balance: sum(c.transactions, "amount"),
      transactions: c.transactions.map((t: Row) => {
        const b = bookings.find((b) => b.id === t.booking_id);
        return {
          ...t,
          booking: b
            ? {
              id: b.id,
              excursion: b.excursion,
              customer_name: b.customer_name,
              price: b.price,
            }
            : null,
        };
      }),
    };
  }
  if (kind === "sales") {
    return {
      user: c.user,
      total_sales: sum(bookings, "price"),
      bookings: bookings.map(sale),
    };
  }
  if (kind === "profit") {
    const totals: Record<string, Row> = {};
    const breakdown = bookings.map((b) => {
      const tariff = c.prices.find((p: Row) =>
        p.excursion_id === b.excursion_id &&
        p.passenger_type === b.passenger_type
      );
      const percent = Number(
        tariff
          ? tariff[
            c.user.is_partner
              ? "partner_commission_percent"
              : "seller_commission_percent"
          ]
          : c.user.is_partner
          ? 0
          : 10,
      );
      const commission = round(Number(b.price) * percent / 100);
      const t = totals[b.passenger_type] ??= { sales: 0, commission: 0 };
      t.sales += Number(b.price);
      t.commission += commission;
      return {
        booking_id: b.id,
        excursion: b.excursion,
        passenger_type: b.passenger_type,
        price: Number(b.price),
        commission_percent: percent,
        commission_amount: commission,
        booked_at: b.booked_at,
      };
    });
    for (const t of Object.values(totals)) {
      t.sales = round(t.sales);
      t.commission = round(t.commission);
    }
    return {
      user: c.user,
      total_profit: sum(breakdown, "commission_amount"),
      breakdown,
      totals_by_type: totals,
    };
  }
  const breakdown: Row[] = [];
  for (const slot of c.staff_slots) {
    const matches = (a: Row) =>
      a.excursion_id === slot.excursion_id &&
      (!a.excursion_date || a.excursion_date === slot.excursion_date) &&
      (!a.time || a.time === slot.time);
    const assignments = c.assignments.filter(matches);
    const mine = assignments.filter((a: Row) => a.user_id === c.user.id);
    const driver = mine.some((a: Row) => a.role_in_excursion === "driver");
    const guide = mine.some((a: Row) => a.role_in_excursion === "guide");
    const auto = driver &&
      !assignments.some((a: Row) => a.role_in_excursion === "guide");
    for (const role of ["driver", "guide"]) {
      if (role === "driver" ? !driver : !guide && !auto) continue;
      const p = c.staff_prices.find((p: Row) =>
        p.excursion_id === slot.excursion_id && p.staff_type === role &&
        Number(p.min_passengers) <= slot.passenger_count &&
        (p.max_passengers === null ||
          Number(p.max_passengers) >= slot.passenger_count)
      );
      breakdown.push({
        ...slot,
        role,
        is_auto_guide_from_driver: role === "guide" && !guide && auto,
        profit: p ? Number(p.price) : 0,
        staff_price_info: p
          ? {
            price: Number(p.price),
            min_passengers: p.min_passengers,
            max_passengers: p.max_passengers,
          }
          : null,
      });
    }
  }
  return { total_profit: sum(breakdown, "profit"), breakdown };
}

export async function settlementRead(
  db: SupabaseClient,
  caller: Row,
  path: string,
  q: URLSearchParams,
): Promise<Row> {
  if (path === "/settlements" || /^\/settlements\/seller\/\d+$/.test(path)) {
    const id = path === "/settlements"
      ? null
      : positiveInt(path.split("/").at(-1), "seller_id");
    if (id) own(caller, id);
    const data = await rows(
      db,
      "settlements",
      "*,seller:profiles!seller_id(id,name,email),settlement_booking(booking_id)",
      id ? { seller_id: id } : {},
    );
    return {
      settlements: data.sort((a, b) =>
        b.settlement_date.localeCompare(a.settlement_date) ||
        b.created_at.localeCompare(a.created_at)
      ).map((s) => {
        const { settlement_booking, ...rest } = s;
        return { ...rest, bookings_count: settlement_booking.length };
      }),
    };
  }
  if (path === "/settlements/sellers") {
    const [users, bookings, roles] = await Promise.all([
      rows(db, "profiles", "id,name,email,role_id"),
      rows(db, "bookings", "id,booked_by"),
      rows(db, "app_roles"),
    ]);
    const roleIds = new Set(
      roles.filter((r) =>
        ["Организатор экскурсии", "Партнер", "Продавец"].includes(r.name)
      ).map((r) => r.id),
    );
    return {
      sellers: users.filter((u) =>
        roleIds.has(u.role_id) && bookings.some((b) => b.booked_by === u.id)
      ).sort((a, b) => a.name.localeCompare(b.name)).map((
        { id, name, email },
      ) => ({ id, name, email })),
    };
  }
  const m = /^\/settlements\/sellers\/(\d+)\/(sales|calendar-status)$/.exec(
    path,
  )!;
  const id = positiveInt(m[1], "seller_id");
  const c = await financialContext(db, caller, id);
  if (![2, 4].includes(c.user.role_id)) {
    throw new ApiError(400, "not_seller", "User is not a seller");
  }
  const sheets = await rows(
    db,
    "settlements",
    "*,settlement_booking(booking_id)",
    { seller_id: id },
  );
  const byBooking = new Map<number, Row>();
  for (const s of sheets) {
    for (const b of s.settlement_booking) byBooking.set(b.booking_id, s);
  }
  if (m[2] === "calendar-status") {
    const grouped: Record<string, Set<string>> = {};
    for (const b of c.bookings) {
      const d = moscowDate(b.resolved_date_time);
      if (!d) continue;
      (grouped[d] ??= new Set()).add(
        byBooking.has(b.id) ? "settled" : "unsettled",
      );
    }
    return {
      days_status: Object.fromEntries(
        Object.entries(grouped).map((
          [d, v],
        ) => [d, v.size > 1 ? "partial" : [...v][0]]),
      ),
    };
  }
  const from = q.has("date_from") ? dateOnly(q.get("date_from")) : null;
  const to = q.has("date_to") ? dateOnly(q.get("date_to")) : null;
  if (from && to && from > to) {
    throw new ApiError(422, "validation_error", "Invalid date range");
  }
  const period = c.bookings.filter((b: Row) => {
    // Laravel date filtering uses stored excursion_date, then excursion.date_time.
    const d = b.excursion_date ?? moscowDate(b.excursion.date_time);
    return (!from || d && d >= from) && (!to || d && d <= to);
  });
  const settled = q.has("settled") ? bool(q.get("settled"), "settled") : false;
  const selected = period.filter((b: Row) => byBooking.has(b.id) === settled);
  const sales = selected.map((b: Row) => {
    const s = byBooking.get(b.id);
    return {
      ...sale(b),
      ...(settled && s
        ? {
          settlement: {
            id: s.id,
            settlement_date: s.settlement_date,
            total_amount: Number(s.total_amount),
          },
        }
        : {}),
    };
  });
  const paid = period.filter((b: Row) => byBooking.has(b.id));
  return {
    seller: { id: c.user.id, name: c.user.name, email: c.user.email },
    total_amount: sum(sales, "price"),
    sales,
    period_stats: from || to
      ? {
        total_sales: sum(period, "price"),
        settled_sales: sum(paid, "price"),
        unsettled_sales: round(sum(period, "price") - sum(paid, "price")),
        total_count: period.length,
        settled_count: paid.length,
        unsettled_count: period.length - paid.length,
      }
      : null,
  };
}
function moscowDate(value: string | null): string | null {
  return value
    ? new Date(Date.parse(value) + 3 * 3600000).toISOString().slice(0, 10)
    : null;
}

export async function statistics(db: SupabaseClient, caller: Row) {
  if (caller.role_id !== 1) {
    throw new ApiError(403, "forbidden", "Administrator required");
  }
  const [excursions, bookings, prices, staff, assignments] = await Promise.all([
    rows(db, "excursions"),
    rows(db, "bookings"),
    rows(db, "excursion_prices"),
    rows(db, "staff_prices"),
    rows(db, "excursion_user"),
  ]);
  const result = excursions.filter((e) => e.is_active).flatMap((e) => {
    const bs = bookings.filter((b) => b.excursion_id === e.id);
    if (!bs.length) return [];
    const revenue = sum(bs, "price");
    const commission = round(
      bs.reduce((n, b) =>
        n + Number(b.price) * Number(
            prices.find((p) =>
              p.excursion_id === e.id && p.passenger_type === b.passenger_type
            )?.seller_commission_percent ?? 10,
          ) /
          100, 0),
    );
    const cost = (role: string) => {
      if (
        !assignments.some((a) =>
          a.excursion_id === e.id && a.role_in_excursion === role
        )
      ) return 0;
      return Number(
        staff.find((p) =>
          p.excursion_id === e.id && p.staff_type === role &&
          p.min_passengers <= bs.length &&
          (p.max_passengers === null || p.max_passengers >= bs.length)
        )?.price ?? 0,
      );
    };
    const driver = cost("driver"), guide = cost("guide");
    return [{
      excursion: { id: e.id, title: e.title, date_time: e.date_time },
      income: revenue,
      total_revenue: revenue,
      bookings_count: bs.length,
      seller_commissions: commission,
      driver_costs: driver,
      guide_costs: guide,
      staff_costs: round(driver + guide),
      net_profit: round(revenue - commission - driver - guide),
    }];
  });
  return { statistics: result, total_net_profit: sum(result, "net_profit") };
}
