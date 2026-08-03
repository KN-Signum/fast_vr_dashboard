from __future__ import annotations

import io
import threading
from datetime import datetime
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


_FONT_REGULAR = "PanelVR-DejaVuSans"
_FONT_BOLD = "PanelVR-DejaVuSans-Bold"
_FONT_LOCK = threading.Lock()
_fonts_registered = False

_PRIMARY = colors.HexColor("#1F568E")
_TEXT = colors.HexColor("#1E293B")
_MUTED = colors.HexColor("#64748B")
_BORDER = colors.HexColor("#D7E0EA")
_SURFACE = colors.HexColor("#F5F8FC")
_DANGER = colors.HexColor("#B91C1C")


def build_session_report(
    summary: dict[str, Any],
    *,
    app_version: str,
    generated_at: datetime | None = None,
) -> bytes:
    _register_fonts()
    generated = generated_at or datetime.now().astimezone()
    buffer = io.BytesIO()
    document = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=18 * mm,
        title=f"Raport z sesji VR - {summary.get('session_id', '')}",
        author="Panel NEXT",
        subject="Automatyczne podsumowanie sesji VR",
    )
    styles = _styles()
    story = [
        _report_header(summary, generated, styles),
        Spacer(1, 7 * mm),
        _section_heading("Pacjent i sesja", styles),
        Spacer(1, 2.5 * mm),
        _metadata_table(summary, styles),
        Spacer(1, 5 * mm),
    ]

    notes = str(summary.get("notes") or "").strip()
    if notes:
        story.extend(
            [
                _section_heading("Notatki przed sesją", styles),
                Spacer(1, 2.5 * mm),
                Paragraph(_paragraph_text(notes), styles["body"]),
                Spacer(1, 5 * mm),
            ]
        )

    post_session_notes = str(summary.get("post_session_notes") or "").strip()
    if post_session_notes:
        story.extend(
            [
                _section_heading("Notatki po sesji", styles),
                Spacer(1, 2.5 * mm),
                Paragraph(_paragraph_text(post_session_notes), styles["body"]),
                Spacer(1, 5 * mm),
            ]
        )

    story.extend(
        [
            _section_heading("Zarejestrowane dane", styles),
            Spacer(1, 2.5 * mm),
            _counts_table(summary, styles),
            Spacer(1, 5 * mm),
            _section_heading("Rozkład spojrzenia", styles),
            Spacer(1, 2.5 * mm),
            _eye_tracking_content(summary, styles),
            Spacer(1, 5 * mm),
            _section_heading("Zdarzenia obserwowane", styles),
            Spacer(1, 2.5 * mm),
            _events_content(summary, styles),
            Spacer(1, 7 * mm),
            Paragraph(
                "Raport został wygenerowany automatycznie przez Panel NEXT. "
                "Nie stanowi interpretacji ani diagnozy medycznej.",
                styles["disclaimer"],
            ),
        ]
    )

    def draw_footer(canvas, doc) -> None:
        canvas.saveState()
        canvas.setStrokeColor(_BORDER)
        canvas.setLineWidth(0.5)
        canvas.line(doc.leftMargin, 12 * mm, A4[0] - doc.rightMargin, 12 * mm)
        canvas.setFont(_FONT_REGULAR, 7)
        canvas.setFillColor(_MUTED)
        canvas.drawString(doc.leftMargin, 8 * mm, f"Panel NEXT {app_version}")
        canvas.drawRightString(
            A4[0] - doc.rightMargin,
            8 * mm,
            f"Strona {doc.page}",
        )
        canvas.restoreState()

    document.build(story, onFirstPage=draw_footer, onLaterPages=draw_footer)
    return buffer.getvalue()


