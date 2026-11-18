import os
import re
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import parse_xml, OxmlElement
from docx.oxml.ns import nsdecls, qn

def set_cell_background(cell, hex_color):
    """Sets the background color of a table cell."""
    tcPr = cell._tc.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=120, bottom=120, left=180, right=180):
    """Sets cell internal padding in twips (1 pt = 20 twips)."""
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = parse_xml(f'''
        <w:tcMar {nsdecls("w")}>
            <w:top w:w="{top}" w:type="dxa"/>
            <w:bottom w:w="{bottom}" w:type="dxa"/>
            <w:left w:w="{left}" w:type="dxa"/>
            <w:right w:w="{right}" w:type="dxa"/>
        </w:tcMar>
    ''')
    tcPr.append(tcMar)

def set_table_borders(table, color="D3D3D3"):
    """Sets clean, subtle borders on a table."""
    tblPr = table._tbl.tblPr
    borders = parse_xml(f'''
        <w:tblBorders {nsdecls("w")}>
            <w:top w:val="single" w:sz="6" w:space="0" w:color="{color}"/>
            <w:bottom w:val="single" w:sz="8" w:space="0" w:color="1F497D"/>
            <w:insideH w:val="single" w:sz="4" w:space="0" w:color="{color}"/>
            <w:insideV w:val="none"/>
            <w:left w:val="none"/>
            <w:right w:val="none"/>
        </w:tblBorders>
    ''')
    tblPr.append(borders)

def add_callout_box(doc, text, title="KEY ARCHITECTURAL HIGHLIGHT"):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    tbl.columns[0].width = Inches(6.5)
    
    cell = tbl.cell(0, 0)
    set_cell_background(cell, "F0F4F8")
    set_cell_margins(cell, top=140, bottom=140, left=240, right=200)
    
    # Blue left border
    tcPr = cell._tc.get_or_add_tcPr()
    border = parse_xml(f'''
        <w:tcBorders {nsdecls("w")}>
            <w:left w:val="single" w:sz="24" w:space="0" w:color="1F497D"/>
            <w:top w:val="none"/>
            <w:bottom w:val="none"/>
            <w:right w:val="none"/>
        </w:tcBorders>
    ''')
    tcPr.append(border)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(4)
    run_t = p.add_run(f"★ {title}\n")
    run_t.font.name = "Calibri"
    run_t.font.size = Pt(10.5)
    run_t.font.bold = True
    run_t.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
    
    run_b = p.add_run(text)
    run_b.font.name = "Calibri"
    run_b.font.size = Pt(10)
    run_b.font.color.rgb = RGBColor(0x33, 0x33, 0x33)

