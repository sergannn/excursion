import { PDFDocument, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import type { SupabaseClient } from "@supabase/supabase-js";
import { bookingSelect, one, type Row } from "./data.ts";
import { fontBase64 } from "./font_data.ts";
import { ApiError, positiveInt } from "./http.ts";
import { databaseError } from "./http.ts";

export function ticketIds(anchor: number, query: URLSearchParams): number[] {
  const values: string[] = [];
  for (const [key, value] of query) {
    if (key === "ids" || key === "ids[]" || /^ids\[\d+\]$/.test(key)) {
      values.push(value);
    } else if (key.startsWith("ids")) {
      throw new ApiError(422, "validation_error", "Invalid ids array");
    }
  }
  if (values.length > 100) {
    throw new ApiError(422, "validation_error", "At most 100 tickets per PDF");
  }
  return [
    ...new Set(
      values.length ? values.map((v) => positiveInt(v, "ids")) : [anchor],
    ),
  ];
}

let fontBytes: Promise<Uint8Array> | undefined;
function loadFont() {
  return fontBytes ??= Promise.resolve(
    Uint8Array.from(atob(fontBase64), (c) => c.charCodeAt(0)),
  );
}

export async function renderTickets(bookings: Row[]): Promise<Uint8Array> {
  if (bookings.length === 0) {
    throw new ApiError(404, "not_found", "Bookings not found");
  }
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const font = await pdf.embedFont(await loadFont(), { subset: true });
  const characterSet = new Set(font.getCharacterSet());
  pdf.setTitle("Электронные билеты");
  pdf.setCreator("Excursion booking");
  const types: Record<string, string> = {
    adult: "Взрослый",
    child: "Детский",
    senior: "Пенсионный",
    disabled: "Льготный",
    special: "Специальный",
    concession: "Льготный",
  };
  const anchor = bookings[0];
  let page = pdf.addPage([595.28, 841.89]);
  let y = 785;
  const line = (value: unknown, size = 13, indent = 0) => {
    const safe = Array.from(String(value ?? "-")).map((c) =>
      c.codePointAt(0)! < 32 || c.codePointAt(0) === 127
        ? " "
        : characterSet.has(c.codePointAt(0)!)
        ? c
        : "?"
    ).join("");
    // Character wrapping also handles a single very long unbroken field.
    let part = "";
    const draw = () => {
      if (y < 55) {
        page = pdf.addPage([595.28, 841.89]);
        y = 785;
      }
      page.drawText(part, {
        x: 45 + indent,
        y,
        size,
        font,
        color: rgb(0.08, 0.12, 0.18),
      });
      y -= size + 10;
      part = "";
    };
    for (const c of safe) {
      if (font.widthOfTextAtSize(part + c, size) > 505 - indent) draw();
      part += c;
    }
    draw();
  };
  const date = String(anchor.excursion_date ?? "-");
  const formattedDate = /^\d{4}-\d{2}-\d{2}$/.test(date)
    ? date.split("-").reverse().join(".")
    : date;
  const total = bookings.reduce(
    (sum, booking) => sum + Number(booking.price ?? 0),
    0,
  );
  line("Электронный билет", 24);
  line(`Номер билета: T-${anchor.excursion_id}-${anchor.id}`);
  y -= 12;
  line(anchor.excursion?.title ?? "Экскурсия", 19);
  line(
    `Дата и время: ${formattedDate} ${String(anchor.time ?? "-").slice(0, 5)}`,
  );
  line(`Остановка: ${anchor.stop?.name ?? "-"}`);
  line(
    `Покупатель: ${anchor.customer_name ?? "-"} • ${
      anchor.customer_phone ?? "-"
    }`,
  );
  line(`Организатор экскурсии: ${anchor.owner?.name ?? "-"}`);
  y -= 14;
  line(`Пассажиры (${bookings.length})`, 17);
  for (const booking of bookings) {
    const entry = booking.with_entry
      ? "Входной билет включен"
      : "Без входного билета";
    line(
      `№${booking.bus_seat?.seat_number ?? "-"} • ${
        booking.customer_name ?? "-"
      } • ${
        types[booking.passenger_type] ?? booking.passenger_type ?? "-"
      } • ${entry} • ${Number(booking.price ?? 0).toFixed(2)} руб.`,
      11,
      8,
    );
    if (booking.customer_phone) {
      line(`Телефон: ${booking.customer_phone}`, 10, 20);
    }
  }
  y -= 10;
  line(`Итого к оплате: ${total.toFixed(2)} руб.`, 17);
  y -= 10;
  line(
    "Пожалуйста, предъявите этот билет при посадке. Перенос и отмена возможны не позднее чем за 24 часа до начала экскурсии.",
    10,
  );
  return pdf.save();
}

export async function ticketPdf(
  db: SupabaseClient,
  caller: Row,
  anchor: number,
  query: URLSearchParams,
) {
  const ids = ticketIds(anchor, query);
  const explicitIds = [...query.keys()].some((key) =>
    key === "ids" || key === "ids[]" || /^ids\[\d+\]$/.test(key)
  );
  const selected = new Map<number, Row>();
  // Check the URL resource too, even when ids[] overrides the rendered set.
  for (const id of new Set([anchor, ...ids])) {
    const b = await one(db, "bookings", id, bookingSelect);
    if (caller.role_id !== 1 && b.booked_by !== caller.id) {
      throw new ApiError(404, "not_found", "Resource not found or unavailable");
    }
    selected.set(id, b);
  }
  if (explicitIds) {
    return renderTickets(ids.map((id) => selected.get(id)!));
  }

  const first = selected.get(anchor)!;
  let related = db.from("bookings").select(bookingSelect)
    .eq("excursion_id", first.excursion_id)
    .eq("excursion_date", first.excursion_date)
    .eq("booked_by", first.booked_by)
    .order("bus_seat_id");
  if (first.time) related = related.eq("time", first.time);
  if (first.booked_at) {
    const bookedAt = new Date(first.booked_at);
    if (!Number.isNaN(bookedAt.valueOf())) {
      related = related
        .gte("booked_at", new Date(bookedAt.valueOf() - 30_000).toISOString())
        .lte("booked_at", new Date(bookedAt.valueOf() + 30_000).toISOString());
    }
  }
  const { data, error } = await related;
  if (error) databaseError(error);
  const grouped = (data ?? []) as unknown as Row[];
  if (!grouped.some((booking) => booking.id === anchor)) grouped.push(first);
  return renderTickets(grouped);
}
