import DashboardApp from '../../DashboardApp';
import AccessGate from '../../AccessGate';

// Same panel as /painel; the module comes from the address (shared/dashboard-route.ts).
export default function Page(){return <AccessGate><DashboardApp/></AccessGate>}