def _register_fonts() -> None:
    global _fonts_registered
    if _fonts_registered:
        return
    with _FONT_LOCK:
        if _fonts_registered:
            return
        font_dir = Path(__file__).resolve().parent / "assets" / "fonts"
        pdfmetrics.registerFont(TTFont(_FONT_REGULAR, font_dir / "DejaVuSans.ttf"))
        pdfmetrics.registerFont(
            TTFont(_FONT_BOLD, font_dir / "DejaVuSans-Bold.ttf")
        )
        pdfmetrics.registerFontFamily(
            "PanelVR-DejaVuSans",
            normal=_FONT_REGULAR,
            bold=_FONT_BOLD,
        )
        _fonts_registered = True


def _styles() -> dict[str, ParagraphStyle]:
    return {
        "brand": ParagraphStyle(
            "ReportBrand",
            fontName=_FONT_BOLD,
            fontSize=12,
            leading=14,
            textColor=_PRIMARY,
        ),
        "title": ParagraphStyle(
            "ReportTitle",
            fontName=_FONT_BOLD,
            fontSize=19,
            leading=23,
            textColor=_TEXT,
            alignment=TA_RIGHT,
        ),
        "meta": ParagraphStyle(
            "ReportMeta",
            fontName=_FONT_REGULAR,
            fontSize=7.5,
            leading=10,
            textColor=_MUTED,
        ),
        "meta_right": ParagraphStyle(
            "ReportMetaRight",
            fontName=_FONT_REGULAR,
            fontSize=7.5,
            leading=10,
            textColor=_MUTED,
            alignment=TA_RIGHT,
        ),
        "section": ParagraphStyle(
            "ReportSection",
            fontName=_FONT_BOLD,
            fontSize=10.5,
            leading=13,
            textColor=_PRIMARY,
        ),
        "label": ParagraphStyle(
            "ReportLabel",
            fontName=_FONT_REGULAR,
            fontSize=7.5,
            leading=10,
            textColor=_MUTED,
        ),
        "body": ParagraphStyle(
            "ReportBody",
            fontName=_FONT_REGULAR,
            fontSize=9,
            leading=13,
            textColor=_TEXT,
        ),
        "body_bold": ParagraphStyle(
            "ReportBodyBold",
            fontName=_FONT_BOLD,
            fontSize=9,
            leading=13,
            textColor=_TEXT,
        ),
        "table_header": ParagraphStyle(
            "ReportTableHeader",
            fontName=_FONT_BOLD,
            fontSize=7.5,
            leading=10,
            textColor=colors.white,
        ),
        "table": ParagraphStyle(
            "ReportTable",
            fontName=_FONT_REGULAR,
            fontSize=7.5,
            leading=10,
            textColor=_TEXT,
        ),
        "disclaimer": ParagraphStyle(
            "ReportDisclaimer",
            fontName=_FONT_REGULAR,
            fontSize=7.5,
            leading=11,
            textColor=_MUTED,
        ),
        "danger": ParagraphStyle(
            "ReportDanger",
            fontName=_FONT_BOLD,
            fontSize=8,
            leading=11,
            textColor=_DANGER,
        ),
    }


def _report_header(
    summary: dict[str, Any],
    generated_at: datetime,
    styles: dict[str, ParagraphStyle],
) -> Table:
    session_id = escape(str(summary.get("session_id") or "—"))
    generated = generated_at.astimezone().strftime("%d.%m.%Y, %H:%M")
    table = Table(
        [
            [
                Paragraph("Panel NEXT", styles["brand"]),
                Paragraph("RAPORT Z SESJI VR", styles["title"]),
            ],
            [
                Paragraph(f"ID sesji: {session_id}", styles["meta"]),
                Paragraph(f"Wygenerowano: {generated}", styles["meta_right"]),
            ],
        ],
        colWidths=[82 * mm, 92 * mm],
    )
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 4),
                ("TOPPADDING", (0, 1), (-1, 1), 4),
                ("LINEBELOW", (0, 0), (-1, 0), 1, _PRIMARY),
            ]
        )
    )
    return table


