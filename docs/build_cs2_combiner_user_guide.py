#!/usr/bin/env python3
"""Build the CS2 Combiner user guide PDF."""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets" / "cs2-combiner-guide"
OUTPUT = ROOT / "output" / "pdf" / "CS2-Combiner-User-Guide.pdf"

W, H = A4
M = 42

INK = colors.HexColor("#202A3B")
TEXT = colors.HexColor("#344054")
MUTED = colors.HexColor("#7A8494")
BLUE = colors.HexColor("#3478F6")
PALE_BLUE = colors.HexColor("#F2F6FC")
CARD_LINE = colors.HexColor("#D6E1F1")
HAIRLINE = colors.HexColor("#E4E8EF")
SOFT_GREY = colors.HexColor("#F6F7F9")
LIGHT_GREY = colors.HexColor("#CBCFD5")
WHITE = colors.white

styles = getSampleStyleSheet()
BODY = ParagraphStyle(
    "body",
    parent=styles["BodyText"],
    fontName="Helvetica",
    fontSize=9,
    leading=13,
    textColor=TEXT,
    spaceAfter=0,
)
SMALL = ParagraphStyle(
    "small",
    parent=BODY,
    fontSize=7.5,
    leading=10,
)
CARD_BODY = ParagraphStyle(
    "card-body",
    parent=BODY,
    fontSize=7.3,
    leading=9.6,
)
TABLE_TEXT = ParagraphStyle(
    "table-text",
    parent=BODY,
    fontSize=6.7,
    leading=8.3,
)
TABLE_HEAD = ParagraphStyle(
    "table-head",
    parent=TABLE_TEXT,
    fontName="Helvetica-Bold",
    textColor=WHITE,
)
def paragraph(c, text, x, y_top, width, style=BODY):
    item = Paragraph(text, style)
    _, height = item.wrap(width, H)
    item.drawOn(c, x, y_top - height)
    return y_top - height


def image_size(path):
    image = ImageReader(str(path))
    return image, image.getSize()


def draw_image(c, path, x, y, width, height):
    """Fit an image without adding a card, fill, border, or shadow."""
    image, (source_width, source_height) = image_size(path)
    scale = min(width / source_width, height / source_height)
    render_width = source_width * scale
    render_height = source_height * scale
    render_x = x + (width - render_width) / 2
    render_y = y + (height - render_height) / 2
    c.drawImage(
        image,
        render_x,
        render_y,
        render_width,
        render_height,
        preserveAspectRatio=True,
        mask="auto",
    )


def draw_cover_background(c, path):
    image, (source_width, source_height) = image_size(path)
    scale = max(W / source_width, H / source_height)
    render_width = source_width * scale
    render_height = source_height * scale
    c.drawImage(
        image,
        (W - render_width) / 2,
        (H - render_height) / 2,
        render_width,
        render_height,
        preserveAspectRatio=True,
        mask="auto",
    )


def page_title(c, title, page):
    c.setFillColor(INK)
    c.setFont("Helvetica", 20)
    c.drawString(M, H - 58, title)
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 7)
    c.drawRightString(W - M, H - 54, "CS2 COMBINER")
    footer(c, page)
    return H - 82


def footer(c, page):
    c.setFillColor(colors.HexColor("#A0A7B3"))
    c.setFont("Helvetica", 6.8)
    c.drawString(M, 18, "CS2 Combiner user guide")
    c.drawRightString(W - M, 18, f"{page:02d}")


def section_label(c, text, x, y):
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(x, y, text)
    return y - 18


def numbered_item(c, number, heading, body, x, y_top, width):
    radius = 8
    centre_x = x + radius
    centre_y = y_top - radius
    c.setFillColor(BLUE)
    c.circle(centre_x, centre_y, radius, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 6.8)
    c.drawCentredString(centre_x, centre_y - 2.5, str(number))

    text_x = x + 24
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 8.6)
    c.drawString(text_x, centre_y - 3, heading)
    bottom = paragraph(c, body, text_x, centre_y - 10, width - 24, SMALL)
    return min(bottom, y_top - 34) - 8


