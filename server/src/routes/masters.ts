import { Router } from 'express';
import { crudRouter } from '../lib/crud.js';
import { db } from '../db/index.js';

export const departmentsRouter = crudRouter({
  table: 'departments',
  columns: ['name', 'alias', 'code', 'inactive'],
  orderBy: 'name ASC',
  searchColumn: 'name',
});

export const unitsRouter = crudRouter({
  table: 'units',
  columns: ['name', 'conversion_factor', 'notes'],
  orderBy: 'name ASC',
  searchColumn: 'name',
});

export const accountsRouter = crudRouter({
  table: 'accounts',
  columns: [
    'kind', 'name', 'alias', 'code', 'group_name',
    'office_address1', 'office_address2', 'office_address3',
    'city', 'state', 'country', 'pincode', 'area',
    'telephone', 'mobile_no', 'email', 'website',
    'gst_no', 'pan_no', 'drug_licence', 'currency',
    'cr_days', 'credit_limit', 'tax_type', 'tcs_percent', 'business_type',
    'opening_balance', 'closing_balance', 'inactive',
  ],
  orderBy: 'name ASC',
  searchColumn: 'name',
});

export const materialsRouter = crudRouter({
  table: 'materials',
  columns: [
    'code', 'name', 'hsn_no', 'unit_id', 'material_type',
    'group_head', 'sub_group', 'gst_percent', 'reorder_level', 'inactive',
  ],
  orderBy: 'name ASC',
  searchColumn: 'name',
});

// Read-only taxonomy lookup for the Indent/PO material picker's autocomplete.
export const materialTaxonomyRouter = Router();
materialTaxonomyRouter.get('/', (_req, res) => {
  res.json(db.prepare('SELECT DISTINCT material_type, group_head, sub_group FROM material_taxonomy ORDER BY material_type, group_head, sub_group').all());
});
materialTaxonomyRouter.get('/material-types', (_req, res) => {
  res.json(db.prepare('SELECT DISTINCT material_type FROM material_taxonomy ORDER BY material_type').all().map((r: any) => r.material_type));
});
