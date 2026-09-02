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


def draw_image_fill(c, path, x, y, width, height, anchor="centre"):
    """Fill a clipped viewport with an image without changing the source asset."""
    image, (source_width, source_height) = image_size(path)
    scale = max(width / source_width, height / source_height)
    render_width = source_width * scale
    render_height = source_height * scale
    render_x = x + (width - render_width) / 2
    if anchor == "top":
        render_y = y + height - render_height
    elif anchor == "bottom":
        render_y = y
    else:
        render_y = y + (height - render_height) / 2
    c.saveState()
    clip = c.beginPath()
    clip.rect(x, y, width, height)
    c.clipPath(clip, stroke=0, fill=0)
    c.drawImage(image, render_x, render_y, render_width, render_height, mask="auto")
    c.restoreState()


def draw_image_view(c, path, x, y, width, height, top_fraction):
    """Draw a full-width viewport beginning at a fraction of the image height."""
    image, (source_width, source_height) = image_size(path)
    scale = width / source_width
    render_height = source_height * scale
    render_y = y + height - render_height + top_fraction * render_height
    c.saveState()
    clip = c.beginPath()
    clip.rect(x, y, width, height)
    c.clipPath(clip, stroke=0, fill=0)
    c.drawImage(image, x, render_y, width, render_height, mask="auto")
    c.restoreState()


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
    y = page_title(c, "Getting Started", page)
    y = paragraph(c, "Choose the asset type first, then drop a folder or select individual maps. Recognised filenames fill matching slots automatically; a file can also be dropped directly on a row.", M, y, W - 2 * M)
    draw_image_fill(c, ASSETS / "building-top-current.png", M, 448, W - 2 * M, 260, "top")
    y = 424
    rows = [
        ["Profile", "Main sizes", "Outputs", "LOD2"],
        ["Building", "512 / 1024 / 2048 / 4096", "BaseColor, ControlMask, MaskMap, Normal, Emissive", "Yes"],
        ["Surface", "512 / 1024 / 2048", "BaseColor, MaskMap, Normal", "No"],
        ["Decal", "512 / 1024 / 2048 / 4096", "BaseColor, MaskMap, Normal; optional experimental outputs", "No"],
    ]
    y = draw_table(c, rows, M, y, [68, 120, 274, 49]) - 22
    y = numbered_item(c, 1, "Select a profile", "Building, Surface, and Decal have different texture contracts.", M, y, 245)
    y = numbered_item(c, 2, "Add and review maps", "Check filenames, assignments, and the dimensions beneath each row.", M, y, 245)
    numbered_item(c, 3, "Export", "Confirm the destination, resolve warnings, then use the profile-specific Export button.", 310, 306, 243)
    info_card(c, M, 100, W - 2 * M, 68, "Screens shown", "The screenshots show the macOS app. The Windows app presents the same profiles, slots, warnings, and export choices with native Windows controls.")
    c.showPage()


def building(c, page):
    y = page_title(c, "Building Textures", page)
    y = paragraph(c, "Building is the full five-texture workflow and the only profile with LOD2 support. BaseColor is required; unassigned optional channels use safe defaults.", M, y, W - 2 * M)
    draw_image(c, ASSETS / "building-top-current.png", 92, 112, 411, 614)
    c.showPage()


def surface(c, page):
    y = page_title(c, "Surface Textures", page)
    y = paragraph(c, "Surface is for tiling materials. Its MaskMap differs from Building, accepts square 512, 1024, or 2048 pixel sources, and does not create ControlMask, Emissive, or LOD2 outputs.", M, y, W - 2 * M)
    draw_image(c, ASSETS / "surface-current.png", 92, 112, 411, 614)
    c.showPage()


def decal(c, page):
    y = page_title(c, "Decal Textures", page)
    y = paragraph(c, "Decal keeps the tested inputs prominent: BaseColor, Opacity, Metallic, Coat, Roughness, and Normal. BaseColor is required; the standard export writes BaseColor, MaskMap, and Normal.", M, y, W - 2 * M)
    draw_image(c, ASSETS / "decal-collapsed-current.png", M, 335, 244, 365)
    draw_image(c, ASSETS / "decal-expanded-current.png", 309, 335, 244, 365)
    info_card(c, M, 214, W - 2 * M, 90, "Experimental maps are deliberately separate", "ColorMask1-3, Snow Remove, and Emissive are labelled untested because the CS2 guide says they may not work as expected. ControlMask and Emissive are written only when the experimental section is opened and matching sources are supplied.")
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 7.2)
    c.drawString(M, 190, "Left: experimental section collapsed. Right: the same section expanded for deliberate use.")
    c.showPage()


