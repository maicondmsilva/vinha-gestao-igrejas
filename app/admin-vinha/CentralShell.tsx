'use client';
import {useEffect, useRef, useState, type ReactNode} from 'react';
import {createSupabaseBrowserClient, supabaseConfigured} from '../lib/supabase/client';
import './central.css';

type Item = {href: string; label: string; badge?: 'trials' | 'chat'};
type Group = {title: string; icon: string; items: Item[]};

/** Menu único da Central: agrupado por assunto, igual em todas as páginas. */
export function centralGroups(credits: boolean): Group[] {
  return [
    {
      title: 'Clientes',
      icon: '◎',
      items: [
        {href: '/admin-vinha', label: 'Ministérios'},
        {href: '/admin-vinha/demonstracoes', label: 'Demonstrações', badge: 'trials'},
        {href: '/admin-vinha/hierarquia', label: 'Hierarquia'},
        {href: '/admin-vinha/hierarquia/solicitacoes', label: 'Solicitações'},
      ],
    },
    {
      title: 'Aplicativos',
      icon: '▣',
      items: [{href: '/admin-vinha/aplicativos', label: 'Apps dos ministérios'}],
    },
    {
      title: 'Comercial',
      icon: '◇',
      items: [
        {href: '/admin-vinha/planos', label: 'Planos e preços'},
        {href: '/admin-vinha/contratos', label: 'Contratos por igreja'},
        ...(credits ? [{href: '/admin-vinha/contratos/documentos', label: 'Créditos e ajustes'}] : []),
      ],
    },
    {
      title: 'Financeiro',
      icon: 'R$',
      items: [
        {href: '/admin-vinha/faturamento', label: 'Assinaturas e faturas'},
        {href: '/admin-vinha/faturamento/consolidadas', label: 'Faturas consolidadas'},
        {href: '/admin-vinha/faturamento/clientes', label: 'Dados de cobrança'},
        {href: '/admin-vinha/faturamento/avisos', label: 'Avisos de cobrança'},
        {href: '/admin-vinha/faturamento/configuracoes', label: 'Configurar cobrança'},
        {href: '/admin-vinha/financeiro-integracoes', label: 'Integrações financeiras'},
        {href: '/admin-vinha/contas-recebedoras', label: 'Contas recebedoras'},
      ],
    },
    {
      title: 'Atendimento',
      icon: '◌',
      items: [
        {href: '/admin-vinha/chat', label: 'Chat', badge: 'chat'},
        {href: '/admin-vinha/chat/setores', label: 'Setores do chat'},
        {href: '/admin-vinha/suporte', label: 'Chamados'},
        {href: '/admin-vinha/suporte/conhecimento', label: 'Qualidade e respostas'},
        {href: '/admin-vinha/disponibilidade', label: 'Disponibilidade'},
      ],
    },
    {
      title: 'Automações',
      icon: '✦',
      items: [
        {href: '/admin-vinha/automacoes', label: 'Automações'},
        {href: '/admin-vinha/automacoes/notificacoes', label: 'Alertas'},
        {href: '/admin-vinha/automacoes/execucoes', label: 'Execuções'},
      ],
    },
    {
      title: 'Vinha',
      icon: 'V',
      items: [
        {href: '/admin-vinha/empresa', label: 'Dados da empresa'},
        {href: '/admin-vinha/operadores', label: 'Operadores'},
        {href: '/admin-vinha/portal', label: 'Portal da Vinha'},
        {href: '/admin-vinha/guia', label: 'Guia da Central'},
      ],
    },
  ];
}
const roleLabel: Record<string, string> = {owner: 'Responsável', admin: 'Administração', support: 'Suporte', read_only: 'Consulta'};
/** Página atual = o item com o caminho mais longo que combina (ex.: /faturamento/clientes antes de /faturamento). */
function activeHref(path: string, groups: Group[]) {
  let best = '';
  for (const g of groups) for (const i of g.items) if ((path === i.href || path.startsWith(i.href + '/')) && i.href.length > best.length) best = i.href;
  return best;
}

