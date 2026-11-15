import {useCallback, useEffect, useState} from 'react';
import {ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, TextInput, View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {kidsPage} from './kids';
import KidsChildPhoto from './KidsChildPhoto';
import {colors, ui} from './theme';
import type {Unit} from './api';
import type {KidsOperationsPage} from '../../shared/contract/kids.ts';
import {kidsCallAnswer, kidsCallReasons, type KidsCall, type KidsCallReason} from '../../shared/kids-calls.ts';

/** Sala Kids no Vinha Equipe: crianças presentes por sala e "Chamar responsável" (aviso no app da família). */
function Ghost({label, onPress}: {label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" style={ui.ghost} onPress={onPress}>
      <Text style={ui.ghostText}>{label}</Text>
    </Pressable>
  );
}

export default function KidsBoard({org, unit, back, embedded = false}: {org: string; unit: Unit; back: () => void; embedded?: boolean}) {
  const [page, setPage] = useState<KidsOperationsPage | null>(null),
    [calls, setCalls] = useState<KidsCall[]>([]),
    [tags, setTags] = useState<Record<string, number>>({}),
    [hasProjector, setHasProjector] = useState(false),
    [projector, setProjector] = useState(true),
    [room, setRoom] = useState(''),
    [child, setChild] = useState<{id: string; name: string} | null>(null),
    [reason, setReason] = useState<KidsCallReason>('pickup'),
    [message, setMessage] = useState(''),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [notice, setNotice] = useState(''),
    [error, setError] = useState('');
  const load = useCallback(async () => {
    try {
      const p = await kidsPage(org, unit.id);
      setPage(p);
      setError('');
      if (p.sessionId && supabase) {
        const r = await supabase.rpc('kids_call', {p_org: org, p_unit: unit.id, p_action: 'list', p_data: {session: p.sessionId}});
        if (!r.error) {
          const d = r.data as {items?: KidsCall[]; tags?: Record<string, number>; projector?: boolean};
          setCalls(d.items || []);
          setTags(d.tags || {});
          setHasProjector(!!d.projector);
        }
      }
    } catch (e) {
      setError((e as Error).message || 'Não foi possível carregar a sala.');
    } finally {
      setLoading(false);
    }
  }, [org, unit.id]);
  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), 15000);
    return () => clearInterval(t);
  }, [load]);
  async function send() {
    if (!child || !supabase || busy) return;
    setBusy(true);
    setNotice('');
    const r = await supabase.rpc('kids_call', {
      p_org: org,
      p_unit: unit.id,
      p_action: 'call',
      p_data: {id: randomUUID(), attendance: child.id, reason, message: message.trim(), projector: hasProjector && projector},
    });
    setBusy(false);
    if (r.error) {
      setNotice(
        /recent/.test(r.error.message)
          ? 'Esta família já foi chamada há pouco. Aguarde a resposta.'
          : /denied/.test(r.error.message)
            ? 'Você não está na equipe desta sala.'
            : 'Não foi possível chamar agora. Tente de novo.',
      );
      return;
    }
    setNotice('Responsável avisado no aplicativo: ' + child.name.split(' ')[0] + '.');
    setChild(null);
    setMessage('');
    void load();
  }
  const groups = page?.groups || [],
    kids = (page?.items || []).filter((k) => k.status === 'present' && (!room || k.groupId === room)),
    session = page?.sessions.find((s) => s.id === page.sessionId);
  return (
    <ScrollView
      contentContainerStyle={[ui.pad, {paddingTop: embedded ? 12 : 24}]}
      refreshControl={<RefreshControl refreshing={false} onRefresh={() => void load()} />}
    >
      {!embedded && <Text style={ui.over}>KIDS · {unit.name.toUpperCase()}</Text>}
      {!embedded && <Text style={ui.h1}>Sala das crianças</Text>}
      {loading ? (
        <ActivityIndicator color={colors.brand} />
      ) : error ? (
        <Text style={ui.error}>{error}</Text>
      ) : !page?.sessionId ? (
        <Text style={ui.copy}>Nenhum encontro Kids aberto agora nesta igreja.</Text>
      ) : (
        <>
          <Text style={ui.copy}>
            {session?.name || 'Encontro aberto'} · {page.items.filter((k) => k.status === 'present').length} criança(s) presente(s)
          </Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap: 8}}>
            {[{id: '', room: 'Todas as salas', occupied: page.items.length}, ...groups].map((g) => (
              <Pressable
                key={g.id || 'all'}
                accessibilityRole="button"
                accessibilityState={{selected: room === g.id}}
                onPress={() => setRoom(g.id)}
                style={[ui.chip, room === g.id && {backgroundColor: colors.brand, borderColor: colors.brand}]}
              >
                <Text style={{color: room === g.id ? '#fff' : colors.text, fontWeight: '700'}}>
                  {g.room}
                  {g.id ? ' · ' + g.occupied : ''}
                </Text>
              </Pressable>
            ))}
          </ScrollView>
          {!!notice && (
            <Text accessibilityRole="alert" style={[ui.copy, {color: colors.text, fontWeight: '700'}]}>
              {notice}
            </Text>
          )}
          {child && (
            <View style={[ui.card, {borderColor: colors.gold, borderWidth: 2}]}>
              <Text style={ui.h2}>Chamar o responsável de {child.name.split(' ')[0]}</Text>
              <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
                {kidsCallReasons.map(([k, label]) => (
                  <Pressable
                    key={k}
                    accessibilityRole="radio"
                    accessibilityState={{checked: reason === k}}
                    onPress={() => setReason(k)}
                    style={[ui.chip, reason === k && {backgroundColor: colors.gold, borderColor: colors.gold}]}
                  >
                    <Text style={{color: colors.text, fontWeight: '700'}}>{label}</Text>
                  </Pressable>
                ))}
              </View>
              <TextInput
                accessibilityLabel="Recado curto (opcional)"
                placeholder="Recado curto (opcional)"
                placeholderTextColor={colors.muted}
                maxLength={200}
                value={message}
                onChangeText={setMessage}
                style={ui.input}
              />
              {hasProjector && (
                <Pressable
                  accessibilityRole="checkbox"
                  accessibilityState={{checked: projector}}
                  onPress={() => setProjector(!projector)}
                  style={{flexDirection: 'row', alignItems: 'center', gap: 10}}
                >
                  <View
                    style={{
                      width: 22,
                      height: 22,
                      borderRadius: 6,
                      borderWidth: 2,
                      borderColor: colors.brand,
                      backgroundColor: projector ? colors.brand : 'transparent',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    {projector && <Text style={{color: '#fff', fontWeight: '900', fontSize: 12}}>✓</Text>}
                  </View>
                  <Text style={[ui.copy, {color: colors.text, flex: 1}]}>Mostrar no telão: “responsável pela criança nº {tags[child.id] || '?'}”</Text>
                </Pressable>
              )}
              <Pressable accessibilityRole="button" disabled={busy} style={[ui.primary, busy && {opacity: 0.6}]} onPress={() => void send()}>
                {busy ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={ui.primaryText}>{hasProjector && projector ? 'Avisar no app e no telão' : 'Avisar no aplicativo'}</Text>
                )}
              </Pressable>
              <Ghost label="Cancelar" onPress={() => setChild(null)} />
            </View>
          )}
          {!kids.length && <Text style={ui.copy}>Nenhuma criança presente {room ? 'nesta sala' : 'agora'}.</Text>}
          {kids.map((k) => {
            const last = calls.find((c) => c.attendance === k.id),
              g = groups.find((x) => x.id === k.groupId);
            return (
              <View key={k.id} style={[ui.card, {flexDirection: 'row', alignItems: 'center', gap: 12}]}>
                <KidsChildPhoto org={org} unit={unit.id} profile={k.profileId} name={k.name} />
                <View style={{flex: 1}}>
                  <Text style={ui.h2}>
                    {tags[k.id] || k.tag ? 'nº ' + (tags[k.id] || k.tag) + ' · ' : ''}
                    {k.name}
                  </Text>
                  <Text style={ui.copy}>
                    {g?.room || 'Sala'} · desde {new Date(k.inAt).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'})}
                  </Text>
                  {last && <Text style={[ui.copy, {color: last.answer ? colors.ok : colors.warn, fontWeight: '700'}]}>{kidsCallAnswer(last)}</Text>}
                </View>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={'Chamar responsável de ' + k.name}
                  onPress={() => {
                    setNotice('');
                    setChild({id: k.id, name: k.name});
                  }}
                  style={[ui.chip, {borderColor: colors.brand}]}
                >
                  <Text style={{color: colors.brand, fontWeight: '800'}}>Chamar</Text>
                </Pressable>
              </View>
            );
          })}
        </>
      )}
      {!embedded && <Ghost label="Voltar" onPress={back} />}
    </ScrollView>
  );
}
