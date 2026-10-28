from __future__ import annotations

from pathlib import Path
from typing import Iterable
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path("/Users/servas/booking_krym")
OUT = ROOT / "rustore_assets"
OUT.mkdir(exist_ok=True)

W = 1920
H = 1080

FONT_REG = "/System/Library/Fonts/SFNS.ttf"
FONT_BOLD = "/System/Library/Fonts/SFNSRounded.ttf"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size=size)


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        draw.line([(0, y), (w, y)], fill=color)
    return img


def wrap_text(draw: ImageDraw.ImageDraw, text: str, text_font: ImageFont.FreeTypeFont, max_width: int) -> str:
    lines: list[str] = []
    for paragraph in text.splitlines():
        words = paragraph.split()
        if not words:
            lines.append("")
            continue
        current = words[0]
        for word in words[1:]:
            candidate = f"{current} {word}"
            if draw.textlength(candidate, font=text_font) <= max_width:
                current = candidate
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return "\n".join(lines)


def rounded_box(draw: ImageDraw.ImageDraw, xy, radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def add_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int = 26, alpha: int = 70):
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(box, radius=36, fill=(0, 0, 0, alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius))
    base.alpha_composite(shadow)


def draw_header(draw: ImageDraw.ImageDraw, kicker: str, title: str, subtitle: str) -> int:
    title_font = font(78, bold=True)
    subtitle_font = font(31)
    wrapped_title = wrap_text(draw, title, title_font, 820)
    wrapped_subtitle = wrap_text(draw, subtitle, subtitle_font, 760)
    draw.text((120, 92), kicker.upper(), font=font(30, bold=True), fill=(115, 91, 214))
    draw.multiline_text((120, 132), wrapped_title, font=title_font, fill=(20, 24, 39), spacing=2)
    title_box = draw.multiline_textbbox((120, 132), wrapped_title, font=title_font, spacing=2)
    subtitle_y = title_box[3] + 20
    draw.multiline_text((120, subtitle_y), wrapped_subtitle, font=subtitle_font, fill=(70, 74, 94), spacing=8)
    subtitle_box = draw.multiline_textbbox((120, subtitle_y), wrapped_subtitle, font=subtitle_font, spacing=8)
    return subtitle_box[3]


def pill(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, fill=(245, 238, 255), fg=(95, 72, 190)):
    w = int(draw.textlength(text, font=font(26, bold=True))) + 44
    rounded_box(draw, (x, y, x + w, y + 52), 26, fill=fill)
    draw.text((x + 22, y + 11), text, font=font(26, bold=True), fill=fg)
    return w


def draw_phone_shell(base: Image.Image, screen_box: tuple[int, int, int, int], title: str):
    left, top, right, bottom = screen_box
    outer = (left - 18, top - 18, right + 18, bottom + 18)
    add_shadow(base, outer, radius=30, alpha=90)
    draw = ImageDraw.Draw(base)
    rounded_box(draw, outer, 56, fill=(23, 25, 38))
    rounded_box(draw, screen_box, 42, fill=(247, 248, 252))
    draw.rounded_rectangle((left + 135, top + 14, right - 135, top + 34), radius=10, fill=(34, 36, 48))
    draw.text((left + 38, top + 36), title, font=font(24, bold=True), fill=(40, 46, 72))


def draw_nav(draw: ImageDraw.ImageDraw, left: int, bottom: int, items: Iterable[tuple[str, bool]]):
    x = left + 40
    for label, active in items:
        color = (103, 80, 164) if active else (149, 156, 178)
        draw.ellipse((x, bottom - 78, x + 18, bottom - 60), fill=color)
        draw.text((x - 18, bottom - 46), label, font=font(18, bold=active), fill=color)
        x += 120


