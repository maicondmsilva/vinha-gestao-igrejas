import {useEffect, useState} from 'react';
import {Image, Text, View} from 'react-native';
import {api} from './api';
import {colors} from './theme';

/** Foto da criança para a equipe reconhecer (link temporário gerado pela plataforma); sem foto, as iniciais. */
export default function KidsChildPhoto({org, unit, profile, name, size = 48}: {org: string; unit: string; profile: string; name: string; size?: number}) {
  const [url, setUrl] = useState('');
  useEffect(() => {
    let live = true;
    setUrl('');
    api<{url?: string}>('/api/kids/photo?' + new URLSearchParams({unit, profile}), org)
      .then((d) => live && setUrl(d.url || ''))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [org, unit, profile]);
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
  return url ? (
    <Image accessibilityLabel={'Foto de ' + name} source={{uri: url}} style={{width: size, height: size, borderRadius: size / 2}} />
  ) : (
    <View style={{width: size, height: size, borderRadius: size / 2, backgroundColor: '#e3efe6', alignItems: 'center', justifyContent: 'center'}}>
      <Text style={{color: colors.brand, fontWeight: '900', fontSize: size * 0.36}}>{initials}</Text>
    </View>
  );
}
