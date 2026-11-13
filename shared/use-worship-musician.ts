// Louvor · visão do músico (app web e Android): próximos cultos com repertório publicado, cifra no tom do dia e ensaio.
import {useCallback, useEffect, useState} from 'react';
import type {ChurchRpc} from './member-church';
import {chartLine, transposeChart} from './worship-chart.ts';

export type MusicianService = {
  service: string;
  title: string;
  startsAt: string;
  arrivalAt: string;
  timezone: string;
  songs: number;
  roles: string[];
  rehearsalConfirmed: boolean;
};
export type MusicianSong = {
  position: number;
  title: string;
  artist: string;
  originalKey: string;
  dayKey: string;
  bpm: number | null;
  timeSignature: string;
  chart: string;
  links: Record<string, string>;
  minister: string | null;
  notes: string;
};
export type MusicianSetlist = {
  service: string;
  title: string;
  startsAt: string;
  arrivalAt: string;
  timezone: string;
  notes: string;
  rehearsalConfirmed: boolean;
  rehearsalCount: number;
  items: MusicianSong[];
};

export function musicianError(code?: string) {
  if (code === '42501') return 'Este repertório é só para quem está escalado no culto e ainda não recusou o convite.';
  return 'Não foi possível abrir o repertório agora. Tente de novo em instantes.';
}

/** Linhas da cifra no tom do dia. Sem acordes (modo só letra), devolve só o texto. */
export function songLines(song: Pick<MusicianSong, 'chart' | 'originalKey' | 'dayKey'>, withChords: boolean) {
  const chart = transposeChart(song.chart || '', song.originalKey || '', song.dayKey || '');
  return chart.split('\n').map((line) => {
    const parts = chartLine(line);
    return withChords ? parts : [{chord: '', text: parts.map((p) => p.text).join('')}];
  });
}

export function useWorshipMusician(rpc: ChurchRpc, org: string, active: boolean) {
  const [items, setItems] = useState<MusicianService[] | null>(null),
    [setlist, setSetlist] = useState<MusicianSetlist | null>(null),
    [loading, setLoading] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [revision, setRevision] = useState(0);
  useEffect(() => {
    if (!active) return;
    let alive = true;
    Promise.resolve()
      .then(() => {
        setLoading(true);
        return rpc.rpc('worship_musician', {p_org: org, p_action: 'list', p_data: {}});
      })
      .then((r) => {
        if (!alive) return;
        if (r.error) {
          setError(musicianError(r.error.code));
          setItems([]);
        } else {
          setError('');
          setItems(((r.data as {items?: MusicianService[]}) || {}).items || []);
        }
      })
      .catch(() => alive && setError(musicianError()))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [rpc, org, active, revision]);
  const open = useCallback(
    async (service: string) => {
      setBusy(true);
      try {
        const r = await rpc.rpc('worship_musician', {p_org: org, p_action: 'view', p_data: {service}});
        if (r.error) setError(musicianError(r.error.code));
        else {
          setError('');
          setSetlist(r.data as MusicianSetlist);
        }
      } catch {
        setError(musicianError());
      } finally {
        setBusy(false);
      }
    },
    [rpc, org],
  );
  const confirm = useCallback(
    async (confirmed: boolean) => {
      if (!setlist) return;
      setBusy(true);
      try {
        const r = await rpc.rpc('worship_musician', {p_org: org, p_action: 'rehearsal', p_data: {service: setlist.service, confirmed}});
        if (r.error) setError(musicianError(r.error.code));
        else {
          setError('');
          await open(setlist.service);
          setRevision((n) => n + 1);
        }
      } catch {
        setError(musicianError());
      } finally {
        setBusy(false);
      }
    },
    [rpc, org, open, setlist],
  );
  return {items, setlist, loading, busy, error, open, close: () => setSetlist(null), confirm, refresh: () => setRevision((n) => n + 1)};
}
