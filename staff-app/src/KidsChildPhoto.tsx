import {useEffect, useState} from 'react';
import {Image, Text, View} from 'react-native';
import {api} from './api';
import {colors} from './theme';
import {kidsPhotoBatcher} from '../../shared/kids-photo-batch.ts';

// Cartões pedidos ao mesmo tempo viram uma chamada só; o link fica guardado por alguns minutos.
const loaders = new Map<string, (unit: string, profile: string) => Promise<string>>();
function photoFor(org: string) {
  let l = loaders.get(org);
  if (!l) {
    l = kidsPhotoBatcher((unit, profiles) =>
      api<{urls?: Record<string, string>}>('/api/kids/photo?' + new URLSearchParams({unit, profiles: profiles.join(',')}), org).then((d) => d.urls || {}),
    );
    loaders.set(org, l);
  }
  return l;
}

/** Foto da criança para a equipe reconhecer (link temporário gerado pela plataforma); sem foto, as iniciais. */
export default function KidsChildPhoto({org, unit, profile, name, size = 48}: {org: string; unit: string; profile: string; name: string; size?: number}) {
  const [url, setUrl] = useState('');
  useEffect(() => {
    let live = true;
    setUrl('');
    void photoFor(org)(unit, profile).then((u) => live && setUrl(u));
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
