'use client';
import {useState} from 'react';
import type {ChurchRpc} from '../shared/member-church';
import {formatInZone} from '../shared/timezone';
import {songLines, useWorshipMusician} from '../shared/use-worship-musician';

const linkLabels: Record<string, string> = {video: 'Vídeo', audio: 'Áudio', chart: 'Cifra externa'};

/** Minhas escalas › Repertório: o músico escalado vê a cifra no tom do dia, usa o modo palco e confirma o ensaio. */
export default function MemberWorshipMusician({rpc, org}: {rpc: ChurchRpc; org: string}) {
  const m = useWorshipMusician(rpc, org, true);
  const [stage, setStage] = useState(false),
    [chords, setChords] = useState(true);
  if (m.setlist) {
    const s = m.setlist;
    return (
      <div className={'sv-music' + (stage ? ' stage' : '')}>
        <div className="sv-music-bar">
          <button type="button" className="secondary" onClick={() => { setStage(false); m.close(); }}>
            ← Voltar
          </button>
          <button type="button" aria-pressed={stage} onClick={() => setStage((v) => !v)}>
            {stage ? 'Sair do modo palco' : 'Modo palco'}
          </button>
          <button type="button" aria-pressed={!chords} onClick={() => setChords((v) => !v)}>
            {chords ? 'Só a letra' : 'Mostrar acordes'}
          </button>
        </div>
        <h3>{s.title}</h3>
        <p>
          {formatInZone(s.startsAt, s.timezone)} · chegada {formatInZone(s.arrivalAt, s.timezone, {timeStyle: 'short'})}
        </p>
        {s.notes && <p className="sv-music-note">{s.notes}</p>}
        {!stage && (
          <div className="sv-music-rehearsal">
            <span>
              {s.rehearsalConfirmed ? 'Você confirmou presença no ensaio.' : 'Confirme se vai ao ensaio.'} {s.rehearsalCount} confirmado(s).
            </span>
            <button type="button" disabled={m.busy} onClick={() => void m.confirm(!s.rehearsalConfirmed)}>
              {s.rehearsalConfirmed ? 'Desfazer confirmação' : 'Confirmar presença no ensaio'}
            </button>
          </div>
        )}
        {m.error && <p role="alert">{m.error}</p>}
        {s.items.map((song) => (
          <article key={song.position} className="sv-song">
            <header>
              <b>
                {song.position}. {song.title}
              </b>
              <span>
                Tom {song.dayKey || '—'}
                {song.dayKey && song.originalKey && song.dayKey !== song.originalKey ? ` (original ${song.originalKey})` : ''}
                {song.bpm ? ` · ${song.bpm} BPM` : ''}
                {song.timeSignature ? ` · ${song.timeSignature}` : ''}
              </span>
              {(song.minister || song.notes) && (
                <small>
                  {song.minister ? 'Ministra: ' + song.minister : ''}
                  {song.minister && song.notes ? ' · ' : ''}
                  {song.notes}
                </small>
              )}
            </header>
            <div className="sv-chart" aria-label={'Cifra de ' + song.title}>
              {songLines(song, chords).map((line, i) => (
                <p key={i}>
                  {line.map((part, j) => (
                    <span key={j} className={part.text.trim() ? undefined : 'gap'}>
                      {chords && <i aria-hidden="true">{part.chord || ' '}</i>}
                      {part.text.trim() ? part.text : '   '}
                    </span>
                  ))}
                </p>
              ))}
            </div>
            {!stage && Object.entries(song.links || {}).filter(([, url]) => /^https:\/\//.test(url)).length > 0 && (
              <div className="sv-actions">
                {Object.entries(song.links)
                  .filter(([, url]) => /^https:\/\//.test(url))
                  .map(([k, url]) => (
                    <a key={k} href={url} target="_blank" rel="noopener noreferrer">
                      {linkLabels[k] || 'Link'}
                    </a>
                  ))}
              </div>
            )}
          </article>
        ))}
      </div>
    );
  }
  return (
    <div className="sv-music">
      <p>Repertório publicado pela liderança de Louvor para os cultos em que você está escalado.</p>
      {m.loading && <p role="status">Consultando o repertório…</p>}
      {m.error && <p role="alert">{m.error}</p>}
      {m.items && !m.items.length && !m.loading && <p>Nenhum repertório publicado para as suas próximas escalas.</p>}
      {m.items?.map((x) => (
        <article key={x.service}>
          <h3>{x.title}</h3>
          <p>
            {formatInZone(x.startsAt, x.timezone)} · {x.roles.join(', ')} · {x.songs} música(s)
            {x.rehearsalConfirmed ? ' · ensaio confirmado' : ''}
          </p>
          <button type="button" disabled={m.busy} onClick={() => void m.open(x.service)}>
            Abrir repertório
          </button>
        </article>
      ))}
    </div>
  );
}
