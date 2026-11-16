'use client';
import {useEffect, useState} from 'react';
import {portalEmbed, portalModules, type PortalModule} from '../../shared/portal-content';
import {createSupabaseBrowserClient, supabaseConfigured} from '../lib/supabase/client';
import './portal.css';

/** Portal da Vinha: como cada módulo funciona, passo a passo, com texto e vídeo. */
export default function PortalVinha() {
  const [current, setCurrent] = useState('pessoas');
  const [videos, setVideos] = useState<Record<string, string>>({});
  // Vídeos cadastrados na Central Vinha › Portal da Vinha.
  useEffect(() => {
    if (!supabaseConfigured) return;
    const client = createSupabaseBrowserClient() as unknown as {
      from: (t: string) => {select: (c: string) => PromiseLike<{data: {module: string; url: string}[] | null}>};
    };
    void client
      .from('vinha_portal_videos')
      .select('module,url')
      .then(({data}) => setVideos(Object.fromEntries((data || []).map((v) => [v.module, v.url]))));
  }, []);
  useEffect(() => {
    const m = new URLSearchParams(location.search).get('modulo');
    if (m && portalModules.some((x) => x.id === m)) setCurrent(m);
  }, []);
  const mod = portalModules.find((m) => m.id === current) as PortalModule;
  const back = typeof window === 'undefined' ? '/painel' : '/painel' + (new URLSearchParams(location.search).get('tenant') ? '?tenant=' + encodeURIComponent(new URLSearchParams(location.search).get('tenant')!) : '');
  function pick(id: string) {
    setCurrent(id);
    const u = new URL(location.href);
    u.searchParams.set('modulo', id);
    history.replaceState({}, '', u);
    window.scrollTo({top: 0});
  }
  const video = portalEmbed(videos[mod.id] || mod.video);
  return (
    <main className="pv">
      <div className="pv-top">
        <a href={back} className="pv-back">
          ‹ Voltar ao painel
        </a>
        <div>
          <p>Portal da Vinha</p>
          <h1>Como cada módulo funciona</h1>
        </div>
      </div>
      <div className="pv-body">
        <nav className="pv-nav" aria-label="Módulos">
          {portalModules.map((m) => (
            <button key={m.id} type="button" aria-current={m.id === current ? 'page' : undefined} onClick={() => pick(m.id)}>
              <span aria-hidden="true">{m.icon}</span>
              <b>{m.title}</b>
              {m.status === 'em breve' && <small>em breve</small>}
            </button>
          ))}
        </nav>
        <article className="pv-article">
          <p className="pv-over">MÓDULO</p>
          <h2>{mod.title}</h2>
          <p className="pv-summary">{mod.summary}</p>
          {mod.status === 'em breve' ? (
            <div className="pv-soon">O guia completo deste módulo entra no portal assim que a análise do módulo for concluída.</div>
          ) : (
            <>
              <div className="pv-video">
                {video ? (
                  <iframe src={video} title={'Vídeo: ' + mod.title} allow="accelerometer; encrypted-media; picture-in-picture" allowFullScreen />
                ) : (
                  <div className="pv-video-soon">
                    <span aria-hidden="true">▶</span>
                    <b>Vídeo em gravação</b>
                    <small>Enquanto isso, siga o passo a passo abaixo.</small>
                  </div>
                )}
              </div>
              <nav className="pv-toc" aria-label="Nesta página">
                {mod.sections.map((s) => (
                  <a key={s.id} href={'#' + s.id}>
                    {s.title}
                  </a>
                ))}
              </nav>
              {mod.sections.map((s) => (
                <section key={s.id} id={s.id} className="pv-section">
                  <h3>{s.title}</h3>
                  {s.text.map((t, i) => (
                    <p key={i}>{t}</p>
                  ))}
                  {s.steps && (
                    <ol>
                      {s.steps.map((t, i) => (
                        <li key={i}>{t}</li>
                      ))}
                    </ol>
                  )}
                  {s.tip && <p className="pv-tip">💡 {s.tip}</p>}
                </section>
              ))}
            </>
          )}
        </article>
      </div>
    </main>
  );
}
