# Thermodrain ERP

Internal ERP for Thermoset Poly Products Pvt. Ltd. (Thermodrain), built from the
`design_handoff_erp` design (Steel variation) plus a real, database-backed
**Purchase** department reverse-engineered from a screen recording of the
legacy "TSS Software" ERP and the `INDENT_REPORT` Excel workbook.

## Stack

- **client/** — React + TypeScript + Vite, React Router. No UI kit; styled
  directly from the Steel design tokens in `client/src/index.css`.
- **server/** — Express + TypeScript, using Node's built-in `node:sqlite`
  (zero native dependencies — deliberately avoided `better-sqlite3` /
  `ffmpeg-static`-style packages that need prebuilt binaries downloaded from
  GitHub releases, since that download is blocked in some sandboxed network
  environments). Data lives in `server/data/erp.db`, created and migrated
  automatically on server start from `server/src/db/schema.sql`.
- **scripts/import_excel.py** — one-time migration of the legacy Purchase
  Excel into the database. Requires `pip install openpyxl`.

## Running it

```bash
npm install                                   # installs both workspaces
npm run seed --workspace server               # base departments/units
python3 scripts/import_excel.py <path-to-xlsx>  # optional: historical data
npm run dev:server                            # API on :4000
npm run dev:client                            # app on :5173 (proxies /api -> :4000)
```

Login screen: click any of the 10 role tiles. Non-admin roles are locked to
their one module; `Admin` sees everything via the sidebar.

## What's real vs. static in this pass

Per the design brief, all 10 modules exist and are navigable. Only **Purchase**
is wired to a real backend + database in this pass — it's the only department
we have a video of. The other 9 (Marketing, Quotation, Work Order, Inventory,
Production, QC, Logistics, the sales-side "Purchase Order", and the Admin
Overview) render the design's own sample data, pixel-for-pixel, with no
backend behind them yet. See "Adding a new department" below for how that
changes for each future department video.

### Role mapping note

The design brief lists a "Procurement" role ("vendor mgmt") separate from a
"Purchase Order" role ("sales ops" — client purchase orders, unrelated to raw
material buying). The video and Excel are about raw-material purchasing, so
that role was renamed **Purchase** and is the one built out fully here. The
original sales-ops "Purchase Order" screen (client POs linked to quotations)
was left as-is, static, per the design.

### Purchase module — document lifecycle

Mirrors the legacy TSS software's menu (`Transactions > Purchase > Order
Processing`), one screen per stage:

1. **Purchase Indent** — a department requests material.
2. **Sanction Indent** — approves/sets accepted quantities; optionally linked
   to an indent.
3. **Request for Quote (RFQ)** — sends a set of materials to one or more
   vendors.
4. **Purchase Quotation** — records a vendor's quoted rates against an RFQ;
   the RFQ detail page shows a side-by-side rate comparison across all
   quotations received.
5. **Purchase Order** — issued to a vendor, with the same fields as the
   legacy screen (delivery/payment terms, transport, GST split, freight,
   discount, round-off) and links back to the Sanction Indent / Quotation it
   came from.
6. **GRN (Goods Receipt Note)** — records what actually arrived against a PO;
   updates the PO's received quantity and status (`issued` →
   `partially_received` → `received`).

Plus **Vendors** and **Materials** masters, and **Reports**: Indent vs PO
(the legacy "Sanction Indent Vs Purchase Order" reconciliation, with a
pending-only filter), Material Rate Trend (replaces the Excel's "TOTAL MONTH
AVG RATE" sheet, computed live from GRN landed cost), and Vendor Performance.

### Historical data import caveats

`scripts/import_excel.py` reconstructs the Indent → Sanction → PO → GRN trail
from the Excel's flat one-line-per-row export, which doesn't actually
separate those steps. A few things to know:

- The Excel has ~2,200 completely empty template rows carrying a leftover
  "TP-" / "PO/TSS/26-27/" placeholder in the number columns but no material,
  qty, or amount — these are skipped, not imported.
- The Excel has no department column, so all historical indents are
  attributed to `STORE` (matches what the video showed as the default).
  There's also no HSN column in the sheet, so historical PO/indent lines have
  no HSN until someone fills it in.
- GRN fields (`receive_qty`, `basic_receive_amount`,
  `freight_gst_recd_basic_amount`, `landed_rate`) map almost 1:1 from the
  sheet's own already-computed columns, so those are the most reliable part
  of the import.
- One Sanction Indent + one Purchase Order is created per distinct legacy
  document number, keeping the real PO numbers (e.g. `PO/TSS/25-26/1183`) so
  old paperwork stays searchable.

## Adding a new department (when its video arrives)

The pattern used for Purchase generalizes directly:

1. **Analyze the video** the same way — extract frames (`ffmpeg -vf fps=...`),
   read screen text/fields directly (OCR wasn't usable in this environment —
   `tesseract.js` fetches its language data at runtime from a CDN that was
   network-blocked here; reading extracted frames directly worked fine).
   Note every screen, field, button, and status the department actually uses.
2. **Extend `server/src/db/schema.sql`** with tables for that department's
   documents (follow the existing pattern: a header table + a `_items` child
   table for line items, `doc_no` generated via `nextDocNumber()` in
   `server/src/lib/docNumber.ts`). `CREATE TABLE IF NOT EXISTS` means this is
   additive — nothing about Purchase's tables needs to change.
3. **Add routes** in `server/src/routes/<department>.ts` following
   `purchaseOrders.ts` or `grns.ts` as a template (a `crudRouter()` from
   `server/src/lib/crud.ts` is enough for simple masters; hand-written routes
   for anything with line items or computed totals). Register in
   `server/src/index.ts`.
4. **Replace the static module** — e.g. `client/src/modules/inventory/
   Inventory.tsx` currently renders hardcoded sample data matching the
   design. Swap it for real screens following `client/src/modules/purchase/`
   as the template: `useApiData()` for lists, the shared `LineItemsEditor`
   for any document with line items, `DataTable`/`Card`/`Badge`/`KpiCard`
   from `client/src/components/ui.tsx` for everything else, so the visual
   language stays consistent with Purchase without re-deriving it.
5. If that department needs its own sub-navigation (Purchase's tab strip is
   `PurchaseShell.tsx`), copy that pattern rather than inventing a new one.

Nothing above requires touching Purchase's code — each department's real
build-out is additive and isolated to its own schema tables, routes, and
module folder.
