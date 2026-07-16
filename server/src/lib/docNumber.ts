import { db } from '../db/index.js';

/** Indian fiscal year label for a date, e.g. 2026-07-16 -> "25-26"... actually FY Apr-Mar: July 2026 -> "26-27". */
export function fiscalYearLabel(date = new Date()): string {
  const y = date.getFullYear();
  const startYear = date.getMonth() >= 3 ? y : y - 1; // April = month index 3
  const shortStart = String(startYear).slice(-2);
  const shortEnd = String(startYear + 1).slice(-2);
  return `${shortStart}-${shortEnd}`;
}

/**
 * Next doc number for a series, formatted `${prefix}/${fiscalYear}/${seq}`
 * (mirrors the legacy "PO/TSS/25-26/1183" style already familiar to the
 * Purchase team). Scans the given table/column for the current fiscal
 * year's max sequence rather than keeping a separate counter table, so
 * numbering self-heals if a row is deleted mid-year.
 */
export function nextDocNumber(
  table: string,
  column: string,
  prefix: string,
  date = new Date(),
): string {
  const fy = fiscalYearLabel(date);
  const like = `${prefix}/${fy}/%`;
  const row = db
    .prepare(`SELECT ${column} AS docNo FROM ${table} WHERE ${column} LIKE ? ORDER BY id DESC LIMIT 1`)
    .get(like) as { docNo: string } | undefined;
  let nextSeq = 1;
  if (row?.docNo) {
    const parts = row.docNo.split('/');
    const lastSeq = Number(parts[parts.length - 1]);
    if (!Number.isNaN(lastSeq)) nextSeq = lastSeq + 1;
  }
  return `${prefix}/${fy}/${String(nextSeq).padStart(4, '0')}`;
}