def _section_heading(
    title: str,
    styles: dict[str, ParagraphStyle],
) -> KeepTogether:
    return KeepTogether(
        [
            Paragraph(escape(title.upper()), styles["section"]),
            Spacer(1, 1.5 * mm),
            Table(
                [[""]],
                colWidths=[174 * mm],
                rowHeights=[0.3 * mm],
                style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), _BORDER)]),
            ),
        ]
    )


def _metadata_table(
    summary: dict[str, Any],
    styles: dict[str, ParagraphStyle],
) -> Table:
    rows = [
        (
            "ID pacjenta",
            str(summary.get("patient_id") or "—"),
            "Preferowana ręka",
            _preferred_hand(summary.get("preferred_hand")),
        ),
        (
            "Rozpoczęcie",
            _format_datetime(summary.get("started_at")),
            "Zakończenie",
            _format_datetime(summary.get("ended_at")),
        ),
        (
            "Czas trwania",
            _format_duration(summary.get("duration_seconds")),
            "Status",
            _status(summary.get("status")),
        ),
    ]
    data = [
        [
            Paragraph(escape(label_a), styles["label"]),
            Paragraph(_paragraph_text(value_a), styles["body_bold"]),
            Paragraph(escape(label_b), styles["label"]),
            Paragraph(_paragraph_text(value_b), styles["body_bold"]),
        ]
        for label_a, value_a, label_b, value_b in rows
    ]
    table = Table(data, colWidths=[29 * mm, 58 * mm, 29 * mm, 58 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), _SURFACE),
                ("BOX", (0, 0), (-1, -1), 0.5, _BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.3, _BORDER),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def _counts_table(
    summary: dict[str, Any],
    styles: dict[str, ParagraphStyle],
) -> Table:
    counts = summary.get("counts")
    if not isinstance(counts, dict):
        counts = {}
    eeg_value = (
        _format_count(counts.get("eeg_records", 0))
        if summary.get("eeg_enabled_at_start", True)
        else "Wyłączone przez operatora"
    )
    entries = [
        ("Pakiety EEG", eeg_value),
        ("Próbki śledzenia wzroku", counts.get("eye_tracking_records", 0)),
        ("Zdarzenia VR", counts.get("vr_events", 0)),
        ("Klatki VR", counts.get("vr_frames", 0)),
        ("Zdarzenia obserwowane", counts.get("session_events", 0)),
        ("Utracone rekordy", summary.get("dropped_records", 0)),
    ]
    data = []
    for label, value in entries:
        is_drop_warning = label == "Utracone rekordy" and isinstance(value, int) and value > 0
        label_style = styles["danger"] if is_drop_warning else styles["table"]
        value_style = styles["danger"] if is_drop_warning else styles["body_bold"]
        data.append(
            [
                Paragraph(escape(label), label_style),
                Paragraph(
                    value if isinstance(value, str) else _format_count(value),
                    value_style,
                ),
            ]
        )
    table = Table(data, colWidths=[137 * mm, 37 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.5, _BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.3, _BORDER),
                ("ROWBACKGROUNDS", (0, 0), (-1, -1), [colors.white, _SURFACE]),
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _eye_tracking_content(
    summary: dict[str, Any],
    styles: dict[str, ParagraphStyle],
):
    analysis = summary.get("eye_tracking_analysis")
    if not isinstance(analysis, dict) or int(analysis.get("valid_points") or 0) <= 0:
        return Paragraph(
            "Brak poprawnych punktów spojrzenia z projekcją na ekran.",
            styles["body"],
        )

    total = int(analysis.get("total_records") or 0)
    valid = int(analysis.get("valid_points") or 0)
    valid_percent = float(analysis.get("valid_percent") or 0)
    heatmap_values = analysis.get("heatmap_percent")
    if not isinstance(heatmap_values, list) or not heatmap_values:
        return Paragraph("Brak danych mapy spojrzenia.", styles["body"])

    numeric_heatmap = [
        [float(value) if isinstance(value, (int, float)) else 0.0 for value in row]
        for row in heatmap_values
        if isinstance(row, list)
    ]
    if not numeric_heatmap or not numeric_heatmap[0]:
        return Paragraph("Brak danych mapy spojrzenia.", styles["body"])

    heatmap = _eye_tracking_heatmap(numeric_heatmap, styles)
    regions = analysis.get("regions")
    if not isinstance(regions, dict):
        regions = {}
    region_table = _eye_tracking_region_table(regions, styles)
    horizontal = analysis.get("horizontal")
    vertical = analysis.get("vertical")
    if not isinstance(horizontal, dict):
        horizontal = {}
    if not isinstance(vertical, dict):
        vertical = {}

    return KeepTogether(
        [
            Paragraph(
                f"Poprawne punkty: {_format_count(valid)} / {_format_count(total)} "
                f"({_format_percent(valid_percent)})",
                styles["body"],
            ),
            Spacer(1, 2 * mm),
            heatmap,
            Spacer(1, 2 * mm),
            Paragraph(
                "Poziomo: "
                f"lewo {_format_percent(horizontal.get('left'))}, "
                f"środek {_format_percent(horizontal.get('center'))}, "
                f"prawo {_format_percent(horizontal.get('right'))}. "
                "Pionowo: "
                f"góra {_format_percent(vertical.get('top'))}, "
                f"środek {_format_percent(vertical.get('middle'))}, "
                f"dół {_format_percent(vertical.get('bottom'))}.",
                styles["body"],
            ),
            Spacer(1, 2 * mm),
            region_table,
            Spacer(1, 1.5 * mm),
            Paragraph(
                "Opisowy rozkład zapisanych punktów spojrzenia; bez interpretacji "
                "diagnostycznej.",
                styles["disclaimer"],
            ),
        ]
    )


def _eye_tracking_heatmap(
    values: list[list[float]],
    styles: dict[str, ParagraphStyle],
) -> Table:
    column_count = max(len(row) for row in values)
    normalized = [row + [0.0] * (column_count - len(row)) for row in values]
    maximum = max((value for row in normalized for value in row), default=0.0)
    grid = Table(
        [["" for _ in range(column_count)] for _ in normalized],
        colWidths=[144 * mm / column_count] * column_count,
        rowHeights=[5 * mm] * len(normalized),
    )
    commands = [
        ("BOX", (0, 0), (-1, -1), 0.5, _BORDER),
        ("INNERGRID", (0, 0), (-1, -1), 0.25, colors.white),
    ]
    for row_index, row in enumerate(normalized):
        for column_index, value in enumerate(row):
            commands.append(
                (
                    "BACKGROUND",
                    (column_index, row_index),
                    (column_index, row_index),
                    _heatmap_color(value, maximum),
                )
            )
    grid.setStyle(TableStyle(commands))
    return Table(
        [
            ["", Paragraph("GÓRA", styles["label"]), ""],
            [Paragraph("LEWO", styles["label"]), grid, Paragraph("PRAWO", styles["label"])],
            ["", Paragraph("DÓŁ", styles["label"]), ""],
        ],
        colWidths=[15 * mm, 144 * mm, 15 * mm],
        style=TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
            ]
        ),
    )


