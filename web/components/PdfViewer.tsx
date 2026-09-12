"use client";

// Client-side PDF viewer: no server storage. Renders the current page to a
// canvas with pdfjs-dist, exposes prev/next paging, and extracts text for
// every page plus the full document on load.

import { useCallback, useEffect, useRef, useState } from "react";
import type { PDFDocumentProxy } from "pdfjs-dist";

export interface ExtractedDoc {
  pageCount: number;
  pageTexts: string[]; // index 0 = page 1
  fullText: string;
  fileName: string;
}

interface Props {
  file: File | null;
  onExtracted: (doc: ExtractedDoc) => void;
  onPageChange: (pageNumber: number) => void;
}

async function loadPdfjs() {
  const pdfjs = await import("pdfjs-dist");
  pdfjs.GlobalWorkerOptions.workerSrc = new URL(
    "pdfjs-dist/build/pdf.worker.min.mjs",
    import.meta.url
  ).toString();
  return pdfjs;
}

export default function PdfViewer({ file, onExtracted, onPageChange }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const holderRef = useRef<HTMLDivElement>(null);
  const docRef = useRef<PDFDocumentProxy | null>(null);
  const renderTaskRef = useRef<{ cancel: () => void } | null>(null);
  const [pageNumber, setPageNumber] = useState(1);
  const [pageCount, setPageCount] = useState(0);
  const [loading, setLoading] = useState(false);

  const renderPage = useCallback(async (num: number) => {
    const doc = docRef.current;
    const canvas = canvasRef.current;
    const holder = holderRef.current;
    if (!doc || !canvas || !holder) return;
    const page = await doc.getPage(num);
    const base = page.getViewport({ scale: 1 });
    const maxWidth = holder.clientWidth - 8 || 700;
    const scale = maxWidth / base.width;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const viewport = page.getViewport({ scale: scale * dpr });
    canvas.width = viewport.width;
    canvas.height = viewport.height;
    canvas.style.width = `${viewport.width / dpr}px`;
    canvas.style.height = `${viewport.height / dpr}px`;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    renderTaskRef.current?.cancel();
    const task = page.render({ canvasContext: ctx, viewport });
    renderTaskRef.current = task;
    try {
      await task.promise;
    } catch {
      // cancelled by a newer render
    }
  }, []);

  // Load + extract when a new file arrives.
  useEffect(() => {
    if (!file) return;
    let cancelled = false;
    setLoading(true);
    (async () => {
      const pdfjs = await loadPdfjs();
      const data = await file.arrayBuffer();
      const doc = await pdfjs.getDocument({ data }).promise;
      if (cancelled) return;
      docRef.current = doc;
      setPageCount(doc.numPages);
      setPageNumber(1);
      await renderPage(1);

      const pageTexts: string[] = [];
      for (let i = 1; i <= doc.numPages; i++) {
        const page = await doc.getPage(i);
        const content = await page.getTextContent();
        const text = content.items
          .map((item) => ("str" in item ? item.str : ""))
          .join(" ")
          .replace(/\s+/g, " ")
          .trim();
        pageTexts.push(text);
        if (cancelled) return;
      }
      setLoading(false);
      onExtracted({
        pageCount: doc.numPages,
        pageTexts,
        fullText: pageTexts
          .map((t, i) => `--- Page ${i + 1} ---\n${t}`)
          .join("\n\n"),
        fileName: file.name,
      });
      onPageChange(1);
    })().catch(() => setLoading(false));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file]);

  const goTo = useCallback(
    (num: number) => {
      if (!docRef.current) return;
      const clamped = Math.min(Math.max(1, num), docRef.current.numPages);
      if (clamped === pageNumber) return;
      setPageNumber(clamped);
      void renderPage(clamped);
      onPageChange(clamped);
    },
    [pageNumber, renderPage, onPageChange]
  );

  // Re-render on container resize.
  useEffect(() => {
    const holder = holderRef.current;
    if (!holder) return;
    const observer = new ResizeObserver(() => {
      if (docRef.current) void renderPage(pageNumber);
    });
    observer.observe(holder);
    return () => observer.disconnect();
  }, [pageNumber, renderPage]);

  return (
    <div className="pdf-viewer">
      <div className="pdf-canvas-holder" ref={holderRef}>
        {file ? (
          <canvas ref={canvasRef} className="pdf-canvas" />
        ) : (
          <div className="pdf-empty">
            <div className="pdf-empty-mark">§</div>
            <p>Upload a PDF to lay it on the table.</p>
          </div>
        )}
        {loading && <div className="pdf-loading">Reading the document…</div>}
      </div>
      {file && pageCount > 0 && (
        <div className="pdf-controls">
          <button
            className="btn btn-page"
            onClick={() => goTo(pageNumber - 1)}
            disabled={pageNumber <= 1}
          >
            ‹ Prev
          </button>
          <span className="pdf-pageinfo">
            Page {pageNumber} of {pageCount}
          </span>
          <button
            className="btn btn-page"
            onClick={() => goTo(pageNumber + 1)}
            disabled={pageNumber >= pageCount}
          >
            Next ›
          </button>
        </div>
      )}
    </div>
  );
}