def screenshot_excursions() -> Image.Image:
    img = gradient((W, H), (243, 238, 255), (255, 255, 255)).convert("RGBA")
    draw = ImageDraw.Draw(img)
    header_bottom = draw_header(
        draw,
        "RuStore",
        "Продажа экскурсий\nв одном приложении",
        "Организаторы, администраторы, водители и гиды\nработают с единым расписанием и актуальными данными.",
    )
    pills_y = header_bottom + 24
    pill(draw, 120, pills_y, "Оффлайн-работа")
    pill(draw, 370, pills_y, "Расписание")
    pill(draw, 565, pills_y, "Роли сотрудников")

    screen = (1110, 104, 1670, 964)
    draw_phone_shell(img, screen, "Организатор экскурсии")
    sl, st, sr, sb = screen
    card_y = st + 96
    for idx, name in enumerate(("Ялта обзорная", "Ласточкино гнездо", "Балаклава")):
        y = card_y + idx * 178
        rounded_box(draw, (sl + 30, y, sr - 30, y + 146), 28, fill=(255, 255, 255), outline=(224, 227, 240))
        draw.text((sl + 58, y + 24), name, font=font(27, bold=True), fill=(28, 33, 58))
        draw.text((sl + 58, y + 66), f"{9 + idx}:00  •  {24 + idx} мест", font=font(22), fill=(99, 104, 126))
        rounded_box(draw, (sr - 182, y + 36, sr - 54, y + 92), 20, fill=(103, 80, 164))
        draw.text((sr - 148, y + 52), "Открыть", font=font(21, bold=True), fill=(255, 255, 255))
    draw_nav(draw, sl, sb, [("Экскурсии", True), ("Бронь", False), ("Кошелёк", False), ("Цены", False)])

    box_top = pills_y + 110
    rounded_box(draw, (120, box_top, 810, box_top + 360), 42, fill=(255, 255, 255, 215))
    draw.text((160, box_top + 46), "Что видит продавец", font=font(38, bold=True), fill=(28, 33, 58))
    points = [
        "Актуальные экскурсии по датам",
        "Быстрый переход к местам и бронированию",
        "Разделы: расписание, цены, кошелёк, билеты",
    ]
    y = box_top + 118
    for point in points:
        draw.ellipse((164, y + 12, 182, y + 30), fill=(103, 80, 164))
        draw.text((202, y), point, font=font(28), fill=(68, 74, 98))
        y += 72
    return img


def screenshot_booking() -> Image.Image:
    img = gradient((W, H), (236, 249, 255), (255, 255, 255)).convert("RGBA")
    draw = ImageDraw.Draw(img)
    header_bottom = draw_header(
        draw,
        "RuStore",
        "Схема мест и быстрое\nбронирование",
        "Место, пассажир, тип тарифа и входной билет\nоформляются в одном сценарии без бумажных таблиц.",
    )
    pills_y = header_bottom + 24
    pill(draw, 120, pills_y, "Схема автобуса", fill=(225, 248, 255), fg=(22, 108, 140))
    pill(draw, 385, pills_y, "Несколько мест", fill=(225, 248, 255), fg=(22, 108, 140))
    pill(draw, 615, pills_y, "PDF-билеты", fill=(225, 248, 255), fg=(22, 108, 140))

    screen = (1060, 90, 1680, 980)
    draw_phone_shell(img, screen, "Выбор мест")
    sl, st, sr, sb = screen
    rounded_box(draw, (sl + 28, st + 82, sr - 28, st + 360), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    seat_colors = [(166, 215, 136), (255, 210, 102), (236, 239, 247)]
    for row in range(5):
        for col in range(4):
            x = sl + 72 + col * 112
            y = st + 132 + row * 42
            c = seat_colors[(row + col) % len(seat_colors)]
            rounded_box(draw, (x, y, x + 72, y + 26), 10, fill=c)
            draw.text((x + 24, y + 2), str(row * 4 + col + 1), font=font(16, bold=True), fill=(49, 54, 76))
    rounded_box(draw, (sl + 28, st + 392, sr - 28, sb - 102), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 52, st + 422), "Пассажир • место 7", font=font(26, bold=True), fill=(28, 33, 58))
    for idx, line in enumerate(("Имя: Анна П.", "Телефон: +7 9•• •••-••-••", "Тариф: взрослый", "Входной билет: да")):
        draw.text((sl + 52, st + 472 + idx * 42), line, font=font(23), fill=(88, 94, 118))
    rounded_box(draw, (sr - 248, sb - 172, sr - 52, sb - 116), 22, fill=(21, 157, 123))
    draw.text((sr - 214, sb - 156), "Сохранить", font=font(22, bold=True), fill=(255, 255, 255))
    draw_nav(draw, sl, sb, [("Экскурсии", False), ("Бронь", True), ("Кошелёк", False), ("Цены", False)])

    box_top = pills_y + 110
    rounded_box(draw, (120, box_top, 800, box_top + 380), 42, fill=(255, 255, 255, 215))
    draw.text((160, box_top + 44), "Что проверяет система", font=font(38, bold=True), fill=(28, 33, 58))
    points = [
        "Свободно ли место и есть ли доступ к нему",
        "Подходящую цену для типа пассажира",
        "Сохранение билета и информации по продаже",
    ]
    y = box_top + 116
    for point in points:
        draw.ellipse((164, y + 12, 182, y + 30), fill=(22, 108, 140))
        draw.text((202, y), point, font=font(28), fill=(68, 74, 98))
        y += 76
    return img


