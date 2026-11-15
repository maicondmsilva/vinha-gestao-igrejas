'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {visitorHeardLabel} from '../shared/visitors';

type Visit = {
  at: string;
  unit: string;
  source: 'qr' | 'staff';
  answers: {firstTime?: boolean; heard?: string; contact?: boolean; visit?: boolean; prayer?: string; note?: string};
};

/** Ficha da pessoa: visitas registradas pelo QR Code ou pela equipe (aparece só quando existe alguma). */
export default function PersonVisits({personId}: {personId: string}) {
  const [items, setItems] = useState<Visit[]>([]);
  useEffect(() => {
    let live = true;
    setItems([]);
    if (!personId) return;
    void fetch(settingsUrl('/api/people/visitors?' + new URLSearchParams({person: personId})), {cache: 'no-store'})
      .then((r) => (r.ok ? r.json() : {items: []}))
      .then((d: {items?: Visit[]}) => live && setItems(d.items || []))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [personId]);
  if (!items.length) return null;
  return (
    <section>
      <h3>Visitas</h3>
      {items.map((v, i) => (
        <p key={v.at + i} className="pp-visit">
          <b>{new Date(v.at).toLocaleDateString('pt-BR')}</b> · {v.unit} · {v.source === 'qr' ? 'QR Code' : 'cadastrado pela equipe'}
          {v.answers.firstTime ? ' · primeira vez' : ''}
          {v.answers.heard ? ' · ' + visitorHeardLabel(v.answers.heard) : ''}
          {v.answers.visit ? ' · quer receber visita' : ''}
          {v.answers.contact === false ? ' · não quer contato' : ''}
          {v.answers.prayer ? <small>Pedido de oração: {v.answers.prayer}</small> : null}
          {v.answers.note ? <small>{v.answers.note}</small> : null}
        </p>
      ))}
    </section>
  );
}
