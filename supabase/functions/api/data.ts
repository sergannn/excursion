import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, databaseError } from "./http.ts";

// SQL results are deliberately open records: this adapter preserves legacy
// fields. Request bodies use unknown and are validated separately in http.ts.
// deno-lint-ignore no-explicit-any
export type Row = Record<string, any>;
export const profileSelect =
  "id,name,email,color,role_id,bus_id,created_at,updated_at,app_roles(name),bus:buses(id,number,model,capacity)";

// Never rely on PostgREST's default 1000-row cap for counts, wallets or bookings.
// Pages use a unique stable order; a bounded failure is preferable to truncation.
export async function rows(
  db: SupabaseClient,
  table: string,
  select = "*",
  filters: Record<string, string | number> = {},
): Promise<Row[]> {
  const result: Row[] = [];
  while (result.length < 50000) {
    let query = db.from(table).select(select, { count: "exact" }).order("id");
    for (const [key, value] of Object.entries(filters)) {
      query = query.eq(key, value);
    }
    const { data, error, count } = await query.range(
      result.length,
      result.length + 499,
    );
    if (error) databaseError(error);
    if (count !== null && count > 50000) break;
    const batch = (data ?? []) as unknown as Row[];
    result.push(...batch);
    if (count !== null ? result.length >= count : batch.length < 500) {
      return result;
    }
    if (batch.length === 0) break;
  }
  throw new ApiError(
    503,
    "result_too_large",
    "Result exceeds the compatibility API limit",
  );
}

export async function one(
  db: SupabaseClient,
  table: string,
  id: number,
  select = "*",
): Promise<Row> {
  const { data, error } = await db.from(table).select(select).eq("id", id)
    .maybeSingle();
  if (error) databaseError(error);
  if (!data) {
    throw new ApiError(404, "not_found", "Resource not found or unavailable");
  }
  return data as unknown as Row;
}

