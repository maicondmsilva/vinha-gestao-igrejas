'use client';
import {useEffect, useState} from 'react';
import QRCode from 'qrcode';
import {settingsUrl} from './lib/settings-navigation';
import {visitorHeardLabel, visitorUrl} from '../shared/visitors';

type Entry = {
  person: string;
  name: string;
  source: 'qr' | 'staff';
  at: string;
  answers: {firstTime?: boolean; heard?: string; contact?: boolean; visit?: boolean; prayer?: string; note?: string};
};

/** Pessoas › Visitantes: QR Code da igreja para imprimir e os cadastros recentes para acompanhamento. */
export default function VisitorQr({unitId, unitName}: {unitId: string; unitName: string}) {
  const [qr, setQr] = useState(''),
    [items, setItems] = useState<Entry[] | null>(null),
    [error, setError] = useState('');
  const valid = /^[0-9a-f-]{36}$/i.test(unitId),
    link = valid ? visitorUrl(unitId) : '';
  useEffect(() => {
    let live = true;
    setQr('');
    setItems(null);
    setError('');
    if (!valid) return;
    void QRCode.toDataURL(link, {width: 560, margin: 2, color: {dark: '#163d2f', light: '#ffffff'}}).then((u) => live && setQr(u));
    void fetch(settingsUrl('/api/people/visitors?' + new URLSearchParams({unit: unitId})), {cache: 'no-store'})
      .then(async (r) => {
        const d = await r.json().catch(() => ({}));
        if (!live) return;
        if (!r.ok) setError(d.error || 'Não foi possível carregar.');
        else setItems(d.items || []);
      })
      .catch(() => live && setError('Sem conexão.'));
    return () => {
      live = false;
    };
  }, [unitId, valid, link]);
  if (!valid) return <p className="pd-empty">Escolha uma igreja no topo da página para gerar o QR Code de visitantes.</p>;
  function print() {
    const w = window.open('', '_blank', 'noopener,noreferrer,width=720,height=900');
    if (!w) return;
    w.document.write(
      `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>QR Code de visitantes</title><style>body{font-family:Georgia,serif;text-align:center;color:#163d2f;padding:40px}h1{font-size:40px;margin:0 0 6px}p{font:20px Arial,sans-serif;margin:6px 0}img{width:420px;height:420px;margin:24px auto;display:block;border:10px solid #dbbb70;border-radius:24px}small{font:14px Arial,sans-serif;color:#5f6f64}</style></head><body><p>${unitName.replace(/[&<>"']/g, (c) => '&#' + c.charCodeAt(0) + ';')}</p><h1>Seja bem-vindo!</h1><p>Aponte a câmera do celular e faça seu cadastro de visitante.</p><img src="${qr}" alt="QR Code"><small>${link}</small><script>onload=()=>print()</script></body></html>`,
    );
    w.document.close();
  }
  return (
    <section className="visitor-qr">
      <div className="vq-card">
        {qr ? <img src={qr} alt={'QR Code de visitantes de ' + unitName} width={220} height={220} /> : <span className="vq-wait">Gerando…</span>}
        <div>
          <p className="section-over">QR CODE DE VISITANTES</p>
          <h2>{unitName}</h2>
          <p>
            Coloque na entrada e nos telões. O visitante aponta a câmera, preenche nome, WhatsApp e algumas perguntas, e o cadastro entra em Pessoas como{' '}
            <b>Visitante</b> com acompanhamento pendente. A equipe também cadastra pelo Vinha Equipe.
          </p>
          <div className="vq-actions">
            <button type="button" className="create" disabled={!qr} onClick={print}>
              Imprimir cartaz
            </button>
            <a href={qr} download={'qrcode-visitantes.png'}>
              Baixar imagem
            </a>
            <button type="button" onClick={() => void navigator.clipboard?.writeText(link)}>
              Copiar link
            </button>
          </div>
        </div>
      </div>
      <h3>Cadastros dos últimos 7 dias</h3>
      {error && <p className="pd-empty">{error}</p>}
      {items && !items.length && <p className="pd-empty">Nenhum visitante cadastrado nos últimos 7 dias.</p>}
      {items?.map((v, i) => (
        <article key={v.person + i} className="vq-row">
          <div>
            <b>{v.name}</b>
            <small>
              {new Date(v.at).toLocaleString('pt-BR', {dateStyle: 'short', timeStyle: 'short'})} · {v.source === 'qr' ? 'QR Code' : 'Equipe'}
              {v.answers.firstTime ? ' · primeira vez' : ''}
              {v.answers.heard ? ' · ' + visitorHeardLabel(v.answers.heard) : ''}
            </small>
            {(v.answers.prayer || v.answers.note) && <small>{v.answers.prayer ? 'Oração: ' + v.answers.prayer : v.answers.note}</small>}
          </div>
          <span>
            {v.answers.visit ? 'Quer visita' : ''}
            {v.answers.contact ? (v.answers.visit ? ' · ' : '') + 'Aceita contato' : ''}
          </span>
        </article>
      ))}
    </section>
  );
}
