import {useEffect, useRef, useState} from 'react';
import type {ChurchRpc} from './member-church';
import {scaleOperationError} from './scale-operations';
export type VolunteerInvite = {
  id: string;
  version: number;
  response: string;
  active: boolean;
  ended_reason: string;
  presence: string;
  deadline: string;
  title: string;
  starts_at: string;
  ends_at: string;
  arrival_at: string;
  status: string;
  role: string;
  team: string;
  location: string;
  notes: string;
  canReply: boolean;
  recordedByLeader: boolean;
  replacement: {id: string; version: number; state: string} | null;
};
export type Availability = {
  id: string;
  version: number;
  kind: 'weekly' | 'unavailable';
  weekday: number;
  start_minute: number;
  end_minute: number;
  starts_at: string;
  ends_at: string;
  reason: string;
  active: boolean;
};
export type VolunteerPage = {unit: string; unitName: string; timezone: string; items: VolunteerInvite[]; total: number};
export function useVolunteerScales(rpc: ChurchRpc, org: string, authenticated = true, nonce: () => string = () => globalThis.crypto.randomUUID()) {
  const [page, setPage] = useState<VolunteerPage | null>(null),
    [availability, setAvailability] = useState<{timezone: string; items: Availability[]; total: number} | null>(null),
    [number, setNumber] = useState(1),
    [availabilityPage, setAvailabilityPage] = useState(1),
    [revision, setRevision] = useState(0),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const client = useRef(rpc),
    epoch = useRef(0),
    mutation = useRef(false),
    retry = useRef({key: '', request: ''});
  client.current = rpc;
  useEffect(() => {
    let alive = true;
    const e = ++epoch.current;
    setPage(null);
    setAvailability(null);
    setError('');
    if (!authenticated) {
      setLoading(false);
      return;
    }
    setLoading(true);
    void Promise.all(
      ['list', 'availability'].map((action, i) =>
        Promise.resolve(client.current.rpc('scale_volunteer', {p_org: org, p_action: action, p_data: {page: i ? availabilityPage : number}})),
      ),
    )
      .then(([a, b]) => {
        if (!alive || e !== epoch.current) return;
        if (a.error || b.error) {
          setError(scaleOperationError((a.error || b.error)!.message, (a.error || b.error)!.code));
          return;
        }
        setPage(a.data as VolunteerPage);
        setAvailability(b.data as typeof availability);
      })
      .catch(() => {
        if (alive) setError('Não foi possível carregar suas escalas. Tente atualizar.');
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
      epoch.current++;
    };
  }, [org, authenticated, number, availabilityPage, revision]);
  async function command(action: string, data: Record<string, unknown>) {
    if (mutation.current || !authenticated) return false;
    mutation.current = true;
    setBusy(true);
    setNotice('');
    const e = epoch.current,
      key = JSON.stringify([org, action, data]);
    if (retry.current.key !== key) retry.current = {key, request: nonce()};
    try {
      const r = await client.current.rpc('scale_volunteer', {p_org: org, p_action: action, p_data: {...data, request: retry.current.request}});
      if (e !== epoch.current) return false;
      if (r.error) throw Error(scaleOperationError(r.error.message, r.error.code));
      if (!(r.data as {ok?: boolean})?.ok) throw Error('Resultado não confirmado. Atualize a consulta.');
      retry.current = {key: '', request: ''};
      setRevision((n) => n + 1);
      setNotice(
        action === 'reply'
          ? 'Resposta registrada. A presença será conferida pela liderança.'
          : action === 'available.save'
            ? 'Disponibilidade atualizada. Os conflitos serão recalculados nas escalas.'
            : action === 'replacement.request'
              ? 'Pedido enviado ao responsável. Sua atribuição continua válida até a decisão.'
              : 'Solicitação cancelada.',
      );
      return true;
    } catch (e) {
      setNotice(e instanceof Error ? e.message : 'Não foi possível confirmar.');
      return false;
    } finally {
      mutation.current = false;
      setBusy(false);
    }
  }
  async function suggestions(id: string, search: string) {
    const r = await client.current.rpc('scale_volunteer', {p_org: org, p_action: 'suggest', p_data: {id, search}});
    if (r.error) throw Error(scaleOperationError(r.error.message, r.error.code));
    return (r.data as {items: {id: string; name: string}[]}).items;
  }
  return {
    page,
    availability,
    number,
    setNumber,
    availabilityPage,
    setAvailabilityPage,
    busy,
    loading,
    error,
    notice,
    command,
    suggestions,
    refresh: () => setRevision((n) => n + 1),
  };
}
