'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';

type Group = {id: string; name: string; color: string; count: number};

/** Ficha do usuário: grupos da igreja (Configurações › Grupos) em que a pessoa está. Marcar salva na hora. */
export default function PersonGroups({personId, disabled}: {personId: string; disabled?: boolean}) {
  const [groups, setGroups] = useState<Group[] | null>(null),
    [mine, setMine] = useState<string[]>([]),
    [busy, setBusy] = useState(false),
    [note, setNote] = useState('');
  useEffect(() => {
    let live = true;
    void fetch(settingsUrl('/api/people-groups?' + new URLSearchParams({person: personId})), {cache: 'no-store'})
      .then((r) => (r.ok ? r.json() : {items: [], mine: []}))
      .then((x) => {
        const d = x as {items?: Group[]; mine?: string[]};
        if (!live) return;
        setGroups(d.items || []);
        setMine(d.mine || []);
      })
      .catch(() => live && setGroups([]));
    return () => {
      live = false;
    };
  }, [personId]);
  async function toggle(id: string) {
    const next = mine.includes(id) ? mine.filter((x) => x !== id) : [...mine, id];
    setBusy(true);
    setNote('');
    const r = await fetch(settingsUrl('/api/people-groups'), {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: 'set_person', data: {person: personId, groups: next}}),
    }).catch(() => null);
    setBusy(false);
    if (r?.ok) {
      setMine(next);
      setNote('Grupos atualizados.');
    } else setNote('Não foi possível atualizar os grupos.');
  }
  if (!groups) return null;
  if (!groups.length) return <p className="us-help">Nenhum grupo criado. Crie em Configurações › Grupos (ex.: Pastores, Lideranças).</p>;
  return (
    <div className="us-person-groups">
      {groups.map((g) => (
        <label key={g.id} className={mine.includes(g.id) ? 'on' : ''} style={{borderColor: mine.includes(g.id) ? g.color : undefined}}>
          <input type="checkbox" checked={mine.includes(g.id)} disabled={disabled || busy} onChange={() => void toggle(g.id)} />
          <i style={{background: g.color}} aria-hidden />
          {g.name}
        </label>
      ))}
      {note && <small role="status">{note}</small>}
    </div>
  );
}
