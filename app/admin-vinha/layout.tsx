import Link from 'next/link';
import './faturamento/financial.css';
export default function AdminVinhaLayout({children}:{children:React.ReactNode}){return <>{children}<Link className="admin-finance-shortcut" href="/admin-vinha/faturamento/clientes">▣ Dados financeiros</Link></>}