export default function CentralShell({children, credits}: {children: ReactNode; credits: boolean}) {
  const groups = centralGroups(credits);
  const [path, setPath] = useState(''),
    [open, setOpen] = useState(false),
    [operator, setOperator] = useState<{name: string; email: string; role: string} | null>(null),
    [trials, setTrials] = useState(0),
    [chat, setChat] = useState(0),
    [alerts, setAlerts] = useState(false),
    seen = useRef<Map<string, string> | null>(null);
  useEffect(() => setPath(location.pathname.replace(/\/$/, '') || '/admin-vinha'), []);
  useEffect(() => {
    void fetch('/api/platform/session', {cache: 'no-store'})
      .then(async (r) => (r.ok ? ((await r.json()) as {user?: {name: string; email: string; role: string}}) : null))
      .then((d) => {
        if (d?.user) setOperator(d.user);
      })
      .catch(() => {});
  }, []);
  // Avisos: demonstrações vencendo e conversas não lidas (só com a aba visível).
  useEffect(() => {
    try {
      setAlerts(localStorage.getItem('vinha-chat-alerts') === 'true');
    } catch {}
    let live = true;
    const load = async () => {
      if (document.hidden) return;
      const [t, c] = await Promise.all([
        fetch('/api/platform/trials', {cache: 'no-store'})
          .then((r) => (r.ok ? r.json() : null))
          .catch(() => null),
        fetch('/api/platform/chat', {cache: 'no-store'})
          .then((r) => (r.ok ? r.json() : null))
          .catch(() => null),
      ]);
      if (!live) return;
      const s = (t as {summary?: {ending?: number; expired?: number}} | null)?.summary;
      setTrials((s?.ending || 0) + (s?.expired || 0));
      const conv = ((c as {conversations?: {id: string; status: string; unread: boolean; last_message_at: string}[]} | null)?.conversations || []).filter(
        (x) => x.status === 'open' && x.unread,
      );
      setChat(conv.length);
      let enabled = false;
      try {
        enabled = localStorage.getItem('vinha-chat-alerts') === 'true';
      } catch {}
      const fresh = seen.current && conv.some((x) => seen.current?.get(x.id) !== x.last_message_at);
      seen.current = new Map(conv.map((x) => [x.id, x.last_message_at]));
      if (fresh && enabled && 'Notification' in window && Notification.permission === 'granted') new Notification('Vinha · nova mensagem no chat');
    };
    void load();
    const t = setInterval(load, 60000);
    return () => {
      live = false;
      clearInterval(t);
    };
  }, []);
  async function toggleAlerts() {
    const next = !alerts;
    if (next && 'Notification' in window && Notification.permission === 'default') await Notification.requestPermission();
    setAlerts(next);
    try {
      localStorage.setItem('vinha-chat-alerts', String(next));
    } catch {}
  }
  async function leave() {
    try {
      if (supabaseConfigured) await createSupabaseBrowserClient().auth.signOut({scope: 'local'});
    } finally {
      location.replace('/central-vinha/login');
    }
  }
  const current = activeHref(path, groups),
    group = groups.find((g) => g.items.some((i) => i.href === current)),
    page = group?.items.find((i) => i.href === current);
  const badge = (b?: Item['badge']) => (b === 'trials' ? trials : b === 'chat' ? chat : 0);
  const initials = (operator?.name || 'V')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
  return (
    <div className={'central-shell' + (open ? ' nav-open' : '')}>
      <aside className="central-side" aria-label="Menu da Central">
        <a className="central-brand" href="/admin-vinha">
          <i>V</i>
          <span>
            <b>Central da Vinha</b>
            <small>Administração da plataforma</small>
          </span>
        </a>
        <nav>
          {groups.map((g) => (
            <section key={g.title}>
              <p>
                <span aria-hidden>{g.icon}</span>
                {g.title}
              </p>
              {g.items.map((i) => (
                <a key={i.href} href={i.href} aria-current={i.href === current ? 'page' : undefined} onClick={() => setOpen(false)}>
                  {i.label}
                  {badge(i.badge) > 0 && <b className="central-badge">{badge(i.badge)}</b>}
                </a>
              ))}
            </section>
          ))}
        </nav>
        <a className="central-out" href="https://app.vinhaigrejas.com.br/painel">
          Painel das igrejas ↗
        </a>
      </aside>
      {open && <button type="button" className="central-backdrop" aria-label="Fechar menu" onClick={() => setOpen(false)} />}
      <div className="central-main">
        <header className="central-top">
          <button type="button" className="central-menu" aria-label="Abrir menu" aria-expanded={open} onClick={() => setOpen(true)}>
            ☰
          </button>
          <div className="central-crumb">
            <small>{group?.title || 'Central da Vinha'}</small>
            <b>{page?.label || 'Central'}</b>
          </div>
          <button
            type="button"
            className={'central-alerts' + (alerts ? ' on' : '')}
            aria-pressed={alerts}
            onClick={() => void toggleAlerts()}
            title="Som e aviso do navegador para novas mensagens do chat"
          >
            {alerts ? '🔔 Alertas do chat' : '🔕 Alertas do chat'}
          </button>
          <div className="central-operator">
            <span className="central-avatar">{initials}</span>
            <span>
              <b>{operator?.name || 'Operador'}</b>
              <small>{roleLabel[operator?.role || ''] || 'Operador Vinha'}</small>
            </span>
            <button type="button" onClick={() => void leave()}>
              Sair
            </button>
          </div>
        </header>
        <div className="central-content">{children}</div>
      </div>
    </div>
  );
}