def screenshot_staff() -> Image.Image:
    img = gradient((W, H), (244, 242, 255), (255, 255, 255)).convert("RGBA")
    draw = ImageDraw.Draw(img)
    header_bottom = draw_header(
        draw,
        "RuStore",
        "Автобусы, водители\nи гиды под контролем",
        "Администратор назначает персонал на экскурсии,\nвидит автобус, вместимость и состав смены.",
    )
    pills_y = header_bottom + 24
    pill(draw, 120, pills_y, "Автобусы")
    pill(draw, 280, pills_y, "Водители")
    pill(draw, 445, pills_y, "Гиды")
    pill(draw, 555, pills_y, "Назначения")

    screen = (1020, 84, 1710, 984)
    draw_phone_shell(img, screen, "Администратор")
    sl, st, sr, sb = screen
    rounded_box(draw, (sl + 26, st + 84, sr - 26, st + 318), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 56, st + 116), "Автобус №21", font=font(28, bold=True), fill=(28, 33, 58))
    draw.text((sl + 56, st + 160), "Mercedes Sprinter • 50 мест", font=font(23), fill=(94, 98, 121))
    draw.text((sl + 56, st + 198), "Водитель: Алексей Д.", font=font(23), fill=(103, 80, 164))
    rounded_box(draw, (sr - 194, st + 114, sr - 56, st + 170), 20, fill=(233, 245, 235))
    draw.text((sr - 162, st + 129), "Активен", font=font(22, bold=True), fill=(36, 122, 62))

    rounded_box(draw, (sl + 26, st + 352, sr - 26, sb - 102), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 56, st + 388), "Экскурсия: Ласточкино гнездо", font=font(27, bold=True), fill=(28, 33, 58))
    staff_rows = [
        ("Водитель", "Алексей Д.", (103, 80, 164)),
        ("Гид", "Мария Г.", (9, 145, 163)),
        ("Автобус", "№21 / 50 мест", (255, 153, 0)),
    ]
    for idx, (role, name, color) in enumerate(staff_rows):
        y = st + 454 + idx * 86
        rounded_box(draw, (sl + 56, y, sr - 56, y + 64), 24, fill=(247, 248, 252))
        draw.ellipse((sl + 82, y + 18, sl + 110, y + 46), fill=color)
        draw.text((sl + 132, y + 17), role, font=font(22, bold=True), fill=(70, 74, 98))
        draw.text((sl + 272, y + 17), name, font=font(22), fill=(35, 39, 58))
    draw_nav(draw, sl, sb, [("Бронь", False), ("Смена", True), ("Расчёт", False)])

    box_top = pills_y + 110
    rounded_box(draw, (120, box_top, 820, box_top + 380), 42, fill=(255, 255, 255, 215))
    draw.text((160, box_top + 44), "Главные связи в системе", font=font(38, bold=True), fill=(28, 33, 58))
    points = [
        "Автобус привязывается к водителю",
        "Водитель и гид назначаются на экскурсию",
        "Сотрудники видят только свои маршруты и брони",
    ]
    y = box_top + 116
    for point in points:
        draw.ellipse((164, y + 12, 182, y + 30), fill=(103, 80, 164))
        draw.text((202, y), point, font=font(28), fill=(68, 74, 98))
        y += 76
    return img


