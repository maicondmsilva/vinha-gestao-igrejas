import AdminVinhaGate from './AdminVinhaGate';
import CentralShell from './CentralShell';
import './chat/team-chat.css';
import './faturamento/financial.css';
import './hierarquia/hierarchy.css';
import {ledgerPilotEnabled} from '../lib/ledger-pilot';
// Estrutura única da Central: menu agrupado e topo com o operador em todas as páginas.
export default function AdminVinhaLayout({children}: {children: React.ReactNode}) {
  return (
    <AdminVinhaGate>
      <CentralShell credits={process.env.VINHA_PLAN_PRORATION_PILOT === 'true' && ledgerPilotEnabled(process.env)}>{children}</CentralShell>
    </AdminVinhaGate>
  );
}