export function userShape(row: Row, balance: number | null = null): Row {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    color: row.color,
    role_id: row.role_id,
    role: row.app_roles?.name ?? "Unknown",
    is_super_user: row.role_id === 1,
    bus_id: row.bus_id,
    bus: row.bus,
    balance,
    balance_visible: balance !== null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

export async function usersWithBalances(
  db: SupabaseClient,
  caller: Row,
): Promise<Row[]> {
  const [profiles, transactions] = await Promise.all([
    rows(db, "profiles", profileSelect),
    rows(db, "wallet_transactions", "id,user_id,amount"),
  ]);
  const balances = new Map<number, number>();
  for (const tx of transactions) {
    balances.set(
      tx.user_id,
      (balances.get(tx.user_id) ?? 0) + Number(tx.amount),
    );
  }
  return profiles.map((profile) =>
    userShape(
      profile,
      caller.role_id === 1 || profile.id === caller.id
        ? Math.round((balances.get(profile.id) ?? 0) * 100) / 100
        : null,
    )
  );
}

export const weekdays = [
  "",
  "Понедельник",
  "Вторник",
  "Среда",
  "Четверг",
  "Пятница",
  "Суббота",
  "Воскресенье",
];
export const hhmm = (time: string | null | undefined) =>
  time?.slice(0, 5) ?? "";
export function moscowParts(
  value: string | Date,
): { date: string; time: string } {
  const shifted = new Date(new Date(value).getTime() + 3 * 3600000)
    .toISOString();
  return { date: shifted.slice(0, 10), time: shifted.slice(11, 16) };
}
export function slot(date: string, time: string): Row {
  const weekday = new Date(date).getUTCDay() || 7;
  return {
    date,
    time: hhmm(time),
    date_time: `${date}T${hhmm(time)}:00+03:00`,
    weekday,
    weekday_name: weekdays[weekday],
    is_unscheduled: false,
    is_cancelled: false,
  };
}

export function expandSlots(
  excursion: Row,
  days: Row[],
  extra: Row[],
  cancelled: Row[],
  includePast: boolean,
  now = new Date(),
): Row[] {
  const today = moscowParts(now).date;
  const start = new Date(`${today}T00:00:00Z`);
  const slots = new Map<string, Row>();
  const put = (item: Row) => slots.set(`${item.date} ${item.time}`, item);
  for (let offset = includePast ? -30 : 0; offset < 30; offset++) {
    const date = new Date(start.getTime() + offset * 86400000).toISOString()
      .slice(0, 10);
    for (const day of days) {
      if (
        day.schedule_template_id === excursion.schedule_template_id &&
        day.time &&
        (new Date(date).getUTCDay() || 7) === day.weekday
      ) put(slot(date, day.time));
    }
  }
  // A standalone dated excursion is also usable without a weekly schedule.
  if (slots.size === 0 && excursion.date_time) {
    const { date, time } = moscowParts(excursion.date_time);
    put(slot(date, time));
  }
  const earliest = new Date(start.getTime() - (includePast ? 30 : 0) * 86400000)
    .toISOString().slice(0, 10);
  for (const item of extra) {
    if (item.excursion_id !== excursion.id || item.deleted_at) continue;
    const { date, time } = moscowParts(item.date_time);
    if (date >= earliest) {
      put({
        ...slot(date, time),
        is_unscheduled: true,
        unscheduled_date_id: item.id,
      });
    }
  }
  const cancelledKeys = new Set(
    cancelled.filter((c) => c.excursion_id === excursion.id).map((c) => {
      const { date, time } = moscowParts(c.date_time);
      return `${date} ${time}`;
    }),
  );
  return [...slots.values()].map<Row>((s) => ({
    ...s,
    is_cancelled: cancelledKeys.has(`${s.date} ${s.time}`),
  }))
    .sort((a, b) => a.date_time.localeCompare(b.date_time));
}

export const bookingSelect =
  "*,excursion:excursions(id,title,date_time,price,max_seats),bus_seat:bus_seats(id,seat_number),stop:stops(id,name,order),owner:profiles!bookings_booked_by_fkey(id,name,color)";
export function bookingShape(booking: Row): Row {
  const { owner, ...result } = booking;
  // An own booking can remain readable after its excursion is made inactive.
  // Excursion RLS then hides the joined row. Keep the booking model parseable
  // without disclosing or inventing the hidden excursion's details.
  const excursion = booking.excursion ?? {
    id: booking.excursion_id,
    title: "Unavailable excursion",
    date_time: booking.booked_at,
    price: null,
    max_seats: null,
  };
  return {
    ...result,
    time: booking.time ? hhmm(booking.time) : null,
    booked_by_name: owner?.name ?? null,
    excursion_visible: booking.excursion != null,
    excursion: {
      ...excursion,
      ...(booking.excursion_date && booking.time
        ? slot(booking.excursion_date, booking.time)
        : {}),
    },
  };
}

export function assignedTo(assignment: Row, target: Row): boolean {
  return (!assignment.excursion_date ||
    assignment.excursion_date === target.date) &&
    (!assignment.time || hhmm(assignment.time) === target.time);
}

export async function excursionData(
  db: SupabaseClient,
  caller: Row | null,
  id?: number,
) {
  const filters: Record<string, string | number> = id
    ? { excursion_id: id }
    : {};
  const [excursions, days, prices, extra, cancelled] = await Promise.all([
    id ? one(db, "excursions", id).then((r) => [r]) : rows(db, "excursions"),
    rows(db, "schedule_days"),
    rows(db, "excursion_prices", "*", filters),
    rows(db, "unscheduled_excursion_dates", "*", filters),
    rows(db, "cancelled_excursion_dates", "*", filters),
  ]);
  const [seats, bookings, staff, assignments, limits, staffPrices] = caller
    ? await Promise.all([
      // Omit global booked_by/booked_at: they are not a per-slot occupancy view.
      rows(db, "bus_seats", "id,excursion_id,seat_number,status", filters),
      rows(db, "bookings", bookingSelect, filters),
      rows(
        db,
        "excursion_user",
        "*,profile:profiles!excursion_user_user_id_fkey(id,name,email)",
        filters,
      ),
      rows(
        db,
        "excursion_bus_assignments",
        "*,bus:buses(*),driver:profiles!excursion_bus_assignments_driver_id_fkey(id,name,email,color,role_id)",
        filters,
      ),
      rows(db, "excursion_slot_limits", "*", filters),
      rows(db, "staff_prices", "*", filters),
    ])
    : [[], [], [], [], [], []];

  function render(excursion: Row, target: Row, includeDetails: boolean): Row {
    const matchingBookings = bookings.filter((b) =>
      b.excursion_id === excursion.id &&
      b.excursion_date === target.date && hhmm(b.time) === target.time
    );
    const matchingStaff = staff.filter((s) =>
      s.excursion_id === excursion.id && assignedTo(s, target)
    );
    const complete = !!caller &&
      (caller.role_id === 1 ||
        matchingStaff.some((s) => s.user_id === caller.id));
    const limit =
      limits.find((l) =>
        l.excursion_id === excursion.id && l.excursion_date === target.date &&
        hhmm(l.time) === target.time
      )?.max_seats ?? excursion.max_seats;
    const bySeat = new Map(matchingBookings.map((b) => [b.bus_seat_id, b]));
    const busSeats = seats.filter((s) =>
      s.excursion_id === excursion.id && s.seat_number <= limit
    ).map((s) => {
      const b = bySeat.get(s.id);
      return {
        id: s.id,
        seat_number: s.seat_number,
        // Conservatively reserve a globally booked seat when RLS prevents
        // proving whether another user's booking belongs to this slot.
        status: b
          ? "booked"
          : !complete && s.status !== "available"
          ? "reserved"
          : "available",
        occupancy_known: complete || !!b || s.status === "available",
        booked_by: b?.booked_by ?? null,
        booked_at: b?.booked_at ?? null,
        booked_by_info: b?.owner ?? null,
        ...(b && includeDetails
          ? {
            booking: {
              ...bookingShape(b),
              stop_title: b.stop?.name ?? null,
              stop_order: b.stop?.order ?? null,
            },
          }
          : {}),
      };
    }).sort((a, b) => a.seat_number - b.seat_number);
    return {
      ...excursion,
      description: excursion.description ?? "",
      ...target,
      prices: prices.filter((p) => p.excursion_id === excursion.id),
      staff_prices: staffPrices.filter((p) => p.excursion_id === excursion.id),
      slot_max_seats: limit,
      bus_seats: busSeats,
      booked_seats_count: complete ? matchingBookings.length : null,
      visible_booked_seats_count: matchingBookings.length,
      available_seats_count: complete
        ? Math.max(0, limit - matchingBookings.length)
        : null,
      occupancy_complete: complete,
      assigned_staff: matchingStaff.map((s) => ({
        ...s.profile,
        role_in_excursion: s.role_in_excursion,
        excursion_date: s.excursion_date,
        time: s.time,
        manual_amount: s.manual_amount,
      })),
      bus_assignments: assignments.filter((a) =>
        a.excursion_id === excursion.id && a.excursion_date === target.date &&
        hhmm(a.time) === target.time
      )
        .map((a) => ({ ...a, allocated_seats: a.seat_to - a.seat_from + 1 })),
    };
  }
  return { excursions, days, extra, cancelled, staff, render };
}