def screenshot_prices() -> Image.Image:
    img = gradient((W, H), (255, 248, 234), (255, 255, 255)).convert("RGBA")
    draw = ImageDraw.Draw(img)
    header_bottom = draw_header(
        draw,
        "RuStore",
        "Цены, расписание и внеплановые даты",
        "Для каждой экскурсии доступны тарифы, входные билеты,\nкомиссии и управление расписанием по датам.",
    )
    pills_y = header_bottom + 24
    pill(draw, 120, pills_y, "Тарифы", fill=(255, 240, 217), fg=(187, 103, 14))
    pill(draw, 245, pills_y, "Вход/без входа", fill=(255, 240, 217), fg=(187, 103, 14))
    pill(draw, 525, pills_y, "Расписание", fill=(255, 240, 217), fg=(187, 103, 14))

    screen = (1065, 86, 1690, 984)
    draw_phone_shell(img, screen, "Цены и расписание")
    sl, st, sr, sb = screen
    rounded_box(draw, (sl + 28, st + 84, sr - 28, st + 380), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 56, st + 116), "Ласточкино гнездо", font=font(27, bold=True), fill=(28, 33, 58))
    rows = [("Взрослый", "2400 ₽ / 2900 ₽"), ("Детский", "1600 ₽ / 2100 ₽"), ("Пенсионер", "1900 ₽ / 2400 ₽")]
    for idx, (name, value) in enumerate(rows):
        y = st + 170 + idx * 62
        draw.text((sl + 58, y), name, font=font(22), fill=(83, 89, 113))
        draw.text((sr - 250, y), value, font=font(22, bold=True), fill=(187, 103, 14))
    rounded_box(draw, (sl + 28, st + 416, sr - 28, sb - 102), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 56, st + 450), "Расписание", font=font(27, bold=True), fill=(28, 33, 58))
    dates = [("22 апр", True), ("23 апр", False), ("25 апр", True), ("27 апр", False)]
    x = sl + 58
    for date, active in dates:
        color = (187, 103, 14) if active else (225, 229, 240)
        text = (255, 255, 255) if active else (88, 94, 118)
        rounded_box(draw, (x, st + 502, x + 114, st + 560), 22, fill=color)
        draw.text((x + 20, st + 518), date, font=font(20, bold=True), fill=text)
        x += 132
    draw.text((sl + 58, st + 610), "Добавление внеплановых дат и отмен", font=font(23), fill=(88, 94, 118))
    draw_nav(draw, sl, sb, [("Экскурсии", False), ("Цены", True), ("Календарь", False)])

    box_top = pills_y + 110
    rounded_box(draw, (120, box_top, 820, box_top + 380), 42, fill=(255, 255, 255, 215))
    draw.text((160, box_top + 44), "Для кого это полезно", font=font(38, bold=True), fill=(28, 33, 58))
    points = [
        "Администратор меняет тарифы без ручных таблиц",
        "Продавец видит актуальную стоимость сразу при продаже",
        "Расписание учитывает обычные и внеплановые выезды",
    ]
    y = box_top + 116
    for point in points:
        draw.ellipse((164, y + 12, 182, y + 30), fill=(187, 103, 14))
        draw.text((202, y), point, font=font(28), fill=(68, 74, 98))
        y += 76
    return img


def screenshot_wallet() -> Image.Image:
    img = gradient((W, H), (235, 250, 245), (255, 255, 255)).convert("RGBA")
    draw = ImageDraw.Draw(img)
    header_bottom = draw_header(
        draw,
        "RuStore",
        "Билеты, кошелёк\nи расчёты по продажам",
        "Приложение хранит билеты, показывает продажи и помогает\nсчитать выплаты сотрудникам и партнёрам.",
    )
    pills_y = header_bottom + 24
    pill(draw, 120, pills_y, "PDF-билеты", fill=(224, 248, 239), fg=(24, 128, 97))
    pill(draw, 300, pills_y, "Кошелёк", fill=(224, 248, 239), fg=(24, 128, 97))
    pill(draw, 455, pills_y, "Расчёты", fill=(224, 248, 239), fg=(24, 128, 97))

    screen = (1075, 84, 1685, 984)
    draw_phone_shell(img, screen, "Кошелёк и билеты")
    sl, st, sr, sb = screen
    rounded_box(draw, (sl + 28, st + 84, sr - 28, st + 248), 32, fill=(24, 128, 97))
    draw.text((sl + 56, st + 118), "Баланс продавца", font=font(24), fill=(220, 244, 237))
    draw.text((sl + 56, st + 154), "126 450 ₽", font=font(48, bold=True), fill=(255, 255, 255))
    draw.text((sl + 56, st + 206), "Продажи за неделю: 18", font=font(22), fill=(220, 244, 237))

    rounded_box(draw, (sl + 28, st + 278, sr - 28, sb - 102), 32, fill=(255, 255, 255), outline=(226, 231, 244))
    draw.text((sl + 56, st + 314), "Электронный билет", font=font(27, bold=True), fill=(28, 33, 58))
    draw.text((sl + 56, st + 362), "Ялта обзорная • 24.04 • 09:00", font=font(22), fill=(88, 94, 118))
    draw.text((sl + 56, st + 404), "Пассажир: Анна П. • место 7", font=font(22), fill=(88, 94, 118))
    rounded_box(draw, (sl + 56, st + 458, sr - 56, st + 530), 20, fill=(242, 245, 251))
    draw.text((sl + 86, st + 480), "QR / PDF / история продажи", font=font(21, bold=True), fill=(60, 66, 92))
    draw.text((sl + 56, st + 594), "Расчётный лист: 12 продаж", font=font(23, bold=True), fill=(24, 128, 97))
    draw.text((sl + 56, st + 636), "Комиссия продавца: 10%", font=font(22), fill=(88, 94, 118))
    draw.text((sl + 56, st + 674), "Выплата водителю / гиду по диапазонам", font=font(22), fill=(88, 94, 118))
    draw_nav(draw, sl, sb, [("Бронь", False), ("Кошелёк", True), ("Билеты", False)])

    box_top = pills_y + 110
    rounded_box(draw, (120, box_top, 840, box_top + 380), 42, fill=(255, 255, 255, 215))
    draw.text((160, box_top + 44), "Финальная часть цикла", font=font(38, bold=True), fill=(28, 33, 58))
    points = [
        "После продажи билет сохраняется в приложении",
        "История бронирований и выручки доступна персоналу",
        "Администратор видит продажи и расчётные листы",
    ]
    y = box_top + 116
    for point in points:
        draw.ellipse((164, y + 12, 182, y + 30), fill=(24, 128, 97))
        draw.text((202, y), point, font=font(28), fill=(68, 74, 98))
        y += 76
    return img


