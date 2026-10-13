#!/usr/bin/env python3
"""Typesets Kate Chopin's "The Story of an Hour" (1894, public domain) as the
4-page class text bundled with the HarknessAI tutorial.

Page breaks follow the tutorial's analytic beats:
  1  the news & the grief (the "heart trouble" plant in line one)
  2  the open window — tone turn, the thing approaching, "free, free, free"
  3  self-assertion, Josephine at the door, the quick prayer
  4  the descent, Brently's latchkey, "the joy that kills"

Usage: scratchpad/venv/bin/python tools/make_story_pdf.py <story_raw.txt> <out.pdf>
"""
import re
import sys

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (BaseDocTemplate, Frame, PageBreak,
                                PageTemplate, Paragraph, Spacer)

raw = open(sys.argv[1]).read()
# Strip the wiki template header, listen tags, categories, interwiki, PD tag.
# Everything before the story's first line is wiki chrome; everything in
# braces/brackets after it is categories.
raw = raw[raw.index("Knowing that Mrs. Mallard"):]
raw = re.sub(r"\{\{.*?\}\}", "", raw, flags=re.S)
raw = re.sub(r"\[\[.*?\]\]", "", raw)
paragraphs = [p.strip() for p in raw.split("\n") if p.strip()]

# Page assignments by first words (keeps breaks stable if spacing shifts).
BREAK_BEFORE = [
    "She could see in the open square",   # page 2
    "She did not stop to ask",            # page 3
    "She arose at length",                # page 4
]

body = ParagraphStyle("body", fontName="Times-Roman", fontSize=13.5, leading=19.5,
                      spaceAfter=12, firstLineIndent=22)
title = ParagraphStyle("title", fontName="Times-Bold", fontSize=26, leading=32,
                       spaceAfter=4, alignment=1)
byline = ParagraphStyle("byline", fontName="Times-Italic", fontSize=15,
                        leading=20, spaceAfter=22, alignment=1)
folio = ParagraphStyle("folio", fontName="Times-Italic", fontSize=11,
                       leading=14, alignment=2, textColor="#666666")

doc = BaseDocTemplate(sys.argv[2], pagesize=letter,
                      leftMargin=0.95 * inch, rightMargin=0.95 * inch,
                      topMargin=0.85 * inch, bottomMargin=0.85 * inch)
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
doc.addPageTemplates([PageTemplate(id="page", frames=[frame])])

story = [Paragraph("The Story of an Hour", title),
         Paragraph("Kate Chopin · 1894", byline)]
page = 1
for p in paragraphs:
    if any(p.startswith(b) for b in BREAK_BEFORE):
        page += 1
        story.append(PageBreak())
        story.append(Paragraph(f"The Story of an Hour — {page}", folio))
        story.append(Spacer(1, 10))
    story.append(Paragraph(p.replace("&", "&amp;"), body))

doc.build(story)
print(f"wrote {sys.argv[2]} ({page} pages)")
