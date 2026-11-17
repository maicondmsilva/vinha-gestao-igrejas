'use client';
import {useRef, useState, type FormEvent} from 'react';
import {lookupPostalAddress, type PostalAddress} from '../shared/brazil-registration';

const digits = (v: string) => v.replace(/\D/g, '');
const mask = (v: string) =>
  digits(v)
    .slice(0, 8)
    .replace(/^(\d{5})(\d)/, '$1-$2');

/**
 * Busca automática do endereço pelo CEP em formulários comuns (campos com name).
 * Ao digitar os 8 números do CEP, preenche rua, bairro, cidade e UF — sem apagar o que a pessoa já escreveu
 * enquanto a consulta acontecia. Número e complemento ficam com a pessoa.
 * Uso: const cep=useCepAutofill({zip:'address.postal_code',street:'address.street',...}); <form onInput={cep.onInput}>…{cep.notice}
 */
export function useCepAutofill(names: {zip: string; street: string; district: string; city: string; state: string}) {
  const [notice, setNotice] = useState('');
  const seq = useRef(0),
    timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined),
    ctrl = useRef<AbortController | null>(null);
  function onInput(event: FormEvent<HTMLFormElement>) {
    const field = event.target;
    if (!(field instanceof HTMLInputElement) || field.name !== names.zip) return;
    field.value = mask(field.value);
    const form = event.currentTarget,
      cep = digits(field.value),
      n = ++seq.current;
    clearTimeout(timer.current);
    ctrl.current?.abort();
    setNotice('');
    if (cep.length !== 8) return;
    const el = (name: string) => form.elements.namedItem(name) as HTMLInputElement | HTMLSelectElement | null;
    const keys = ['street', 'district', 'city', 'state'] as const;
    const before = Object.fromEntries(keys.map((k) => [k, el(names[k])?.value || '']));
    timer.current = setTimeout(() => {
      const c = new AbortController();
      ctrl.current = c;
      setNotice('Buscando endereço…');
      lookupPostalAddress(cep, c.signal)
        .then((a: PostalAddress) => {
          if (n !== seq.current || digits(el(names.zip)?.value || '') !== cep) return;
          for (const k of keys) {
            const input = el(names[k]);
            if (input && input.value === before[k] && a[k]) {
              input.value = a[k];
              input.dispatchEvent(new Event('input', {bubbles: true}));
            }
          }
          setNotice('Endereço encontrado. Confira e informe o número.');
        })
        .catch((e) => {
          if (n === seq.current && !(e instanceof DOMException)) setNotice(e instanceof Error ? e.message : 'Consulta indisponível. Preencha manualmente.');
        });
    }, 350);
  }
  return {onInput, notice};
}

/** Monta um endereço em uma linha (para campos de texto único, como o local da célula). */
export function addressLine(a: PostalAddress & {number?: string; cep?: string}) {
  const street = [a.street, a.number].filter(Boolean).join(', ');
  return [street, a.district, a.city && a.state ? a.city + '/' + a.state : a.city, a.cep ? 'CEP ' + mask(a.cep) : ''].filter(Boolean).join(' · ');
}