def info_card(c, x, y, width, height, heading, body):
    c.setFillColor(PALE_BLUE)
    c.setStrokeColor(CARD_LINE)
    c.roundRect(x, y, width, height, 8, fill=1, stroke=1)
    c.setFillColor(BLUE)
    c.roundRect(x + 10, y + height - 25, 3, 14, 1.5, fill=1, stroke=0)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(x + 20, y + height - 20, heading)
    paragraph(c, body, x + 20, y + height - 29, width - 30, CARD_BODY)


def code_panel(c, x, y, width, height, lines):
    c.setFillColor(SOFT_GREY)
    c.setStrokeColor(HAIRLINE)
    c.roundRect(x, y, width, height, 8, fill=1, stroke=1)
    c.setFillColor(INK)
    c.setFont("Courier", 7.2)
    baseline = y + height - 18
    for line in lines:
        c.drawString(x + 14, baseline, line)
        baseline -= 13


def draw_table(c, rows, x, y_top, widths):
    converted = []
    for row_index, row in enumerate(rows):
        style = TABLE_HEAD if row_index == 0 else TABLE_TEXT
        converted.append([Paragraph(str(cell), style) for cell in row])
    table = Table(converted, colWidths=widths, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#3A4658")),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, SOFT_GREY]),
                ("GRID", (0, 0), (-1, -1), 0.35, HAIRLINE),
            ]
        )
    )
    _, height = table.wrap(sum(widths), H)
    table.drawOn(c, x, y_top - height)
    return y_top - height


def cover(c):
    draw_cover_background(c, ASSETS / "cover-background.png")
    draw_image(c, ASSETS / "cover-shape.png", 135, 285, W - 270, 360)
    c.setFillColor(LIGHT_GREY)
    c.setFont("Helvetica", 31)
    c.drawCentredString(W / 2, 226, "CS2 Combiner")
    c.setFillColor(colors.HexColor("#92979F"))
    c.setFont("Helvetica", 8)
    c.drawCentredString(W / 2, 199, "USER GUIDE")
    c.showPage()


def importing(c, page):
    y = page_title(c, "Importing", page)
    y = paragraph(
        c,
        "Drop a folder or select individual exported maps. Recognised filenames fill "
        "their slots automatically; any map can also be assigned directly to a row.",
        M,
        y,
        W - 2 * M,
    )
    draw_image(c, ASSETS / "import-drop.png", M, y - 78, W - 2 * M, 66)
    y -= 96

    left_x = M
    left_width = 235
    y_left = y
    y_left = numbered_item(c, 1, "Add maps", "Drop images or a folder, or choose Add Maps / Add Folder.", left_x, y_left, left_width)
    y_left = numbered_item(c, 2, "Review assignments", "Check filenames, slot names, and the dimensions shown beneath each map.", left_x, y_left, left_width)
    y_left = numbered_item(c, 3, "Set optional controls", "Read the active Opacity source and enable Normalise only when needed.", left_x, y_left, left_width)
    y_left = numbered_item(c, 4, "Confirm the destination", "Use CS2 Export in the BaseColor source folder or choose another output folder.", left_x, y_left, left_width)
    y_left = numbered_item(c, 5, "Export", "Use Export Main, Export LOD2, or Export All.", left_x, y_left, left_width)

    info_card(
        c,
        left_x,
        116,
        left_width,
        88,
        "Accepted dimensions",
        "Main textures: square 512, 1024, 2048, or 4096 px. LOD2 textures: exactly "
        "512 x 512. Imported textures are never resized.",
    )

    draw_image(c, ASSETS / "import-overview.png", 310, 112, 243, 525)
    c.showPage()