def _eye_tracking_region_table(
    regions: dict[str, Any],
    styles: dict[str, ParagraphStyle],
) -> Table:
    rows = [
        [
            Paragraph("", styles["table_header"]),
            Paragraph("Lewo", styles["table_header"]),
            Paragraph("Środek", styles["table_header"]),
            Paragraph("Prawo", styles["table_header"]),
        ]
    ]
    for key, label in (("top", "Góra"), ("middle", "Środek"), ("bottom", "Dół")):
        rows.append(
            [
                Paragraph(label, styles["table_header"]),
                Paragraph(_format_percent(regions.get(f"{key}_left")), styles["table"]),
                Paragraph(_format_percent(regions.get(f"{key}_center")), styles["table"]),
                Paragraph(_format_percent(regions.get(f"{key}_right")), styles["table"]),
            ]
        )
    table = Table(rows, colWidths=[36 * mm, 46 * mm, 46 * mm, 46 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), _PRIMARY),
                ("BACKGROUND", (0, 1), (0, -1), _PRIMARY),
                ("BOX", (0, 0), (-1, -1), 0.5, _BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.3, _BORDER),
                ("ALIGN", (1, 1), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def _heatmap_color(value: float, maximum: float):
    ratio = 0.0 if maximum <= 0 else max(0.0, min(value / maximum, 1.0))
    ratio = 0.08 + ratio * 0.92 if value > 0 else 0.0
    return colors.Color(
        _SURFACE.red + (_PRIMARY.red - _SURFACE.red) * ratio,
        _SURFACE.green + (_PRIMARY.green - _SURFACE.green) * ratio,
        _SURFACE.blue + (_PRIMARY.blue - _SURFACE.blue) * ratio,
    )


def _format_percent(value: Any) -> str:
    try:
        return f"{float(value):.1f}%"
    except (TypeError, ValueError):
        return "0.0%"


def _events_content(
    summary: dict[str, Any],
    styles: dict[str, ParagraphStyle],
):
    events = summary.get("session_events")
    if not isinstance(events, list) or not events:
        return Paragraph("Brak zgłoszonych zdarzeń.", styles["body"])

    rows = [
        [
            Paragraph("Czas", styles["table_header"]),
            Paragraph("Kategoria", styles["table_header"]),
            Paragraph("Zdarzenie", styles["table_header"]),
            Paragraph("Notatka", styles["table_header"]),
        ]
    ]
    for event in events:
        if not isinstance(event, dict):
            continue
        rows.append(
            [
                Paragraph(
                    _format_elapsed(event.get("elapsed_ms")), styles["table"]
                ),
                Paragraph(
                    _paragraph_text(_event_category(event.get("category"))),
                    styles["table"],
                ),
                Paragraph(
                    _paragraph_text(str(event.get("label") or "—")),
                    styles["table"],
                ),
                Paragraph(
                    _paragraph_text(_truncate(str(event.get("note") or "—"), 800)),
                    styles["table"],
                ),
            ]
        )

    table = Table(
        rows,
        colWidths=[19 * mm, 36 * mm, 50 * mm, 69 * mm],
        repeatRows=1,
        splitByRow=1,
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), _PRIMARY),
                ("BOX", (0, 0), (-1, -1), 0.5, _BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.3, _BORDER),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, _SURFACE]),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _paragraph_text(value: str) -> str:
    return escape(value).replace("\n", "<br/>")


