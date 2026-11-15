'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';

/** Foto do cadastro (enviada pelo app do membro) ou, sem foto, as iniciais. */
export default function PersonPhoto({id, initials, name}: {id?: string; initials: string; name: string}) {
  const [url, setUrl] = useState('');
  useEffect(() => {
    let live = true;
    setUrl('');
    if (!id) return;
    void fetch(settingsUrl('/api/people/photo?' + new URLSearchParams({id})), {cache: 'no-store'})
      .then((r) => (r.ok ? r.json() : {url: ''}))
      .then((d: {url?: string}) => live && setUrl(d.url || ''))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [id]);
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img className="person-photo" src={url} alt={'Foto de ' + name} width={72} height={72} />
  ) : (
    <i>{initials}</i>
  );
}