def texture_slots(c, page):
    y = page_title(c, "Texture Slots", page)
    y = paragraph(
        c,
        "BaseColor is required. Every other main slot is optional and falls back to "
        "a safe packed-channel default when it is not assigned.",
        M,
        y,
        W - 2 * M,
    )
    draw_image(c, ASSETS / "texture-slots.png", 74, 264, W - 148, 470)

    rows = [
        ["Slot group", "Assigned inputs", "Packed result"],
        ["BaseColor", "BaseColor, Opacity", "BaseColor RGB and active opacity source"],
        ["Control Mask", "ColorMask1-3, Snow Remove", "RGBA channels in slot order"],
        ["Mask Map", "Metallic, Coat, Roughness", "R, G, black, inverse Roughness"],
        ["Surface", "Normal, Emissive", "OpenGL Normal RGB and Emissive RGB"],
    ]
    draw_table(c, rows, M, 238, [86, 190, 235])
    c.showPage()


def opacity_normals(c, page):
    y = page_title(c, "Opacity & Normals", page)
    y = paragraph(
        c,
        "The live Opacity row identifies the source that will be exported. BaseColor "
        "alpha normally takes precedence over a separate Opacity map.",
        M,
        y,
        W - 2 * M,
    )
    draw_image(c, ASSETS / "opacity-controls-attached.png", M, y - 118, W - 2 * M, 105)
    y -= 136

    card_width = (W - 2 * M - 16) / 3
    info_card(c, M, y - 76, card_width, 76, "BaseColor alpha", "Used whenever the imported BaseColor contains an alpha channel.")
    info_card(c, M + card_width + 8, y - 76, card_width, 76, "Opacity map", "Used when BaseColor has no alpha and an Opacity map is assigned.")
    info_card(c, M + (card_width + 8) * 2, y - 76, card_width, 76, "Override", "Override BaseColor alpha makes the assigned Opacity map take precedence.")
    y -= 101

    y = section_label(c, "Normalise", M, y)
    draw_image(c, ASSETS / "normalise-controls-attached.png", M, y - 112, W - 2 * M, 100)
    y -= 130
    y = paragraph(
        c,
        "Enable the Normalise checkbox to correct Normal vectors to unit length while "
        "writing the exported Normal texture. The assigned source is never modified, "
        "replaced, or saved as a separate normalised copy.",
        M,
        y,
        W - 2 * M,
    )
    y -= 18

    y_left = y
    y_left = numbered_item(c, 1, "Unchecked", "Write the imported OpenGL Normal RGB values unchanged.", M, y_left, 245)
    numbered_item(c, 2, "Checked", "Normalise only the pixels written to the exported Normal PNG.", 310, y, 243)
    c.showPage()


def lod2(c, page):
    y = page_title(c, "LOD2", page)
    y = paragraph(
        c,
        "LOD2 maps are grouped by their shared asset name. Every accepted LOD2 input "
        "must already be exactly 512 x 512; the app never resizes it.",
        M,
        y,
        W - 2 * M,
    )
    draw_image(c, ASSETS / "lod2-attached.png", M, 390, W - 2 * M, 328)

    info_card(
        c,
        M,
        286,
        248,
        80,
        "Main texture folder",
        "Keep Export in the main texture folder enabled to place LOD2 output beside "
        "the main set.",
    )
    info_card(
        c,
        305,
        286,
        248,
        80,
        "Independent location",
        "Disable the shared-folder option and choose a separate LOD2 destination.",
    )

    y = section_label(c, "LOD2 outputs", M, 254)
    code_panel(
        c,
        M,
        140,
        W - 2 * M,
        96,
        [
            "<asset>_LOD2_BaseColor.png",
            "<asset>_LOD2_ControlMask.png",
            "<asset>_LOD2_MaskMap.png",
            "<asset>_LOD2_Normal.png       (when assigned)",
            "<asset>_LOD2_Emissive.png     (when assigned)",
        ],
    )
    c.showPage()


