import Link from 'next/link';
import './faturamento/financial.css';
import './hierarquia/hierarchy.css';
export default function AdminVinhaLayout({children}:{children:React.ReactNode}){return <>{children}<div className="admin-shortcuts"><Link href="/admin-vinha/hierarquia/solicitacoes">◌ Solicitações</Link><Link href="/admin-vinha/faturamento/consolidadas">▤ Consolidadas</Link><Link href="/admin-vinha/hierarquia">⌘ Hierarquia</Link><Link href="/admin-vinha/faturamento/clientes">▣ Dados financeiros</Link></div></>}
