'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {kidsPhotoBatcher} from '../shared/kids-photo-batch';

const photo = kidsPhotoBatcher((unit, profiles) =>
  fetch(settingsUrl('/api/kids/photo?' + new URLSearchParams({unit, profiles: profiles.join(',')})), {cache: 'no-store'})
    .then((r) => (r.ok ? r.json() : {urls: {}}))
    .then((d) => (d as {urls?: Record<string, string>}).urls || {}),
);

/** Foto da criança (Kids) para reconhecer na recepção e nas salas; sem foto, as iniciais. */
export default function KidsChildPhoto({unit, profile, name, size = 44}: {unit: string; profile: string; name: string; size?: number}) {
  const [url, setUrl] = useState('');
  useEffect(() => {
    let live = true;
    setUrl('');
    void photo(unit, profile).then((u) => live && setUrl(u));
    return () => {
      live = false;
    };
  }, [unit, profile]);
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={url}
      alt={'Foto de ' + name}
      width={size}
      height={size}
      style={{width: size, height: size, borderRadius: '50%', objectFit: 'cover', flex: 'none'}}
    />
  ) : (
    <span
      aria-hidden
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: '#e3efe6',
        color: '#285c45',
        display: 'inline-grid',
        placeItems: 'center',
        fontWeight: 700,
        flex: 'none',
      }}
    >
      {initials}
    </span>
  );
}
