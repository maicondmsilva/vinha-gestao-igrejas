import DashboardApp from '../../../DashboardApp';
import AccessGate from '../../../AccessGate';

export default function Page(){return <AccessGate><DashboardApp/></AccessGate>}
