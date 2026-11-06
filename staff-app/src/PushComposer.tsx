import {useEffect, useState} from 'react';
import {ActivityIndicator, Pressable, ScrollView, Text, TextInput, View} from 'react-native';
import * as Crypto from 'expo-crypto';
import {api, type Unit} from './api';
import {colors, ui} from './theme';

type Options = {units: Unit[]; cells: {id: string; name: string; unit: string}[]; groups: {id: string; name: string; unit: string}[]};
type Reach = {devices: number; people: number};

/** Push from the phone: destinations are only the churches the server says this person may publish to. */
export default function PushComposer({org, unit, back}: {org: string; unit: Unit; units: Unit[]; back: () => void}) {
  const [options, setOptions] = useState<Options | null>(null),
    [title, setTitle] = useState(''),
    [body, setBody] = useState(''),
    [targets, setTargets] = useState<string[]>([unit.id]),
    [cells, setCells] = useState<string[]>([]),
    [groups, setGroups] = useState<string[]>([]),
    [reach, setReach] = useState<Reach | null>(null),
    [busy, setBusy] = useState(false),
    [done, setDone] = useState(''),
    [error, setError] = useState(''),
    [request, setRequest] = useState(() => Crypto.randomUUID());
  useEffect(() => {
    api<Options>('/api/push/campaigns?' + new URLSearchParams({unit: unit.id, options: '1'}), org)
      .then((o) => {
        setOptions(o);
        setTargets((t) => t.filter((id) => o.units.some((u) => u.id === id)));
      })
      .catch((e) => setError((e as Error).message));
  }, [org, unit.id]);
  const audience = {...(cells.length ? {cells} : {}), ...(groups.length ? {groups} : {})};
  useEffect(() => {
    if (!options || !targets.length) return setReach(null);
    const timer = setTimeout(() => {
      api<Reach>('/api/push/campaigns', org, {method: 'POST', body: {unit: unit.id, action: 'preview', data: {targets, audience}}})
        .then(setReach)
        .catch(() => setReach(null));
    }, 400);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options, targets.join(), cells.join(), groups.join()]);
  async function send() {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await api('/api/push/campaigns', org, {
        method: 'POST',
        body: {unit: unit.id, action: 'create', data: {title: title.trim(), body: body.trim(), targets, audience, link: {screen: 'inbox'}, mode: 'now', recurrence: 'none', request}},
      });
      setDone(`Enviado para ${reach?.people ?? 'as'} pessoas. Os avisos chegam em até um minuto.`);
      setTitle('');
      setBody('');
      setRequest(Crypto.randomUUID());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const toggle = (list: string[], set: (v: string[]) => void, id: string) => set(list.includes(id) ? list.filter((x) => x !== id) : [...list, id]);
  const valid = title.trim().length >= 2 && body.trim().length >= 2 && targets.length > 0;
  return (
    <ScrollView contentContainerStyle={ui.pad} keyboardShouldPersistTaps="handled">
      <Pressable accessibilityRole="button" onPress={back}>
        <Text style={{color: colors.brand, fontWeight: '600'}}>← Voltar</Text>
      </Pressable>
      <Text style={ui.over}>ENVIAR PUSH</Text>
      <Text style={ui.h1}>Novo aviso</Text>
      {!options ? (
        error ? <Text style={ui.error}>{error}</Text> : <ActivityIndicator color={colors.brand} />
      ) : (
        <>
          <Text style={ui.label}>Título ({title.length}/65)</Text>
          <TextInput style={ui.input} maxLength={65} value={title} onChangeText={setTitle} placeholder="Culto de domingo" />
          <Text style={ui.label}>Mensagem ({body.length}/240)</Text>
          <TextInput style={[ui.input, {minHeight: 90, paddingTop: 12, textAlignVertical: 'top'}]} multiline maxLength={240} value={body} onChangeText={setBody} placeholder="Hoje às 19h. Traga sua família!" />
          <View style={[ui.card, {backgroundColor: '#eef3ef'}]}>
            <Text style={{fontWeight: '700', color: colors.text}}>{title || 'Título da notificação'}</Text>
            <Text style={ui.copy}>{body || 'Assim o aviso aparece na tela do celular.'}</Text>
          </View>
          <Text style={ui.label}>Igrejas que recebem</Text>
          <Chips items={options.units} selected={targets} toggle={(id) => toggle(targets, setTargets, id)} />
          {!!options.cells.filter((c) => targets.includes(c.unit)).length && (
            <>
              <Text style={ui.label}>Somente estas células (opcional)</Text>
              <Chips items={options.cells.filter((c) => targets.includes(c.unit))} selected={cells} toggle={(id) => toggle(cells, setCells, id)} />
            </>
          )}
          {!!options.groups.filter((g) => targets.includes(g.unit)).length && (
            <>
              <Text style={ui.label}>Somente estes ministérios (opcional)</Text>
              <Chips items={options.groups.filter((g) => targets.includes(g.unit))} selected={groups} toggle={(id) => toggle(groups, setGroups, id)} />
            </>
          )}
          <Text style={ui.copy} accessibilityLiveRegion="polite">
            {!targets.length ? 'Escolha ao menos uma igreja.' : reach ? `Alcance agora: ${reach.people} pessoas em ${reach.devices} aparelhos.` : 'Calculando alcance…'}
          </Text>
          {!!error && <Text style={ui.error}>{error}</Text>}
          {!!done && <Text style={{color: colors.ok, fontWeight: '600'}}>{done}</Text>}
          <Pressable accessibilityRole="button" style={[ui.primary, (!valid || busy) && {opacity: 0.5}]} disabled={!valid || busy} onPress={() => void send()}>
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Enviar agora</Text>}
          </Pressable>
          <Text style={[ui.copy, {fontSize: 13}]}>Agendamento, repetição e filtros por idade ficam no painel da Vinha, em Comunicação → Push para o app.</Text>
        </>
      )}
    </ScrollView>
  );
}

function Chips({items, selected, toggle}: {items: {id: string; name: string}[]; selected: string[]; toggle: (id: string) => void}) {
  return (
    <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
      {items.map((i) => {
        const on = selected.includes(i.id);
        return (
          <Pressable key={i.id} accessibilityRole="checkbox" accessibilityState={{checked: on}} style={[ui.chip, on && ui.chipOn]} onPress={() => toggle(i.id)}>
            <Text style={{color: on ? '#fff' : colors.text}}>{i.name}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}