def packing(c, page):
    y = page_title(c, "Packed Texture Layouts", page)
    y = paragraph(c, "The selected profile controls which channels are packed. The app never silently converts one profile into another.", M, y, W - 2 * M)
    y -= 14
    y = section_label(c, "Building and Decal", M, y)
    rows = [
        ["Output", "Red", "Green", "Blue", "Alpha"],
        ["BaseColor", "BaseColor R", "BaseColor G", "BaseColor B", "Active opacity"],
        ["ControlMask", "ColorMask1", "ColorMask2", "ColorMask3", "Snow Remove"],
        ["MaskMap", "Metallic", "Coat", "Black", "Inverse Roughness"],
        ["Normal", "OpenGL Normal R", "OpenGL Normal G", "OpenGL Normal B", "Opaque"],
    ]
    y = draw_table(c, rows, M, y, [76, 109, 109, 109, 108]) - 28
    y = section_label(c, "Surface MaskMap", M, y)
    rows = [
        ["Output", "Red", "Green", "Blue", "Alpha"],
        ["MaskMap", "Metallic", "Metallic Mask (white default)", "Normal Mask (white default)", "Inverse Roughness"],
    ]
    y = draw_table(c, rows, M, y, [76, 109, 109, 109, 108]) - 28
    card_width = (W - 2 * M - 16) / 3
    info_card(c, M, y - 96, card_width, 96, "BaseColor", "Required for every profile. It supplies the asset name and output dimensions.")
    info_card(c, M + card_width + 8, y - 96, card_width, 96, "Normal fallback", "If Normal is absent, the app creates a flat OpenGL normal output.")
    info_card(c, M + (card_width + 8) * 2, y - 96, card_width, 96, "Matching sizes", "All assigned main maps must match BaseColor. Export stops on a mismatch.")
    c.showPage()


def opacity_normals(c, page):
    y = page_title(c, "Opacity & Normals", page)
    y = paragraph(c, "The Opacity status line identifies the source that will be exported. BaseColor alpha normally takes precedence over a separate Opacity map.", M, y, W - 2 * M)
    draw_image_view(c, ASSETS / "building-top-current.png", M, 535, W - 2 * M, 150, 0.205)
    card_width = (W - 2 * M - 16) / 3
    info_card(c, M, 438, card_width, 78, "BaseColor alpha", "Used whenever the imported BaseColor contains a usable alpha channel.")
    info_card(c, M + card_width + 8, 438, card_width, 78, "Opacity map", "Used when BaseColor has no alpha and an Opacity map is assigned.")
    info_card(c, M + (card_width + 8) * 2, 438, card_width, 78, "Override", "Makes the assigned Opacity map take precedence.")
    y = section_label(c, "Normalise", M, 406)
    y = paragraph(c, "Enable Normalise to correct vectors to unit length while writing the exported Normal texture. The imported source is never modified. Leave it off to preserve the original OpenGL Normal RGB values.", M, y, W - 2 * M)
    draw_image_view(c, ASSETS / "building-top-current.png", M, 215, W - 2 * M, 135, 0.535)
    info_card(c, M, 108, 248, 82, "Unchecked", "Writes the imported OpenGL Normal values unchanged.")
    info_card(c, 305, 108, 248, 82, "Checked", "Normalises only the pixels written to the exported Normal PNG.")
    c.showPage()


def lod2(c, page):
    y = page_title(c, "Building LOD2", page)
    y = paragraph(c, "LOD2 belongs to the Building profile. Inputs are grouped by their shared asset name and must already be exactly 512 x 512; the app never resizes them.", M, y, W - 2 * M)
    draw_image(c, ASSETS / "building-middle-current.png", 92, 232, 411, 470)
    code_panel(c, M, 100, W - 2 * M, 104, [
        "<asset>_LOD2_BaseColor.png",
        "<asset>_LOD2_ControlMask.png",
        "<asset>_LOD2_MaskMap.png",
        "<asset>_LOD2_Normal.png       (flat normal when absent)",
        "<asset>_LOD2_Emissive.png     (when assigned)",
    ])
    c.showPage()


