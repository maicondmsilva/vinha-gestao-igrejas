import DashboardApp from '../DashboardApp';
import AccessGate from '../AccessGate';

export default function Painel(){return <AccessGate><DashboardApp/></AccessGate>}
