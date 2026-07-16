import type { ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './state/AuthContext';
import { LoginScreen } from './components/LoginScreen';
import { Shell, moduleHome } from './components/Shell';
import { Overview } from './modules/overview/Overview';
import { Marketing } from './modules/marketing/Marketing';
import { Quotation } from './modules/quotation/Quotation';
import { SalesPurchaseOrder } from './modules/salesPurchaseOrder/SalesPurchaseOrder';
import { WorkOrder } from './modules/workOrder/WorkOrder';
import { Inventory } from './modules/inventory/Inventory';
import { Production } from './modules/production/Production';
import { QualityControl } from './modules/qc/QualityControl';
import { Logistics } from './modules/logistics/Logistics';
import { PurchaseShell } from './modules/purchase/PurchaseShell';
import { Dashboard as PurchaseDashboard } from './modules/purchase/Dashboard';
import { Vendors } from './modules/purchase/Vendors';
import { Materials } from './modules/purchase/Materials';
import { IndentList } from './modules/purchase/Indents/IndentList';
import { IndentForm } from './modules/purchase/Indents/IndentForm';
import { SanctionList } from './modules/purchase/SanctionIndents/SanctionList';
import { SanctionForm } from './modules/purchase/SanctionIndents/SanctionForm';
import { RfqList } from './modules/purchase/Rfqs/RfqList';
import { RfqForm } from './modules/purchase/Rfqs/RfqForm';
import { QuotationList } from './modules/purchase/Quotations/QuotationList';
import { QuotationForm } from './modules/purchase/Quotations/QuotationForm';
import { PoList } from './modules/purchase/PurchaseOrders/PoList';
import { PoForm } from './modules/purchase/PurchaseOrders/PoForm';
import { PoDetail } from './modules/purchase/PurchaseOrders/PoDetail';
import { GrnList } from './modules/purchase/Grns/GrnList';
import { GrnForm } from './modules/purchase/Grns/GrnForm';
import { Reports as PurchaseReports } from './modules/purchase/Reports/Reports';

/** Non-admin roles are locked to their one module; admin can reach every module. */
function Guarded({ moduleKey, children }: { moduleKey: string; children: ReactNode }) {
  const { role } = useAuth();
  if (!role) return <Navigate to="/" replace />;
  if (role !== 'admin' && role !== moduleKey) return <Navigate to={moduleHome(role)} replace />;
  return <>{children}</>;
}

function AppRoutes() {
  const { role } = useAuth();

  if (!role) {
    return (
      <Routes>
        <Route path="*" element={<LoginScreen />} />
      </Routes>
    );
  }

  return (
    <Routes>
      <Route path="/" element={<Navigate to={moduleHome(role)} replace />} />

      <Route path="/overview" element={<Guarded moduleKey="admin"><Shell activeModule="overview"><Overview /></Shell></Guarded>} />
      <Route path="/marketing" element={<Guarded moduleKey="marketing"><Shell activeModule="marketing"><Marketing /></Shell></Guarded>} />
      <Route path="/quotation" element={<Guarded moduleKey="quotation"><Shell activeModule="quotation"><Quotation /></Shell></Guarded>} />
      <Route path="/sales-po" element={<Guarded moduleKey="salesPO"><Shell activeModule="salesPO"><SalesPurchaseOrder /></Shell></Guarded>} />
      <Route path="/work-order" element={<Guarded moduleKey="workorder"><Shell activeModule="workorder"><WorkOrder /></Shell></Guarded>} />
      <Route path="/inventory" element={<Guarded moduleKey="inventory"><Shell activeModule="inventory"><Inventory /></Shell></Guarded>} />
      <Route path="/production" element={<Guarded moduleKey="production"><Shell activeModule="production"><Production /></Shell></Guarded>} />
      <Route path="/qc" element={<Guarded moduleKey="qc"><Shell activeModule="qc"><QualityControl /></Shell></Guarded>} />
      <Route path="/logistics" element={<Guarded moduleKey="logistics"><Shell activeModule="logistics"><Logistics /></Shell></Guarded>} />

      <Route path="/purchase/*" element={
        <Guarded moduleKey="purchase">
          <Shell activeModule="purchase" title="Purchase">
            <Routes>
              <Route path="/" element={<PurchaseShell />}>
                <Route index element={<PurchaseDashboard />} />
                <Route path="vendors" element={<Vendors />} />
                <Route path="materials" element={<Materials />} />
                <Route path="indents" element={<IndentList />} />
                <Route path="indents/:id" element={<IndentForm />} />
                <Route path="sanction-indents" element={<SanctionList />} />
                <Route path="sanction-indents/:id" element={<SanctionForm />} />
                <Route path="rfqs" element={<RfqList />} />
                <Route path="rfqs/:id" element={<RfqForm />} />
                <Route path="quotations" element={<QuotationList />} />
                <Route path="quotations/new" element={<QuotationForm />} />
                <Route path="purchase-orders" element={<PoList />} />
                <Route path="purchase-orders/new" element={<PoForm />} />
                <Route path="purchase-orders/:id" element={<PoDetail />} />
                <Route path="grns" element={<GrnList />} />
                <Route path="grns/new" element={<GrnForm />} />
                <Route path="grns/:id" element={<GrnForm />} />
                <Route path="reports" element={<PurchaseReports />} />
              </Route>
            </Routes>
          </Shell>
        </Guarded>
      } />

      <Route path="*" element={<Navigate to={moduleHome(role)} replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  );
}
