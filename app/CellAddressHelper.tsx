'use client';
import {useEffect, useState} from 'react';
import {lookupPostalAddress, type PostalAddress} from '../shared/brazil-registration';
import {addressLine} from './useCepAutofill';

/** Células: CEP + número montam o endereço do local em uma linha (o local continua editável). */
export default function CellAddressHelper({disabled, apply}: {disabled?: boolean; apply: (line: string) => void}) {
  const [cep, setCep] = useState(''),
    [number, setNumber] = useState(''),
    [found, setFound] = useState<PostalAddress | null>(null),
    [notice, setNotice] = useState('');
  const raw = cep.replace(/\D/g, '');
  useEffect(() => {
    setFound(null);
    if (raw.length !== 8) {
      setNotice('');
      return;
    }
    const c = new AbortController();
    const t = setTimeout(() => {
      setNotice('Buscando endereço…');
      lookupPostalAddress(raw, c.signal)
        .then((a) => {
          setFound(a);
          setNotice('');
        })
        .catch((e) => !c.signal.aborted && setNotice(e instanceof Error ? e.message : 'Consulta indisponível.'));
    }, 350);
    return () => {
      clearTimeout(t);
      c.abort();
    };
  }, [raw]);
  useEffect(() => {
    if (found) apply(addressLine({...found, number: number.trim(), cep: raw}));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [found, number]);
  return (
    <div className="cell-form-row cell-cep">
      <label>
        CEP do local
        <input
          inputMode="numeric"
          maxLength={9}
          placeholder="00000-000"
          disabled={disabled}
          value={cep}
          onChange={(e) =>
            setCep(
              e.target.value
                .replace(/\D/g, '')
                .slice(0, 8)
                .replace(/^(\d{5})(\d)/, '$1-$2'),
            )
          }
        />
      </label>
      <label>
        Número
        <input
          maxLength={20}
          disabled={disabled || !found}
          value={number}
          onChange={(e) => setNumber(e.target.value)}
          placeholder={found ? 'Ex.: 120' : 'Depois do CEP'}
        />
      </label>
      {notice && (
        <small role="status" className="cell-cep-notice">
          {notice}
        </small>
      )}
    </div>
  );
}