def _truncate(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return value[: limit - 1].rstrip() + "…"


def _format_datetime(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return "—"
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value
    return parsed.astimezone().strftime("%d.%m.%Y, %H:%M:%S")


def _format_duration(value: Any) -> str:
    if not isinstance(value, (int, float)) or value < 0:
        return "—"
    total_seconds = round(value)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    parts = []
    if hours:
        parts.append(f"{hours} godz.")
    if minutes or hours:
        parts.append(f"{minutes} min")
    parts.append(f"{seconds} s")
    return " ".join(parts)


def _format_elapsed(value: Any) -> str:
    if not isinstance(value, (int, float)) or value < 0:
        return "—"
    total_seconds = round(value / 1000)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def _format_count(value: Any) -> str:
    count = value if isinstance(value, int) and value >= 0 else 0
    return f"{count:,}".replace(",", " ")


def _preferred_hand(value: Any) -> str:
    return {
        "left": "Lewa",
        "right": "Prawa",
        "ambidextrous": "Oburęczność",
        "not_specified": "Nie określono",
    }.get(str(value), "Nie określono")


def _status(value: Any) -> str:
    return {
        "active": "Aktywna",
        "completed": "Zakończona",
        "interrupted": "Przerwana",
    }.get(str(value), str(value or "—"))


def _event_category(value: Any) -> str:
    return {
        "patient_behavior": "Zachowanie pacjenta",
        "task": "Zadanie",
        "support": "Wsparcie",
        "custom": "Własne",
    }.get(str(value), str(value or "—"))
