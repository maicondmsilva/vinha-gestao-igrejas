import AdminVinhaGate from './AdminVinhaGate';
import TrialNavigation from './TrialNavigation';
import ChatNavigation from './ChatNavigation';
import './chat/team-chat.css';
import './faturamento/financial.css';
import './hierarquia/hierarchy.css';
import FinancialNavigation from './financeiro-integracoes/FinancialNavigation';
import {ledgerPilotEnabled} from '../lib/ledger-pilot';
export default function AdminVinhaLayout({children}:{children:React.ReactNode}){
 return <AdminVinhaGate>{children}<nav className="admin-shortcuts" aria-label="Atalhos da Central">
  {process.env.VINHA_PLAN_PRORATION_PILOT==='true'&&ledgerPilotEnabled(process.env)&&<a href="/admin-vinha/contratos/documentos">Créditos e ajustes</a>}
  <a href="/admin-vinha/contas-recebedoras">Contas recebedoras</a><a href="/admin-vinha/guia">? Guia da Central</a><a href="/admin-vinha/disponibilidade">◇ Disponibilidade</a><a href="/admin-vinha/contratos">▤ Contratos por igreja</a><FinancialNavigation/><TrialNavigation/><ChatNavigation/>
  <a href="/admin-vinha/suporte">◌ Suporte</a><a href="/admin-vinha/suporte/conhecimento">◇ Qualidade</a><a href="/admin-vinha/automacoes">✦ Automações</a>
  <a href="/admin-vinha/automacoes/notificacoes">⌁ Alertas</a><a href="/admin-vinha/automacoes/execucoes">◷ Execuções</a><a href="/admin-vinha/operadores">♙ Operadores</a>
  <a href="/admin-vinha/hierarquia/solicitacoes">◌ Solicitações</a><a href="/admin-vinha/faturamento/consolidadas">▤ Consolidadas</a><a href="/admin-vinha/hierarquia">⌘ Hierarquia</a><a href="/admin-vinha/faturamento/clientes">▣ Dados financeiros</a>
 </nav></AdminVinhaGate>;
}
