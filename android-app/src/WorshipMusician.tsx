import {useState} from 'react';
import {ActivityIndicator, Linking, Pressable, StyleSheet, Text, View} from 'react-native';
import type {ChurchRpc} from '../../shared/member-church';
import {formatInZone} from '../../shared/timezone';
import {songLines, useWorshipMusician} from '../../shared/use-worship-musician';
import {onBrand} from './experience-model';
type Palette = {surface: string; text: string; muted: string; line: string; brand: string};
const linkLabels: Record<string, string> = {video: 'Vídeo', audio: 'Áudio', chart: 'Cifra externa'};

/** Minhas escalas › Repertório (Android): cifra no tom do dia, modo palco e confirmação de ensaio. */
export default function WorshipMusician({rpc, org, palette}: {rpc: ChurchRpc; org: string; palette: Palette}) {
  const m = useWorshipMusician(rpc, org, true);
  const [stage, setStage] = useState(false),
    [chords, setChords] = useState(true);
  const fg = stage ? '#f4f8f4' : palette.text,
    muted = stage ? '#d6e3da' : palette.muted;
  const text = (v: string, heading = false) => (
    <Text style={{color: heading ? fg : muted, fontSize: heading ? 18 : 15, fontWeight: heading ? '700' : '400', lineHeight: 23, marginVertical: 4}}>{v}</Text>
  );
  const button = (label: string, action: () => void, selected = false) => (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{disabled: m.busy, selected}}
      disabled={m.busy}
      onPress={action}
      style={[s.button, {backgroundColor: selected ? palette.brand : palette.surface, borderColor: palette.brand, opacity: m.busy ? 0.45 : 1}]}
    >
      <Text style={{color: selected ? onBrand(palette.brand) : palette.text, fontWeight: '600', textAlign: 'center'}}>{label}</Text>
    </Pressable>
  );
  if (m.setlist) {
    const set = m.setlist;
    return (
      <View style={stage ? [s.stage] : undefined}>
        <View style={s.row}>
          {button('← Voltar', () => {
            setStage(false);
            m.close();
          })}
          {button(stage ? 'Sair do modo palco' : 'Modo palco', () => setStage((v) => !v), stage)}
          {button(chords ? 'Só a letra' : 'Mostrar acordes', () => setChords((v) => !v), !chords)}
        </View>
        {text(set.title, true)}
        {text(formatInZone(set.startsAt, set.timezone) + ' · chegada ' + formatInZone(set.arrivalAt, set.timezone, {timeStyle: 'short'}))}
        {!!set.notes && text(set.notes)}
        {!stage && (
          <View style={[s.card, {borderColor: palette.line, backgroundColor: palette.surface}]}>
            {text((set.rehearsalConfirmed ? 'Você confirmou presença no ensaio.' : 'Confirme se vai ao ensaio.') + ' ' + set.rehearsalCount + ' confirmado(s).')}
            {button(set.rehearsalConfirmed ? 'Desfazer confirmação' : 'Confirmar presença no ensaio', () => void m.confirm(!set.rehearsalConfirmed), !set.rehearsalConfirmed)}
          </View>
        )}
        {!!m.error && (
          <Text accessibilityRole="alert" style={{color: fg}}>
            {m.error}
          </Text>
        )}
        {set.items.map((song) => (
          <View key={song.position} style={{marginVertical: 14}}>
            {text(song.position + '. ' + song.title, true)}
            {text(
              'Tom ' +
                (song.dayKey || '—') +
                (song.dayKey && song.originalKey && song.dayKey !== song.originalKey ? ' (original ' + song.originalKey + ')' : '') +
                (song.bpm ? ' · ' + song.bpm + ' BPM' : '') +
                (song.minister ? ' · Ministra: ' + song.minister : ''),
            )}
            {!!song.notes && text(song.notes)}
            {songLines(song, chords).map((line, i) => (
              <View key={i} style={s.line}>
                {line.map((part, j) => (
                  <View key={j} style={part.text.trim() ? undefined : {minWidth: stage ? 44 : 32}}>
                    {chords && <Text style={{color: stage ? '#f2c46b' : '#b4572a', fontWeight: '700', fontSize: stage ? 18 : 14}}>{part.chord || ' '}</Text>}
                    <Text style={{color: fg, fontSize: stage ? 24 : 16}}>{part.text.trim() ? part.text : '   '}</Text>
                  </View>
                ))}
              </View>
            ))}
            {!stage && (
              <View style={s.row}>
                {Object.entries(song.links || {})
                  .filter(([, url]) => /^https:\/\//.test(url))
                  .map(([k, url]) => (
                    <View key={k}>{button(linkLabels[k] || 'Link', () => void Linking.openURL(url))}</View>
                  ))}
              </View>
            )}
          </View>
        ))}
      </View>
    );
  }
  return (
    <View>
      {text('Repertório publicado pela liderança de Louvor para os cultos em que você está escalado.')}
      {m.loading && <ActivityIndicator color={palette.brand} />}
      {!!m.error && (
        <Text accessibilityRole="alert" style={{color: palette.text}}>
          {m.error}
        </Text>
      )}
      {m.items && !m.items.length && !m.loading && text('Nenhum repertório publicado para as suas próximas escalas.')}
      {m.items?.map((x) => (
        <View key={x.service} style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
          {text(x.title, true)}
          {text(formatInZone(x.startsAt, x.timezone) + ' · ' + x.roles.join(', ') + ' · ' + x.songs + ' música(s)' + (x.rehearsalConfirmed ? ' · ensaio confirmado' : ''))}
          {button('Abrir repertório', () => void m.open(x.service), true)}
        </View>
      ))}
    </View>
  );
}
const s = StyleSheet.create({
  row: {flexDirection: 'row', flexWrap: 'wrap', gap: 8},
  button: {minHeight: 46, borderWidth: 1, borderRadius: 10, padding: 12, justifyContent: 'center', marginVertical: 5},
  card: {borderWidth: 1, borderRadius: 16, padding: 18, marginVertical: 12},
  line: {flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-end', marginBottom: 6},
  stage: {backgroundColor: '#10261d', borderRadius: 12, padding: 16},
});