def add_code_block(doc, code_str):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    tbl.columns[0].width = Inches(6.5)
    
    cell = tbl.cell(0, 0)
    set_cell_background(cell, "F8F9FA")
    set_cell_margins(cell, top=100, bottom=100, left=180, right=140)
    
    tcPr = cell._tc.get_or_add_tcPr()
    border = parse_xml(f'''
        <w:tcBorders {nsdecls("w")}>
            <w:left w:val="single" w:sz="18" w:space="0" w:color="2E75B6"/>
            <w:top w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
            <w:bottom w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
            <w:right w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
        </w:tcBorders>
    ''')
    tcPr.append(border)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.05
    run = p.add_run(code_str.rstrip())
    run.font.name = "Consolas"
    run.font.size = Pt(9)
    run.font.color.rgb = RGBColor(0x22, 0x22, 0x22)
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def format_styled_table(doc, headers, rows_data, col_widths=None):
    tbl = doc.add_table(rows=len(rows_data) + 1, cols=len(headers))
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    set_table_borders(tbl)
    
    # Header Row
    hdr_cells = tbl.rows[0].cells
    for i, h in enumerate(headers):
        hdr_cells[i].text = h.strip()
        set_cell_background(hdr_cells[i], "1F497D")
        set_cell_margins(hdr_cells[i], top=120, bottom=120, left=140, right=140)
        p = hdr_cells[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        for r in p.runs:
            r.font.name = "Calibri"
            r.font.size = Pt(9.5)
            r.font.bold = True
            r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
            
    # Set header repeat across pages
    trPr = tbl.rows[0]._tr.get_or_add_trPr()
    trPr.append(parse_xml(f'<w:tblHeader {nsdecls("w")}/>'))
    
    # Body Rows
    for r_idx, row in enumerate(rows_data):
        row_cells = tbl.rows[r_idx + 1].cells
        bg_color = "F9FAFC" if (r_idx % 2 == 1) else "FFFFFF"
        for c_idx, val in enumerate(row):
            if c_idx < len(row_cells):
                row_cells[c_idx].text = str(val).strip()
                set_cell_background(row_cells[c_idx], bg_color)
                set_cell_margins(row_cells[c_idx], top=80, bottom=80, left=120, right=120)
                p = row_cells[c_idx].paragraphs[0]
                p.paragraph_format.space_before = Pt(0)
                p.paragraph_format.space_after = Pt(0)
                
                # Check for PASS / FAIL
                txt = str(val).strip()
                for r in p.runs:
                    r.font.name = "Calibri"
                    r.font.size = Pt(9)
                    if "PASS" in txt:
                        r.font.bold = True
                        r.font.color.rgb = RGBColor(0x00, 0x80, 0x00)
                    elif "FAIL" in txt:
                        r.font.bold = True
                        r.font.color.rgb = RGBColor(0xCC, 0x00, 0x00)
                    elif "DENIED" in txt:
                        r.font.bold = True
                        r.font.color.rgb = RGBColor(0xB2, 0x22, 0x22)
                    elif txt.startswith("0x") or txt.startswith("TC_") or txt.startswith("M") and len(txt) <= 2:
                        r.font.name = "Consolas"
                        r.font.size = Pt(8.5)
                    else:
                        r.font.color.rgb = RGBColor(0x22, 0x22, 0x22)

    # Apply column widths if provided
    if col_widths and len(col_widths) == len(headers):
        for row in tbl.rows:
            for idx, width in enumerate(col_widths):
                row.cells[idx].width = Inches(width)

    doc.add_paragraph().paragraph_format.space_after = Pt(6)

def build_docx_report(md_path, docx_path):
    doc = Document()
    
    # Configure Margins: 0.75 in (54 pt) all around for spacious technical printout
    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.85)
        section.right_margin = Inches(0.85)
        
        # Configure Header & Footer
        header = section.header
        hp = header.paragraphs[0]
        hp.text = "Secure Communication Gateway SoC | Comprehensive Course Project Report"
        hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        hp.runs[0].font.name = "Calibri"
        hp.runs[0].font.size = Pt(8.5)
        hp.runs[0].font.italic = True
        hp.runs[0].font.color.rgb = RGBColor(0x88, 0x88, 0x88)
        
        footer = section.footer
        fp = footer.paragraphs[0]
        fp.text = "Academic Honours Final-Year Project | Release v1.0-final | Confidential"
        fp.alignment = WD_ALIGN_PARAGRAPH.LEFT
        fp.runs[0].font.name = "Calibri"
        fp.runs[0].font.size = Pt(8.5)
        fp.runs[0].font.color.rgb = RGBColor(0x88, 0x88, 0x88)

    # ==========================================
    # COVER PAGE
    # ==========================================
    p_inst = doc.add_paragraph()
    p_inst.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_inst.paragraph_format.space_before = Pt(36)
    p_inst.paragraph_format.space_after = Pt(12)
    run_inst = p_inst.add_run("FINAL-YEAR HONOURS ENGINEERING COURSE PROJECT REPORT\nDEPARTMENT OF ELECTRONICS & VLSI DESIGN")
    run_inst.font.name = "Calibri"
    run_inst.font.size = Pt(12)
    run_inst.font.bold = True
    run_inst.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    # Title
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.space_before = Pt(24)
    p_title.paragraph_format.space_after = Pt(16)
    run_title = p_title.add_run("Design and Verification of a RISC-V Based Secure Communication Gateway SoC with Hardware AES Encryption and Watchdog Scoped Fault Recovery")
    run_title.font.name = "Calibri"
    run_title.font.size = Pt(22)
    run_title.font.bold = True
    run_title.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)

    # Subtitle
    p_sub = doc.add_paragraph()
    p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_sub.paragraph_format.space_before = Pt(8)
    p_sub.paragraph_format.space_after = Pt(40)
    run_sub = p_sub.add_run("Synthesizable RTL Crossbar Architecture, Autonomous Dual-Mode DMA Datapath, Scoped Fault Recovery & IEEE 1800.2 UVM 1.2 Verification Closure")
    run_sub.font.name = "Calibri"
    run_sub.font.size = Pt(13)
    run_sub.font.italic = True
    run_sub.font.color.rgb = RGBColor(0x2E, 0x75, 0xB6)

    # Metadata Card
    meta_tbl = doc.add_table(rows=6, cols=2)
    meta_tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(meta_tbl)
    meta_data = [
        ("Academic Course / Degree:", "Honours Final-Year Project in VLSI & SoC Architecture"),
        ("Candidate Name / Student ID:", "Karunya (karunyanani)"),
        ("Repository URL:", "https://github.com/karunyanani/Honours-project.git"),
        ("Verified Release Tag:", "v1.0-final (Production Milestone)"),
        ("Target Verification Simulators:", "Synopsys VCS / Verdi (UVM 1.2), Icarus Verilog v12.0"),
        ("Software / ISA Target:", "GNU GCC RV32I / ILP32 ABI (VeeR EL2 Core)")
    ]
    for idx, (label, val) in enumerate(meta_data):
        c0, c1 = meta_tbl.rows[idx].cells
        c0.text = label
        c1.text = val
        set_cell_background(c0, "F0F4F8")
        set_cell_background(c1, "FFFFFF")
        set_cell_margins(c0, top=80, bottom=80, left=140, right=140)
        set_cell_margins(c1, top=80, bottom=80, left=140, right=140)
        c0.paragraphs[0].runs[0].font.name = "Calibri"
        c0.paragraphs[0].runs[0].font.size = Pt(9.5)
        c0.paragraphs[0].runs[0].font.bold = True
        c0.paragraphs[0].runs[0].font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
        c1.paragraphs[0].runs[0].font.name = "Calibri"
        c1.paragraphs[0].runs[0].font.size = Pt(9.5)

    doc.add_page_break()

    # ==========================================
    # PARSE & RENDER MARKDOWN BODY
    # ==========================================
    with open(md_path, "r", encoding="utf-8") as f:
        md_text = f.read()

    lines = md_text.splitlines()
    i = 0
    in_code = False
    code_lines = []
    in_table = False
    table_lines = []

    def flush_code(doc, code_lines):
        if code_lines:
            add_code_block(doc, "\n".join(code_lines))
            code_lines.clear()

    def flush_table(doc, table_lines):
        if not table_lines:
            return
        parsed_rows = []
        for line in table_lines:
            cells = [c.strip() for c in line.split("|")[1:-1]]
            parsed_rows.append(cells)
        if len(parsed_rows) >= 2:
            headers = parsed_rows[0]
            # row 1 is separator (e.g. ---|---|---)
            data_rows = parsed_rows[2:]
            format_styled_table(doc, headers, data_rows)
        table_lines.clear()

    while i < len(lines):
        line = lines[i]
        
        # Code fence handling
        if line.startswith("```"):
            if in_code:
                in_code = False
                flush_code(doc, code_lines)
            else:
                if in_table:
                    in_table = False
                    flush_table(doc, table_lines)
                in_code = True
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        # Table line handling
        if line.strip().startswith("|") and line.strip().endswith("|"):
            if not in_table:
                in_table = True
            table_lines.append(line)
            i += 1
            continue
        else:
            if in_table:
                in_table = False
                flush_table(doc, table_lines)

        # Markdown Headings
        if line.startswith("# "):
            heading_text = line[2:].strip()
            if "COMPREHENSIVE COURSE PROJECT TECHNICAL REPORT" in heading_text or "Design and Verification" in heading_text:
                i += 1
                continue
            h = doc.add_heading(level=1)
            h.paragraph_format.space_before = Pt(20)
            h.paragraph_format.space_after = Pt(8)
            h.paragraph_format.keep_with_next = True
            r = h.add_run(heading_text)
            r.font.name = "Calibri"
            r.font.size = Pt(16)
            r.font.bold = True
            r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
            i += 1
            continue

        elif line.startswith("## "):
            heading_text = line[3:].strip()
            h = doc.add_heading(level=2)
            h.paragraph_format.space_before = Pt(14)
            h.paragraph_format.space_after = Pt(6)
            h.paragraph_format.keep_with_next = True
            r = h.add_run(heading_text)
            r.font.name = "Calibri"
            r.font.size = Pt(13)
            r.font.bold = True
            r.font.color.rgb = RGBColor(0x2E, 0x75, 0xB6)
            i += 1
            continue

        elif line.startswith("### "):
            heading_text = line[4:].strip()
            h = doc.add_heading(level=3)
            h.paragraph_format.space_before = Pt(10)
            h.paragraph_format.space_after = Pt(4)
            h.paragraph_format.keep_with_next = True
            r = h.add_run(heading_text)
            r.font.name = "Calibri"
            r.font.size = Pt(11)
            r.font.bold = True
            r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
            i += 1
            continue

        elif line.startswith("#### "):
            heading_text = line[5:].strip()
            h = doc.add_heading(level=4)
            h.paragraph_format.space_before = Pt(8)
            h.paragraph_format.space_after = Pt(2)
            h.paragraph_format.keep_with_next = True
            r = h.add_run(heading_text)
            r.font.name = "Calibri"
            r.font.size = Pt(10.5)
            r.font.bold = True
            r.font.italic = True
            r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            i += 1
            continue

        # Bullet points
        if line.strip().startswith("- ") or line.strip().startswith("* "):
            bullet_text = line.strip()[2:].strip()
            p = doc.add_paragraph(style='List Bullet')
            p.paragraph_format.space_before = Pt(1)
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.line_spacing = 1.15
            
            # Format bold/code runs
            parts = re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', bullet_text)
            for part in parts:
                if part.startswith("**") and part.endswith("**"):
                    r = p.add_run(part[2:-2])
                    r.font.bold = True
                    r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
                elif part.startswith("`") and part.endswith("`"):
                    r = p.add_run(part[1:-1])
                    r.font.name = "Consolas"
                    r.font.size = Pt(9.5)
                    r.font.color.rgb = RGBColor(0x9C, 0x27, 0xB0)
                else:
                    r = p.add_run(part)
                    r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            i += 1
            continue

        # Numbered lists
        m_num = re.match(r'^(\d+)\.\s+(.*)$', line.strip())
        if m_num:
            num_val = m_num.group(1)
            item_text = m_num.group(2)
            p = doc.add_paragraph(style='List Number')
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.line_spacing = 1.15
            
            parts = re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', item_text)
            for part in parts:
                if part.startswith("**") and part.endswith("**"):
                    r = p.add_run(part[2:-2])
                    r.font.bold = True
                    r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
                elif part.startswith("`") and part.endswith("`"):
                    r = p.add_run(part[1:-1])
                    r.font.name = "Consolas"
                    r.font.size = Pt(9.5)
                    r.font.color.rgb = RGBColor(0x9C, 0x27, 0xB0)
                else:
                    r = p.add_run(part)
                    r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            i += 1
            continue

        # Horizontal Rule
        if line.strip() == "---":
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(8)
            p.paragraph_format.space_after = Pt(8)
            p_border = parse_xml(f'<w:pBdr {nsdecls("w")}><w:bottom w:val="single" w:sz="6" w:space="1" w:color="CCCCCC"/></w:pBdr>')
            p._p.get_or_add_pPr().append(p_border)
            i += 1
            continue

        # Standard Paragraphs
        stripped = line.strip()
        if stripped:
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(4)
            p.paragraph_format.line_spacing = 1.15
            
            parts = re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', stripped)
            for part in parts:
                if part.startswith("**") and part.endswith("**"):
                    r = p.add_run(part[2:-2])
                    r.font.bold = True
                    r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
                elif part.startswith("`") and part.endswith("`"):
                    r = p.add_run(part[1:-1])
                    r.font.name = "Consolas"
                    r.font.size = Pt(9.5)
                    r.font.color.rgb = RGBColor(0x9C, 0x27, 0xB0)
                else:
                    r = p.add_run(part)
                    r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)

        i += 1

    if in_table:
        flush_table(doc, table_lines)
    if in_code:
        flush_code(doc, code_lines)

    doc.save(docx_path)
    print(f"[+] Successfully generated professional DOCX report: {docx_path}")

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    md_path = os.path.join(root, "docs", "FINAL_PROJECT_REPORT.md")
    docx_path = os.path.join(root, "docs", "FINAL_PROJECT_REPORT.docx")
    build_docx_report(md_path, docx_path)
