import express from 'express';
import cors from 'cors';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import './db/index.js';
import { departmentsRouter, unitsRouter, accountsRouter, materialsRouter, materialTaxonomyRouter } from './routes/masters.js';
import { indentsRouter } from './routes/indents.js';
import { sanctionIndentsRouter } from './routes/sanctionIndents.js';
import { rfqsRouter } from './routes/rfqs.js';
import { quotationsRouter } from './routes/quotations.js';
import { purchaseOrdersRouter } from './routes/purchaseOrders.js';
import { grnsRouter } from './routes/grns.js';
import { reportsRouter } from './routes/reports.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

app.get('/api/health', (_req, res) => res.json({ ok: true }));

// Masters
app.use('/api/departments', departmentsRouter);
app.use('/api/units', unitsRouter);
app.use('/api/accounts', accountsRouter);
app.use('/api/materials', materialsRouter);
app.use('/api/material-taxonomy', materialTaxonomyRouter);

// Purchase document lifecycle
app.use('/api/purchase-indents', indentsRouter);
app.use('/api/sanction-indents', sanctionIndentsRouter);
app.use('/api/rfqs', rfqsRouter);
app.use('/api/purchase-quotations', quotationsRouter);
app.use('/api/purchase-orders', purchaseOrdersRouter);
app.use('/api/grns', grnsRouter);

// Reports
app.use('/api/reports', reportsRouter);

// Serve the built client (client/dist) when present — a single-service
// deploy (e.g. Railway/Render) runs `npm run build` first, which produces
// this directory; local dev instead runs the Vite dev server separately
// on :5173 and proxies /api here, so this simply finds nothing and no-ops.
const __dirname = dirname(fileURLToPath(import.meta.url));
const clientDist = join(__dirname, '..', '..', 'client', 'dist');
if (existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get(/^(?!\/api).*/, (_req, res) => {
    res.sendFile(join(clientDist, 'index.html'));
  });
}

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  // eslint-disable-next-line no-console
  console.error(err);
  res.status(500).json({ error: err instanceof Error ? err.message : 'Internal server error' });
});

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Thermodrain ERP API listening on :${port}`);
});