def icon_image() -> Image.Image:
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base = gradient((size, size), (71, 171, 233), (103, 80, 164)).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle((18, 18, size - 18, size - 18), radius=110, fill=255)
    img.paste(base, (0, 0), mask)
    draw = ImageDraw.Draw(img)
    draw.polygon([(44, 340), (176, 228), (260, 320), (356, 214), (468, 340), (468, 468), (44, 468)], fill=(17, 100, 153, 255))
    draw.polygon([(58, 344), (174, 244), (248, 326), (350, 224), (452, 344)], fill=(25, 141, 191, 255))
    draw.rectangle((44, 348, 468, 468), fill=(33, 117, 191, 255))
    draw.ellipse((196, 86, 324, 214), fill=(255, 208, 78, 255))
    draw.ellipse((170, 146, 350, 326), fill=(255, 255, 255, 245))
    draw.ellipse((194, 172, 326, 304), fill=(242, 247, 255, 255))
    draw.polygon([(260, 206), (220, 244), (240, 244), (240, 286), (280, 286), (280, 244), (300, 244)], fill=(62, 115, 209, 255))
    draw.rounded_rectangle((184, 332, 338, 408), radius=26, fill=(255, 255, 255, 240))
    draw.rounded_rectangle((208, 348, 314, 390), radius=12, fill=(31, 94, 164, 255))
    draw.ellipse((224, 382, 248, 406), fill=(34, 53, 86, 255))
    draw.ellipse((274, 382, 298, 406), fill=(34, 53, 86, 255))
    return img


def save_outputs():
    shots = {
        "phone_01_excursions_dashboard": screenshot_excursions(),
        "phone_02_seat_booking": screenshot_booking(),
        "phone_03_staff_buses": screenshot_staff(),
        "phone_04_prices_schedule": screenshot_prices(),
        "phone_05_wallet_tickets": screenshot_wallet(),
    }
    for name, image in shots.items():
        png_path = OUT / f"{name}.png"
        jpg_path = OUT / f"{name}.jpg"
        image.convert("RGB").save(png_path, optimize=True)
        image.convert("RGB").save(jpg_path, quality=92, subsampling=0, optimize=True)
    icon = icon_image()
    icon.save(OUT / "icon_512.png", optimize=True)
    (OUT / "README.txt").write_text(
        "\n".join(
            [
                "RuStore assets for booking_krym / excursion app",
                "",
                "Icon:",
                " - icon_512.png",
                "",
                "Phone screenshots (16:9, 1920x1080):",
                " - phone_01_excursions_dashboard.jpg",
                " - phone_02_seat_booking.jpg",
                " - phone_03_staff_buses.jpg",
                " - phone_04_prices_schedule.jpg",
                " - phone_05_wallet_tickets.jpg",
                "",
                "PNG versions are also included if needed.",
            ]
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    save_outputs()
