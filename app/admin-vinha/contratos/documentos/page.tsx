import {ledgerPilotEnabled} from '../../../lib/ledger-pilot';
import Documents from './Documents';
export default function DocumentsPage(){
 if(process.env.VINHA_PLAN_PRORATION_PILOT!=='true'||!ledgerPilotEnabled(process.env))return <main className="team-chat-page"><h1>Documentos proporcionais</h1><p>Disponível somente no ambiente de homologação isolado.</p><a href="/admin-vinha/contratos">Voltar aos contratos</a></main>;
 return <Documents/>;
}