def exporting(c, page):
    y = page_title(c, "Exporting", page)
    y = paragraph(
        c,
        "BaseColor supplies the asset name and native main export dimensions. The app "
        "writes into CS2 Export beside the source or into a selected folder, stages complete PNGs, and "
        "asks before replacing files.",
        M,
        y,
        W - 2 * M,
    )
    draw_image(c, ASSETS / "export-controls.png", 368, y - 28, 185, 16)
    y -= 58

    info_card(
        c,
        M,
        y - 82,
        248,
        82,
        "Default location",
        "CS2 Export inside the BaseColor source folder. A custom location writes "
        "directly into the selected folder.",
    )
    info_card(
        c,
        305,
        y - 82,
        248,
        82,
        "No resampling",
        "Every assigned main map must match BaseColor. A mismatch stops export instead "
        "of resizing an imported texture.",
    )
    y -= 108

    y = section_label(c, "Main filenames", M, y)
    code_panel(
        c,
        M,
        y - 100,
        W - 2 * M,
        90,
        [
            "<asset>_BaseColor.png",
            "<asset>_ControlMask.png",
            "<asset>_MaskMap.png",
            "<asset>_Normal.png",
            "<asset>_Emissive.png",
        ],
    )
    y -= 122

    y = section_label(c, "Export flow", M, y)
    left_y = y
    left_y = numbered_item(c, 1, "Choose the action", "Export Main, Export LOD2, or Export All.", M, left_y, 245)
    left_y = numbered_item(c, 2, "Review warnings", "Resolve size mismatches and review any existing filenames.", M, left_y, 245)
    right_y = y
    right_y = numbered_item(c, 3, "Write the set", "Complete files are staged before they replace existing outputs.", 310, right_y, 243)
    numbered_item(c, 4, "Verify the result", "Check the destination, five main filenames, and expected pixel dimensions.", 310, right_y, 243)
    c.showPage()


def common_workflows(c, page):
    y = page_title(c, "Common Workflows", page)
    y = paragraph(
        c,
        "Use these short paths for the most common assignments and corrections.",
        M,
        y,
        W - 2 * M,
    )
    y -= 16

    cards = [
        ("Import a folder", "Drop the export folder once. Recognised main and LOD2 names are routed to their matching slots."),
        ("Assign a map manually", "Drop directly on a row or use Assign / Replace when a filename is not recognised."),
        ("Use BaseColor alpha", "Leave Override BaseColor alpha off. The live Opacity row confirms the active source."),
        ("Use an Opacity map", "Assign the map. Enable Override BaseColor alpha only when it should take precedence."),
        ("Normalise on export", "Enable Normalise on the Normal row. Only the exported Normal pixels are corrected."),
        ("Resolve a size mismatch", "Prepare matching 512, 1024, 2048, or 4096 px main maps. LOD2 inputs must be 512 x 512."),
        ("Replace existing exports", "Review the listed filenames, then replace them or cancel without changing the existing set."),
        ("Keep outputs together", "Use Export All with the main texture folder enabled. It appears only when main and LOD2 maps are both assigned."),
    ]
    card_width = 248
    card_height = 88
    column_gap = 15
    row_gap = 12
    for index, (heading, body) in enumerate(cards):
        column = index % 2
        row = index // 2
        x = M + column * (card_width + column_gap)
        card_y = y - card_height - row * (card_height + row_gap)
        info_card(c, x, card_y, card_width, card_height, heading, body)

    c.setFillColor(MUTED)
    c.setFont("Helvetica", 7.2)
    c.drawString(M, 78, "Existing filenames are listed for confirmation before replacement.")
    c.showPage()


def build():
    required = [
        "cover-background.png",
        "cover-shape.png",
        "import-overview.png",
        "import-drop.png",
        "texture-slots.png",
        "opacity-controls-attached.png",
        "normalise-controls-attached.png",
        "lod2-attached.png",
        "export-controls.png",
    ]
    missing = [name for name in required if not (ASSETS / name).exists()]
    if missing:
        raise FileNotFoundError(f"Missing guide assets: {missing}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=A4, pageCompression=1)
    c.setTitle("CS2 Combiner User Guide")
    c.setAuthor("CS2 Combiner")
    c.setSubject("User documentation for CS2 Combiner on macOS")
    c.setCreator("ReportLab source: docs/build_cs2_combiner_user_guide.py")

    cover(c)
    importing(c, 2)
    texture_slots(c, 3)
    opacity_normals(c, 4)
    lod2(c, 5)
    exporting(c, 6)
    common_workflows(c, 7)
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    build()