def exporting(c, page):
    y = page_title(c, "Exporting & Updates", page)
    y = paragraph(c, "By default the app creates CS2 Export beside the BaseColor source. Choose another location to write directly into that folder. Complete PNGs are staged before any existing set is replaced.", M, y, W - 2 * M)
    rows = [
        ["Profile", "Normal outputs", "Conditional outputs"],
        ["Building", "BaseColor, ControlMask, MaskMap, Normal, Emissive", "LOD2 set when supplied"],
        ["Surface", "BaseColor, MaskMap, Normal", "None"],
        ["Decal", "BaseColor, MaskMap, Normal", "Experimental ControlMask / Emissive when supplied"],
    ]
    y = draw_table(c, rows, M, y - 12, [76, 270, 165]) - 28
    y = section_label(c, "Export flow", M, y)
    left_y = y
    left_y = numbered_item(c, 1, "Choose the action", "Use Export Main, Export Surface, Export Decal, Export LOD2, or Export All as shown.", M, left_y, 245)
    left_y = numbered_item(c, 2, "Resolve warnings", "Correct size mismatches and review existing filenames before approving replacement.", M, left_y, 245)
    right_y = y
    right_y = numbered_item(c, 3, "Check the destination", "Use the default CS2 Export folder or choose a custom location.", 310, right_y, 243)
    numbered_item(c, 4, "Verify the set", "Confirm the expected profile filenames and native pixel dimensions.", 310, right_y, 243)
    info_card(c, M, 236, W - 2 * M, 90, "Secure updates", "CS2 Combiner checks for a newer stable release when it opens. Update Now downloads the matching package, verifies its published SHA-256 digest and version, installs it, and reopens the app. Check for Updates is also available manually.")
    info_card(c, M, 122, W - 2 * M, 90, "If Windows blocks an unsigned build", "Windows Smart App Control may block independently distributed applications whose publisher cannot be verified. Code signing avoids that warning; it does not indicate a texture-export error.")
    c.showPage()


def common_workflows(c, page):
    y = page_title(c, "Quick Reference", page)
    y = paragraph(c, "Use these short paths for common assignments and corrections.", M, y, W - 2 * M) - 16
    cards = [
        ("Import a folder", "Select the intended profile, then drop the folder once and review the detected slots."),
        ("Wrong profile detected", "Accept the warning and switch profile only when the dropped filenames belong to another asset type."),
        ("Assign manually", "Drop directly on a row or use Assign / Replace when a filename is not recognised."),
        ("Use BaseColor alpha", "Leave Override BaseColor alpha off and confirm the live Opacity status."),
        ("Use an Opacity map", "Enable the override only when the assigned map should take priority."),
        ("Normalise on export", "Enable Normalise on the Normal row. Only exported pixels are corrected."),
        ("Resolve a mismatch", "Match every main map to BaseColor. Surface stops at 2048; Building and Decal also allow 4096."),
        ("Use Decal experiments", "Expand the orange section deliberately. Untested outputs are written only when sources are supplied."),
        ("Keep Building outputs together", "Use Export All with the main texture folder option when main and LOD2 maps are both assigned."),
        ("Replace existing exports", "Review the listed filenames, then replace or cancel without changing the existing set."),
    ]
    card_width = 248
    card_height = 82
    for index, (heading, body) in enumerate(cards):
        column = index % 2
        row = index // 2
        x = M + column * 263
        card_y = y - card_height - row * 94
        info_card(c, x, card_y, card_width, card_height, heading, body)
    c.showPage()


def build():
    required = [
        "cover-background.png",
        "cover-shape.png",
        "building-top-current.png",
        "building-middle-current.png",
        "surface-current.png",
        "decal-collapsed-current.png",
        "decal-expanded-current.png",
    ]
    missing = [name for name in required if not (ASSETS / name).exists()]
    if missing:
        raise FileNotFoundError(f"Missing guide assets: {missing}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=A4, pageCompression=1)
    c.setTitle("CS2 Combiner User Guide")
    c.setAuthor("CS2 Combiner")
    c.setSubject("User documentation for CS2 Combiner on macOS and Windows")
    c.setCreator("ReportLab source: docs/build_cs2_combiner_user_guide.py")

    cover(c)
    importing(c, 2)
    building(c, 3)
    surface(c, 4)
    decal(c, 5)
    packing(c, 6)
    opacity_normals(c, 7)
    lod2(c, 8)
    exporting(c, 9)
    common_workflows(c, 10)
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    build()
