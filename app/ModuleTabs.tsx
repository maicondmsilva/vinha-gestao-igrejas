'use client';
import {useEffect, useRef, useState, type MouseEvent} from 'react';
import {communicationPages, programmingPages} from '../shared/dashboard-menu';
import {currentDashboardQuery, dashboardUrl} from '../shared/dashboard-route';
import './vinha-module.css';

const modules = {
  eventos: {label: 'Programação', pages: programmingPages, fallback: 'proximos'},
  comunicacao: {label: 'Comunicação', pages: communicationPages, fallback: 'avisos'},
} as const;

/**
 * Section tabs for Programação and Comunicação, on top of the page. Each tab is a real address
 * (/painel/programacao/agenda) that can be shared or bookmarked; the side menu keeps the same entries.
 */
export default function ModuleTabs({page, navigate}: {page: keyof typeof modules; navigate: (section: string) => void}) {
  const m = modules[page];
  const [section, setSection] = useState<string>(() => currentDashboardQuery().get('secao') || m.fallback),
    [search, setSearch] = useState(() => (typeof location === 'undefined' ? '' : location.search));
  useEffect(() => {
    const sync = () => {
      setSection(currentDashboardQuery().get('secao') || m.fallback);
      setSearch(location.search);
    };
    addEventListener('popstate', sync);
    return () => removeEventListener('popstate', sync);
  }, [m.fallback]);
  const list = useRef<HTMLOListElement>(null);
  // On phones the tabs scroll sideways: keep the current one in view.
  useEffect(() => {
    const el = list.current?.querySelector<HTMLElement>('[aria-current="page"]');
    if (el && list.current) list.current.scrollLeft = Math.max(0, el.offsetLeft - 16);
  }, [section]);
  function follow(e: MouseEvent<HTMLAnchorElement>, id: string) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
    e.preventDefault();
    navigate(id);
  }
  return (
    <nav aria-label={`Seções de ${m.label}`} className="vinha-module-tabs">
      <ol ref={list} className="flex gap-1 overflow-x-auto border-b border-vinha-line px-0.5" role="list">
        {m.pages.map(([id, label]) => {
          const current = id === section;
          return (
            <li key={id} className="shrink-0">
              <a
                href={dashboardUrl(page, id, search)}
                aria-current={current ? 'page' : undefined}
                onClick={(e) => follow(e, id)}
                className={
                  'inline-flex min-h-11 items-center rounded-t-vinha-sm border-b-[3px] px-3.5 text-[14px] font-semibold no-underline transition-colors focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-vinha-brand ' +
                  (current ? 'border-vinha-brand text-vinha-brand-dark' : 'border-transparent text-vinha-muted hover:bg-vinha-brand-soft hover:text-vinha-ink')
                }
              >
                {label}
              </a>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
