'use client';
import {createClient} from '@supabase/supabase-js';
import {useEffect, useState} from 'react';
import '../../member-auth.css';

type Result = {
  found: boolean;
  code?: string;
  title?: string;
  version?: number;
  church?: string;
  acceptedAt?: string;
  signer?: string;
  subject?: string | null;
  choices?: Record<string, boolean>;
  sha256?: string;
  intact?: boolean;
  revokedAt?: string | null;
  revokedReason?: string | null;
};
const labels: Record<string, string> = {photos: 'Fotos', videos: 'Vídeos', social: 'Redes sociais', live: 'Transmissões ao vivo'};

/** Página pública: confere se um termo assinado pela Vinha é autêntico e não foi alterado. */
export default function VerifyConsent() {
  const [r, setR] = useState<Result | null>(null);
  useEffect(() => {
    const code = decodeURIComponent(location.pathname.split('/').pop() || '').toUpperCase();
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL,
      key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) {
      setR({found: false});
      return;
    }
    createClient(url, key, {auth: {persistSession: false}})
      .rpc('consent_verify', {p_code: code})
      .then(({data}) => setR((data as Result) || {found: false}));
  }, []);
  const ok = r?.found && r.intact && !r.revokedAt;
  return (
    <main className="ma">
      <section className="ma-card">
        <header className="ma-head">
          <span className="ma-logo">V</span>
          <div>
            <b>Vinha</b>
            <small>Verificação de documento</small>
          </div>
        </header>
        <div className="ma-body">
          {!r && <p>Conferindo…</p>}
          {r && !r.found && (
            <>
              <p className="ma-over">Não encontrado</p>
              <h1>Código não existe</h1>
              <p className="ma-alert">Confira se o código foi digitado exatamente como aparece no documento (ex.: VNH-7K2Q-9MXA).</p>
            </>
          )}
          {r?.found && (
            <>
              <span className="ma-ok" aria-hidden="true" style={ok ? undefined : {background: '#fff4e0', color: '#9a5b00'}}>
                {ok ? '✓' : '!'}
              </span>
              <p className="ma-over">{ok ? 'Documento autêntico' : r.intact ? 'Documento autêntico, sem validade atual' : 'Documento alterado'}</p>
              <h1>{r.title}</h1>
              {!r.intact && <p className="ma-alert">O conteúdo guardado não confere com a impressão digital original. Procure a igreja.</p>}
              {r.revokedAt && (
                <p className="ma-alert">
                  {r.revokedReason || 'Revogado'} em {new Date(r.revokedAt).toLocaleString('pt-BR', {timeZone: 'America/Sao_Paulo'})}.
                </p>
              )}
              <p>
                <b>Igreja:</b> {r.church}
                <br />
                <b>Assinado por:</b> {r.signer}
                {r.subject ? (
                  <>
                    <br />
                    <b>Criança:</b> {r.subject}
                  </>
                ) : null}
                <br />
                <b>Data:</b> {r.acceptedAt && new Date(r.acceptedAt).toLocaleString('pt-BR', {timeZone: 'America/Sao_Paulo'})}
                <br />
                <b>Versão do termo:</b> {r.version || 'padrão'}
                <br />
                <b>Código:</b> {r.code}
              </p>
              {r.choices && Object.keys(r.choices).length > 0 && (
                <p>
                  <b>Autorizações:</b>{' '}
                  {Object.entries(r.choices)
                    .map(([k, v]) => `${labels[k] || k}: ${v ? 'sim' : 'não'}`)
                    .join(' · ')}
                </p>
              )}
              <p className="ma-note" style={{wordBreak: 'break-all'}}>
                SHA-256: {r.sha256}
              </p>
            </>
          )}
          <p className="ma-note">Assinatura eletrônica simples (Lei 14.063/2020). Dados pessoais completos ficam só com a igreja.</p>
        </div>
      </section>
    </main>
  );
}
