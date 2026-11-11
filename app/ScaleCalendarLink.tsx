'use client';

import {useEffect, useState} from 'react';
import type {ChurchRpc} from '../shared/member-church';

type LinkState = {active: boolean; token?: string};

export default function ScaleCalendarLink({rpc, org}: {rpc: ChurchRpc; org: string}) {
  const [opened, setOpened] = useState(false);
  return (
    <details onToggle={(e) => setOpened(e.currentTarget.open)}>
      <summary>Calendário pessoal</summary>
      {opened && <CalendarControls key={org} rpc={rpc} org={org} />}
    </details>
  );
}

function CalendarControls({rpc, org}: {rpc: ChurchRpc; org: string}) {
  const [state, setState] = useState<LinkState | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  useEffect(() => {
    let current = true;
    void Promise.resolve(rpc.rpc('scale_calendar_manage', {p_org: org, p_action: 'status'}))
      .then((result) => {
        if (!current) return;
        if (result.error) setError('O calendário pessoal está indisponível para este cadastro.');
        else setState(result.data as LinkState);
      })
      .catch(() => {
        if (current) setError('Não foi possível consultar o calendário. Abra esta seção novamente.');
      });
    return () => {
      current = false;
    };
  }, [org, rpc]);

  async function change(action: 'rotate' | 'revoke') {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const result = await rpc.rpc('scale_calendar_manage', {p_org: org, p_action: action});
      if (result.error) throw new Error();
      setState(result.data as LinkState);
      setNotice(action === 'rotate' ? 'Novo link gerado.' : 'Link revogado.');
    } catch {
      setError('Não foi possível confirmar a alteração. Confira a situação antes de tentar novamente.');
    } finally {
      setBusy(false);
    }
  }
  const url = state?.token && typeof location !== 'undefined' ? new URL('/api/scales-calendar?t=' + state.token, location.origin).href : '';
  return (
    <div>
      <p>
        Assine em seu calendário os serviços confirmados dos próximos 180 dias, até 250 serviços. O calendário consulta a Vinha e cada aplicativo decide quando
        atualizar.
      </p>
      <p>Quem tiver o link pode ver os títulos e horários. Guarde-o em local privado. Gerar um novo link invalida o anterior.</p>
      {error && <p role="alert">{error}</p>}
      {notice && <p role="status">{notice}</p>}
      {state ? (
        <>
          <p>{state.active ? 'Assinatura ativa.' : 'Nenhuma assinatura ativa.'}</p>
          <button type="button" disabled={busy} onClick={() => void change('rotate')}>
            {state.active ? 'Gerar novo link' : 'Gerar link privado'}
          </button>
          {state.active && (
            <button type="button" disabled={busy} onClick={() => void change('revoke')}>
              Revogar link
            </button>
          )}
          {url && (
            <label>
              Link de assinatura · copie agora
              <input readOnly value={url} onFocus={(e) => e.currentTarget.select()} />
            </label>
          )}
        </>
      ) : (
        !error && <p role="status">Consultando assinatura…</p>
      )}
    </div>
  );
}
