#!/usr/bin/env python3
"""
Generate PNG charts for opt/docs/PROJECT_REPORT_ALL_PHASES.md
from opt/synth/reports CSVs and phase5_measure.json.

Requires: Pillow (DejaVu Sans fonts on Linux).
Run from repo root: python3 opt/scripts/generate_report_figures.py
"""
from __future__ import annotations

import csv
import json
import math
import re
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OPT = Path(__file__).resolve().parent.parent
REPORTS = OPT / "synth" / "reports"
FIGURES = OPT / "docs" / "figures"
FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
FONT_BOLD = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")

# Harmonious palette (saturated enough for projection, distinct categories)
PALETTE_DEFAULT = [
    (37, 99, 235),    # blue
    (234, 88, 12),   # orange
    (13, 148, 136),  # teal
    (180, 83, 9),    # amber
    (124, 58, 237),  # violet
    (79, 70, 229),   # indigo
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    p = FONT_BOLD if bold and FONT_BOLD.exists() else FONT
    return ImageFont.truetype(str(p), size=size)


def _tb(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int, int, int]:
    return draw.textbbox((0, 0), text, font=font)


def _tw(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> int:
    l, t, r, b = _tb(draw, text, font)
    return r - l


def _th(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> int:
    l, t, r, b = _tb(draw, text, font)
    return b - t


def _rot_resample():
    try:
        return Image.Resampling.BICUBIC
    except AttributeError:
        return Image.BICUBIC


def _paste_rotated_ylabel(
    target: Image.Image,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    cx: int,
    cy: int,
) -> None:
    """Draw axis title parallel to the Y axis (bottom-to-top), using rotate+paste."""
    probe = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    bbox = probe.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    pad = 6
    layer = Image.new("RGBA", (tw + 2 * pad, th + 2 * pad), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.text((pad - bbox[0], pad - bbox[1]), text, font=font, fill=(*fill, 255))
    rot = layer.rotate(90, expand=True, resample=_rot_resample())
    rx, ry = rot.size
    target.paste(rot, (cx - rx // 2, cy - ry // 2), rot)


def _mix(c: tuple[int, int, int], toward: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a + (b - a) * t) for a, b in zip(c, toward))


def _darken(c: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return _mix(c, (20, 24, 32), t)


def _label_lines(s: str, max_chars: int = 20) -> list[str]:
    """Up to 2 horizontal lines for category labels (stable alignment under bars)."""
    s = s.strip()
    if not s:
        return [""]
    if len(s) <= max_chars:
        return [s]
    cut = s.rfind(" ", 6, max_chars + 1)
    if cut <= 0:
        cut = max_chars
    a, b = s[:cut].strip(), s[cut:].strip()
    if len(b) > max_chars:
        b = b[: max_chars - 1] + "…"
    return [a, b]


def save_figure_png(img: Image.Image, base: Path) -> None:
    base.parent.mkdir(parents=True, exist_ok=True)
    png = base.with_suffix(".png")
    img.save(png, "PNG", optimize=True)
    print("Wrote", png)


def read_phase1_lut() -> tuple[list[str], list[int]]:
    path = REPORTS / "phase1_area_comparison.csv"
    labels, vals = [], []
    with path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            name = row["config"].split("(")[0].strip()
            labels.append(name.replace("Baseline ", "").replace("Optimized", "Opt"))
            vals.append(int(row["SB_LUT4"]))
    return labels, vals


def read_phase2_rows() -> dict[str, dict[str, str]]:
    path = REPORTS / "phase2_performance.csv"
    out: dict[str, dict[str, str]] = {}
    with path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            k = row.get("config") or row.get(list(row.keys())[0])
            if k:
                out[k.strip()] = row
    return out


def read_phase3_area() -> tuple[list[str], list[int], list[int]]:
    path = REPORTS / "phase3_area_final.csv"
    labels, lut, carry = [], [], []
    with path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            lab = row["label"].strip()
            short = (
                lab.replace("Baseline ", "")
                .replace("Optimized", "Opt")
                .replace(" (Core + KSA)", "+KSA")
                .split("(")[0]
                .strip()
            )
            labels.append(short[:14])
            lut.append(int(row["SB_LUT4"]))
            carry.append(int(row["SB_CARRY"]))
    return labels, lut, carry


def read_phase3_fmax() -> tuple[list[str], list[float | None]]:
    path = REPORTS / "phase3_timing.csv"
    labels, fmax = [], []
    with path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            lab = row["label"].strip()
            short = (
                lab.replace("Baseline ", "")
                .replace("Optimized", "Opt")
                .replace(" (Core + KSA)", "+KSA")
                .split("(")[0]
                .strip()
            )[:12]
            labels.append(short)
            raw = (row.get("T1_fmax_mhz") or "").strip()
            if raw and raw.lower() != "none":
                try:
                    fmax.append(float(raw))
                except ValueError:
                    fmax.append(None)
            else:
                fmax.append(None)
    return labels, fmax


def read_switching() -> tuple[list[str], list[int]]:
    path = REPORTS / "switching_comparison.txt"
    text = path.read_text()
    labels, vals = [], []
    for m in re.finditer(
        r"^\s*(Baseline\s+[AB]|Optimized)\s+(\d+)\s+(\d+)", text, re.MULTILINE
    ):
        raw = m.group(1).strip()
        if raw.startswith("Baseline "):
            labels.append(raw.replace("Baseline ", ""))
        else:
            labels.append("Opt")
        vals.append(int(m.group(2)))
    if len(labels) < 3:
        labels = ["A", "B", "Opt"]
        vals = [17839, 6748, 20301]
    return labels, vals


def read_phase5_fmax() -> tuple[list[str], list[float]]:
    path = REPORTS / "phase5_measure.json"
    if not path.exists():
        return ["-dsp", "-dsp -abc2"], [21.2, 15.94]
    d = json.loads(path.read_text())
    labs, vals = [], []
    for k in ("optimized", "optimized_abc2"):
        if k not in d:
            continue
        labs.append("-dsp" if k == "optimized" else "-dsp -abc2")
        v = d[k].get("fmax_mhz") or "0"
        vals.append(float(str(v).replace(" MHz", "")))
    return labs, vals


def draw_bar_chart(
    title: str,
    ylabel: str,
    xlabels: list[str],
    values: list[float | None],
    colors: list[tuple[int, int, int]] | None = None,
    width: int = 2100,
    height: int = 1280,
    na_indices: set[int] | None = None,
    na_caption: str = "PnR fail",
    format_bar_value: Callable[[float], str] | None = None,
) -> Image.Image:
    na_indices = na_indices or set()
    # Flat, neutral canvas (no vertical gradient)
    img = Image.new("RGB", (width, height), (248, 250, 252))
    draw = ImageDraw.Draw(img)

    # Same size for Y tick numbers, X category lines, and footer; axis name bold same size
    font_title = load_font(46, bold=True)
    font_axis = load_font(30)
    font_axis_title = load_font(30, bold=True)
    font_val = load_font(32, bold=True)
    font_na = load_font(30, bold=True)

    numeric = [v for v in values if v is not None and not (isinstance(v, float) and math.isnan(v))]
    y_max = max(numeric) * 1.12 if numeric else 1.0
    if y_max < 1e-6:
        y_max = 1.0

    ticks = 5
    tick_strings = []
    for i in range(ticks + 1):
        yv = y_max * i / ticks
        if y_max >= 500:
            tick_strings.append(f"{yv:.0f}")
        elif y_max >= 50:
            tick_strings.append(f"{yv:.0f}")
        elif y_max >= 5:
            tick_strings.append(f"{yv:.1f}")
        else:
            tick_strings.append(f"{yv:.2f}")
    tick_w = max(_tw(draw, s, font_axis) for s in tick_strings) if tick_strings else 48
    # Y-axis title is rotated parallel to Y; horizontal clearance ~= one line of text height.
    ylabel_th = _th(draw, ylabel, font_axis_title) + 24
    ylabel_gutter = max(88, ylabel_th)
    pad_l = int(tick_w + 44 + ylabel_gutter)
    pad_r = 80
    title_bb = _tb(draw, title, font_title)
    title_h = title_bb[3] - title_bb[1]
    pad_t = int(title_h + 88)
    if numeric:
        if format_bar_value is not None:
            max_val_str = max((format_bar_value(v) for v in numeric), key=len)
        else:
            max_val_str = max((f"{v:g}" for v in numeric), key=len)
    else:
        max_val_str = "0"
    val_h = _th(draw, max_val_str, font_val) + 22
    pad_t = max(pad_t, title_h + 56 + val_h)

    line_h = _th(draw, "Mg", font_axis) + 8
    max_x_lines = max(len(_label_lines(x)) for x in xlabels) if xlabels else 1
    pad_b = int(52 + line_h * max_x_lines + 36)

    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    plot_h = max(plot_h, 360)

    # Title + accent underline
    title_y = 32
    draw.text((width // 2, title_y), title, fill=(15, 23, 42), font=font_title, anchor="mt")
    tw_title = min(_tw(draw, title, font_title), width - 120)
    ux0 = (width - tw_title) // 2
    draw.line(
        [(ux0, title_y + title_h + 10), (ux0 + tw_title, title_y + title_h + 10)],
        fill=(37, 99, 235),
        width=4,
    )

    # Plot panel — flat, no shadow
    card_pad = 4
    draw.rounded_rectangle(
        [pad_l, pad_t, pad_l + plot_w, pad_t + plot_h],
        radius=10,
        fill=(255, 255, 255),
        outline=(226, 232, 240),
        width=1,
    )
    inner_l = pad_l + card_pad
    inner_t = pad_t + card_pad
    inner_r = pad_l + plot_w - card_pad
    inner_b = pad_t + plot_h - card_pad

    for i in range(ticks + 1):
        ypix = inner_b - (i / ticks) * (inner_b - inner_t)
        draw.line([(inner_l, ypix), (inner_r, ypix)], fill=(241, 245, 249), width=1)
        draw.text(
            (inner_l - 20, ypix),
            tick_strings[i],
            fill=(71, 85, 105),
            font=font_axis,
            anchor="rm",
        )

    y_mid = (inner_t + inner_b) // 2
    ylabel_cx = max(48, tick_w + ylabel_gutter // 2 + 8)
    _paste_rotated_ylabel(img, ylabel, font_axis_title, (51, 65, 85), ylabel_cx, y_mid)

    n = len(xlabels)
    gap = 0.15
    bar_w = (inner_r - inner_l) / (n + (n + 1) * gap)
    gap_px = bar_w * gap
    palette = colors or PALETTE_DEFAULT

    for i, (lab, val) in enumerate(zip(xlabels, values)):
        x0 = inner_l + gap_px + i * (bar_w + gap_px)
        x1 = x0 + bar_w
        cx = (x0 + x1) // 2
        col = palette[i % len(palette)]
        r_rad = min(6, max(2, int(bar_w * 0.06)))

        if i in na_indices or val is None:
            stub_h = min(140.0, (inner_b - inner_t) * 0.38)
            y_stub = inner_b - stub_h
            draw.rounded_rectangle(
                [x0, y_stub, x1, inner_b],
                radius=r_rad,
                fill=(254, 226, 226),
                outline=(220, 38, 38),
                width=1,
            )
            draw.text((cx, (y_stub + inner_b) // 2), na_caption, fill=(127, 29, 29), font=font_na, anchor="mm")
        else:
            assert val is not None
            h = max(6.0, (val / y_max) * (inner_b - inner_t))
            y0 = inner_b - h
            draw.rounded_rectangle(
                [x0, y0, x1, inner_b],
                radius=r_rad,
                fill=col,
                outline=_darken(col, 0.15),
                width=1,
            )
            if format_bar_value is not None:
                vtxt = format_bar_value(float(val))
            else:
                vtxt = f"{val:g}"
            vh = _th(draw, vtxt, font_val)
            if y0 - vh - 22 < inner_t:
                draw.text((cx, y0 + 30), vtxt, fill=(255, 255, 255), font=font_val, anchor="mt")
            else:
                draw.text((cx, y0 - 18), vtxt, fill=(15, 23, 42), font=font_val, anchor="mb")

        ly0 = inner_b + 18
        for li, line in enumerate(_label_lines(lab)):
            draw.text(
                (cx, ly0 + li * line_h),
                line,
                fill=(71, 85, 105),
                font=font_axis,
                anchor="mt",
            )

    draw.text(
        (pad_l + plot_w // 2, height - 32),
        "Configuration",
        fill=(100, 116, 139),
        font=font_axis,
        anchor="mm",
    )

    return img


def draw_scatter_tradeoff(path_base: Path) -> None:
    path = REPORTS / "master_metrics.csv"
    pts: list[tuple[str, float, float]] = []
    want = {"baseline_A", "baseline_B", "optimized"}
    with path.open(newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            cfg = row.get("config", "")
            if cfg not in want:
                continue
            try:
                lut4 = float(row.get("SB_LUT4") or "")
                lat = float(row.get("pcpi_latency") or "")
            except ValueError:
                continue
            lab = {"baseline_A": "A", "baseline_B": "B", "optimized": "Opt"}[cfg]
            pts.append((lab, lut4, lat))

    w, h = 2680, 1320
    img = Image.new("RGB", (w, h), (248, 250, 252))
    draw = ImageDraw.Draw(img)

    ft = load_font(46, bold=True)
    fs = load_font(26)
    fnum = load_font(28)
    faxis_name = load_font(30, bold=True)
    fleg_title = load_font(28, bold=True)
    fleg_body = load_font(26)

    title = "SB_LUT4 vs PCPI latency (trade space)"
    subtitle = (
        "Lower-left is better  ·  A: iterative shim  ·  B: native fast (UP5K PnR failed)  ·  Opt: Vedic + KSA"
    )
    draw.text((w // 2, 44), title, fill=(15, 23, 42), font=ft, anchor="mt")
    draw.text((w // 2, 108), subtitle, fill=(71, 85, 105), font=fs, anchor="mt")
    tw_line = _tw(draw, title, ft)
    lx0 = (w - tw_line) // 2
    draw.line([(lx0, 142), (lx0 + tw_line, 142)], fill=(37, 99, 235), width=4)

    xs = [p[1] for p in pts]
    ys = [p[2] for p in pts]
    xmin, xmax = min(xs) * 0.88, max(xs) * 1.10
    ymin, ymax = 0.2, max(ys) * 1.28

    x_title = "SB_LUT4 (iCE40 post-flow primitives)"
    y_title = "PCPI latency (cycles, simulation)"
    y_title_th = _th(draw, y_title, faxis_name) + 28
    x_title_h = _th(draw, x_title, fnum) + 40
    tick_w_sc = max(_tw(draw, f"{yv:.0f}", fnum) for yv in [ymin + (i / 4) * (ymax - ymin) for i in range(5)])
    pad_l = int(tick_w_sc + y_title_th + 52)
    pad_legend = 420
    pad_r = pad_legend + 48
    pad_t = 188
    pad_b = int(x_title_h + 56)

    pw, ph = w - pad_l - pad_r, h - pad_t - pad_b
    draw.rounded_rectangle(
        [pad_l, pad_t, pad_l + pw, pad_t + ph],
        radius=10,
        fill=(255, 255, 255),
        outline=(226, 232, 240),
        width=1,
    )

    for gi in range(5):
        gx = pad_l + (gi / 4) * pw
        draw.line([(gx, pad_t), (gx, pad_t + ph)], fill=(241, 245, 249), width=1)
    for gi in range(5):
        gy = pad_t + (gi / 4) * ph
        draw.line([(pad_l, gy), (pad_l + pw, gy)], fill=(241, 245, 249), width=1)

    for i in range(5):
        xv = xmin + (i / 4) * (xmax - xmin)
        tx = pad_l + (i / 4) * pw
        draw.text((tx, pad_t + ph + 18), f"{xv:.0f}", fill=(71, 85, 105), font=fnum, anchor="mt")
    for i in range(5):
        yv = ymin + (i / 4) * (ymax - ymin)
        ty = pad_t + ph - (i / 4) * ph
        draw.text((pad_l - 20, ty), f"{yv:.0f}", fill=(71, 85, 105), font=fnum, anchor="rm")

    draw.text((pad_l + pw // 2, h - 32), x_title, fill=(51, 65, 85), font=faxis_name, anchor="mm")
    y_axis_cx = max(36, tick_w_sc + y_title_th // 2 + 10)
    _paste_rotated_ylabel(img, y_title, faxis_name, (51, 65, 85), y_axis_cx, pad_t + ph // 2)

    colors = {"A": (37, 99, 235), "B": (234, 88, 12), "Opt": (13, 148, 136)}
    by_lab = {p[0]: (p[1], p[2]) for p in pts}
    for lab, xl, yl in pts:
        px = pad_l + (xl - xmin) / (xmax - xmin) * pw
        py = pad_t + ph - (yl - ymin) / (ymax - ymin) * ph
        rad = 26
        c = colors.get(lab, (100, 100, 120))
        draw.ellipse([px - rad, py - rad, px + rad, py + rad], fill=c, outline=(51, 65, 85), width=2)

    legend_x = pad_l + pw + 36
    y_cur = pad_t + 28
    draw.text((legend_x, y_cur), "Legend", fill=(15, 23, 42), font=fleg_title, anchor="lt")
    y_cur += 44
    entries = [
        ("A", "Baseline A", "Iterative multiply path"),
        ("B", "Baseline B", "Native fast_mul (PnR fail)"),
        ("Opt", "Optimized", "Vedic + KSA + PCPI"),
    ]
    row_h = 102
    for key, name, note in entries:
        if key not in by_lab:
            continue
        xl, yl = by_lab[key]
        col = colors[key]
        sw = 30
        draw.rounded_rectangle(
            [legend_x, y_cur, legend_x + sw, y_cur + sw],
            radius=6,
            fill=col,
            outline=_darken(col, 0.15),
            width=1,
        )
        tx = legend_x + sw + 18
        draw.text((tx, y_cur), name, fill=(15, 23, 42), font=fleg_title, anchor="lt")
        draw.text((tx, y_cur + 34), note, fill=(71, 85, 105), font=fleg_body, anchor="lt")
        metrics = f"SB_LUT4 = {int(xl):,}  ·  latency = {int(yl)} cycles".replace(",", " ")
        draw.text((tx, y_cur + 66), metrics, fill=(51, 65, 85), font=fleg_body, anchor="lt")
        y_cur += row_h

    draw.text(
        (legend_x, pad_t + ph - 8),
        "Markers only in plot; values from master_metrics.csv",
        fill=(148, 163, 184),
        font=load_font(22),
        anchor="lb",
    )

    save_figure_png(img, path_base)


def _draw_phases_flow(path_base: Path) -> None:
    w, h = 2400, 680
    img = Image.new("RGB", (w, h), (248, 250, 252))
    draw = ImageDraw.Draw(img)
    ft = load_font(44, bold=True)
    fb = load_font(34)
    phases = [
        ("P1", "RTL + area\nframework"),
        ("P2", "Sim + perf +\nswitching"),
        ("P3", "PnR + timing +\ncomposites"),
        ("P4", "Formal plan\n(F1–F5)"),
        ("P5", "Gate + synth\nA/B (-abc2)"),
    ]
    n = len(phases)
    box_w = 330
    gap = 52
    total_w = n * box_w + (n - 1) * gap
    x0 = (w - total_w) // 2
    y0 = 200
    box_h = 258
    fills = [(37, 99, 235), (13, 148, 136), (124, 58, 237), (234, 88, 12), (79, 70, 229)]
    for i, (tag, desc) in enumerate(phases):
        x = x0 + i * (box_w + gap)
        col = fills[i % len(fills)]
        draw.rounded_rectangle(
            [x, y0, x + box_w, y0 + box_h],
            radius=12,
            fill=col,
            outline=_darken(col, 0.12),
            width=1,
        )
        draw.text((x + box_w // 2, y0 + 58), tag, fill=(255, 255, 255), font=ft, anchor="mm")
        draw.text((x + box_w // 2, y0 + 158), desc, fill=(255, 255, 255), font=fb, anchor="mm")
        if i < n - 1:
            ax = x + box_w + 10
            mid = y0 + box_h // 2
            draw.line([(ax, mid), (ax + gap - 24, mid)], fill=(100, 116, 139), width=5)
            draw.polygon(
                [(ax + gap - 10, mid), (ax + gap - 28, mid - 14), (ax + gap - 28, mid + 14)],
                fill=(100, 116, 139),
            )
    fph = load_font(46, bold=True)
    ptitle = "Project phases — high-level pipeline"
    draw.text((w // 2, 56), ptitle, fill=(15, 23, 42), font=fph, anchor="mt")
    tw = _tw(draw, ptitle, fph)
    lx0 = (w - tw) // 2
    th = _th(draw, ptitle, fph)
    draw.line([(lx0, 56 + th + 14), (lx0 + tw, 56 + th + 14)], fill=(37, 99, 235), width=6)
    save_figure_png(img, path_base)


def _draw_phases_detail_block(path_base: Path) -> None:
    """Block diagram aligned with the Mermaid phase breakdown in PROJECT_REPORT_ALL_PHASES.md."""
    w, h = 3000, 1720
    img = Image.new("RGB", (w, h), (248, 250, 252))
    draw = ImageDraw.Draw(img)
    fhdr = load_font(38, bold=True)
    ftag = load_font(30, bold=True)
    fsub = load_font(22, bold=True)
    fitem = load_font(21)

    phases_data: list[tuple[str, str, tuple[int, int, int], list[str]]] = [
        (
            "P1",
            "RTL + area framework",
            (37, 99, 235),
            [
                "KSA 32-bit adder",
                "Vedic 2x2 .. 32x32 hierarchy, CSA + pipelined KSA",
                "pcpi_vedic_mul + PicoRV32 integration",
                "Unit TBs, lint / quality gates",
                "Yosys stat -> phase1_area_comparison.csv",
            ],
        ),
        (
            "P2",
            "Simulation + performance + switching",
            (13, 148, 136),
            [
                "mul_test integration TB (total cycles)",
                "Average PCPI latency TB",
                "Switching proxy W1 (transition counts)",
                "phase2_performance.csv + summaries",
            ],
        ),
        (
            "P3",
            "PnR + timing + composites",
            (124, 58, 237),
            [
                "nextpnr iCE40-UP5K flow",
                "SB_LUT4 / SB_CARRY post-route metrics",
                "Routed Fmax (phase3_timing.csv)",
                "ADP, MOPS/LUT (phase3_composites.csv)",
            ],
        ),
        (
            "P4",
            "Formal verification (F1-F5)",
            (234, 88, 12),
            [
                "F1 KSA (sby)",
                "F2 Vedic blocks (sby / SMT hierarchy)",
                "F3 PCPI protocol (run_smtbmc)",
                "F4 arithmetic equivalence",
                "F5 RVFI (MUL-only or full ISA)",
            ],
        ),
        (
            "P5",
            "Regression gate + synth A/B",
            (79, 70, 229),
            [
                "Lint, Vedic quick sim, reduced PCPI sim",
                "PHASE4_FAST formal (waived slow legs)",
                "PnR: -dsp vs -dsp -abc2 (Yosys)",
                "phase5_measure.json + gate bundle",
            ],
        ),
    ]

    main_title = "Project phases — deliverables (same content as Mermaid diagram in report)"
    ty = 34
    draw.text((w // 2, ty), main_title, fill=(15, 23, 42), font=fhdr, anchor="mt")
    twm = _tw(draw, main_title, fhdr)
    thm = _th(draw, main_title, fhdr)
    lx0 = (w - twm) // 2
    draw.line([(lx0, ty + thm + 12), (lx0 + twm, ty + thm + 12)], fill=(37, 99, 235), width=5)

    y0 = ty + thm + 36
    card_h = h - y0 - 56
    gap = 16
    ncols = len(phases_data)
    margin_x = 48
    usable = w - 2 * margin_x - (ncols - 1) * gap
    col_w = usable / ncols

    for i, (tag, subtitle, col, lines) in enumerate(phases_data):
        x = int(margin_x + i * (col_w + gap))
        cw = int(col_w)
        band_h = 96
        draw.rounded_rectangle(
            [x, y0, x + cw, y0 + band_h],
            radius=10,
            fill=col,
            outline=_darken(col, 0.12),
            width=1,
        )
        draw.text((x + cw // 2, y0 + 28), tag, fill=(255, 255, 255), font=ftag, anchor="mm")
        sub_lines = _label_lines(subtitle, max_chars=22)
        sy = y0 + 52
        for si, sl in enumerate(sub_lines[:2]):
            draw.text(
                (x + cw // 2, sy + si * 24),
                sl,
                fill=(255, 255, 255),
                font=fsub,
                anchor="mm",
            )

        body_top = y0 + band_h + 10
        draw.rounded_rectangle(
            [x + 2, body_top, x + cw - 2, y0 + card_h],
            radius=10,
            fill=(255, 255, 255),
            outline=(226, 232, 240),
            width=1,
        )
        ly = body_top + 20
        for line in lines:
            draw.text((x + 14, ly), f"- {line}", fill=(51, 65, 85), font=fitem, anchor="lt")
            ly += _th(draw, line, fitem) + 12

        if i < ncols - 1:
            ax0 = x + cw + 4
            ax1 = x + cw + gap - 4
            amy = int(y0 + card_h * 0.52)
            draw.line([(ax0, amy), (ax1 - 14, amy)], fill=(100, 116, 139), width=5)
            draw.polygon(
                [(ax1, amy), (ax1 - 18, amy - 12), (ax1 - 18, amy + 12)],
                fill=(100, 116, 139),
            )

    save_figure_png(img, path_base)


def main() -> None:
    FIGURES.mkdir(parents=True, exist_ok=True)

    l1, v1 = read_phase1_lut()
    img = draw_bar_chart(
        "Phase 1 — SB_LUT4 (pre-PnR Yosys stat)",
        "SB_LUT4 (cells, pre-PnR)",
        l1,
        [float(x) for x in v1],
        format_bar_value=lambda v: f"{int(round(v))}",
    )
    save_figure_png(img, FIGURES / "phase1_lut4")

    p2 = read_phase2_rows()
    keys = ["baseline_A_mul", "baseline_B_mul", "optimized_mul"]
    labs2 = ["Baseline A", "Baseline B", "Optimized"]
    cyc = []
    for k in keys:
        row = p2.get(k, {})
        cyc.append(float(row.get("total_cycles", 0) or 0))
    img = draw_bar_chart(
        "Phase 2 — mul_test integration (total cycles)",
        "Cycles (mul_test TB)",
        labs2,
        cyc,
        PALETTE_DEFAULT[:3],
        format_bar_value=lambda v: f"{int(round(v))} cyc",
    )
    save_figure_png(img, FIGURES / "phase2_mul_test_cycles")

    labs_p = ["Baseline A", "Baseline B", "Optimized"]
    lat = []
    for k in ["baseline_A_pcpi", "baseline_B_pcpi", "optimized_pcpi"]:
        row = p2.get(k, {})
        v = row.get("avg_pcpi_latency") or row.get("avg_latency") or "0"
        try:
            lat.append(float(v))
        except ValueError:
            lat.append(0.0)
    img = draw_bar_chart(
        "Phase 2 — Average PCPI latency",
        "Cycles (avg. PCPI latency)",
        labs_p,
        lat,
        PALETTE_DEFAULT[:3],
        format_bar_value=lambda v: f"{int(round(v))} cyc",
    )
    save_figure_png(img, FIGURES / "phase2_pcpi_latency")

    sw_l, sw_v = read_switching()
    img = draw_bar_chart(
        "Phase 2 — Switching proxy W1 (total transitions)",
        "W1 transition count",
        sw_l,
        [float(x) for x in sw_v],
        PALETTE_DEFAULT[:3],
        format_bar_value=lambda v: f"{int(round(v)):,}".replace(",", " "),
    )
    save_figure_png(img, FIGURES / "phase2_switching_w1")

    p3_x = ["Baseline A", "Baseline B", "Baseline C", "Baseline C + KSA", "Optimized"]
    _l3, lut3, carry3 = read_phase3_area()
    img = draw_bar_chart(
        "Phase 3 — SB_LUT4 (PnR flow metrics)",
        "SB_LUT4 (post-PnR cells)",
        p3_x,
        [float(x) for x in lut3],
        format_bar_value=lambda v: f"{int(round(v))}",
    )
    save_figure_png(img, FIGURES / "phase3_lut4")

    img = draw_bar_chart(
        "Phase 3 — SB_CARRY (PnR flow metrics)",
        "SB_CARRY (post-PnR cells)",
        p3_x,
        [float(x) for x in carry3],
        PALETTE_DEFAULT,
        format_bar_value=lambda v: f"{int(round(v))}",
    )
    save_figure_png(img, FIGURES / "phase3_carry")

    _lf, vf = read_phase3_fmax()
    na = {i for i, v in enumerate(vf) if v is None}
    img = draw_bar_chart(
        "Phase 3 — Routed Fmax",
        "Fmax (MHz, routed)",
        p3_x,
        vf,
        na_indices=na,
        na_caption="PnR fail",
        format_bar_value=lambda v: f"{v:.2f} MHz",
    )
    save_figure_png(img, FIGURES / "phase3_fmax")

    _p5old, p5v = read_phase5_fmax()
    p5l = ["Yosys -dsp", "Yosys -dsp -abc2"]
    img = draw_bar_chart(
        "Phase 5 — Routed Fmax comparison",
        "Fmax (MHz, routed)",
        p5l,
        p5v,
        [PALETTE_DEFAULT[0], PALETTE_DEFAULT[3]],
        format_bar_value=lambda v: f"{v:.2f} MHz",
    )
    save_figure_png(img, FIGURES / "phase5_fmax_abc2")

    draw_scatter_tradeoff(FIGURES / "tradeoff_lut4_vs_pcpi_latency")
    _draw_phases_flow(FIGURES / "phases_flow_overview")
    _draw_phases_detail_block(FIGURES / "phases_detail_block")

    for stale in FIGURES.glob("*.jpg"):
        try:
            stale.unlink()
        except OSError:
            pass

    readme = FIGURES / "README.txt"
    readme.write_text(
        "Generated by opt/scripts/generate_report_figures.py\n"
        "Flat modern styling (no shadows), aligned axis typography.\n"
        "PNG only (lossless). Re-run after updating CSVs / phase5_measure.json.\n",
        encoding="utf-8",
    )
    print("Wrote", readme)


if __name__ == "__main__":
    main()
