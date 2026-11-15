import {useEffect, useState} from 'react';
import {ActivityIndicator, Image, Pressable, ScrollView, Text, TextInput, View} from 'react-native';
import * as Crypto from 'expo-crypto';
import {api, ApiError, authHeaders, type Unit} from './api';
import {fieldErrors} from '../../shared/contract/errors.ts';
import {pushCampaignSchema, pushImageUrl, pushLimits, pushRoles, type PushOptions, type PushReach, type PushSegment} from '../../shared/contract/push.ts';
import {colors, ui} from './theme';

type Options = PushOptions;
type Reach = PushReach;

/** Push from the phone: destinations are only the churches the server says this person may publish to. */
export default function PushComposer({org, unit, back}: {org: string; unit: Unit; units: Unit[]; back: () => void}) {
  const [options, setOptions] = useState<Options | null>(null),
    [title, setTitle] = useState(''),
    [body, setBody] = useState(''),
    [targets, setTargets] = useState<string[]>([unit.id]),
    [cells, setCells] = useState<string[]>([]),
    [groups, setGroups] = useState<string[]>([]),
    [roles, setRoles] = useState<string[]>([]),
    [extra, setExtra] = useState<Record<string, unknown>>({}),
    [segments, setSegments] = useState<PushSegment[]>([]),
    [segment, setSegment] = useState(''),
    [images, setImages] = useState<{id: string; name: string}[] | null>(null),
    [image, setImage] = useState(''),
    [headers, setHeaders] = useState<Record<string, string>>({}),
    [mode, setMode] = useState<'now' | 'schedule'>('now'),
    [day, setDay] = useState(''),
    [time, setTime] = useState('19:00'),
    [reach, setReach] = useState<Reach | null>(null),
    [busy, setBusy] = useState(false),
    [done, setDone] = useState(''),
    [error, setError] = useState(''),
    [fields, setFields] = useState<Record<string, string>>({}),
    [request, setRequest] = useState(() => Crypto.randomUUID());
  useEffect(() => {
    api<Options>('/api/push/campaigns?' + new URLSearchParams({unit: unit.id, options: '1'}), org)
      .then((o) => {
        setOptions(o);
        setTargets((t) => t.filter((id) => o.units.some((u) => u.id === id)));
      })
      .catch((e) => setError((e as Error).message));
    api<{items: PushSegment[]}>('/api/push/segments?' + new URLSearchParams({unit: unit.id}), org)
      .then((d) => setSegments(d.items || []))
      .catch(() => setSegments([]));
    void authHeaders(org).then(setHeaders);
  }, [org, unit.id]);
  function applySegment(sg: PushSegment) {
    if (segment === sg.id) {
      setSegment('');
      setRoles([]);
      setCells([]);
      setGroups([]);
      setExtra({});
      return;
    }
    const {roles: r, cells: c, groups: g, ...rest} = sg.audience;
    setSegment(sg.id);
    setRoles(r || []);
    setCells(c || []);
    setGroups(g || []);
    setExtra(rest);
  }
  function loadImages() {
    api<{items: {id: string; name: string}[]}>('/api/publishing-images?' + new URLSearchParams({unit: unit.id}), org)
      .then((d) => setImages(d.items || []))
      .catch(() => setImages([]));
  }
  const audience = {...extra, ...(roles.length ? {roles} : {}), ...(cells.length ? {cells} : {}), ...(groups.length ? {groups} : {})};
  useEffect(() => {
    if (!options || !targets.length) return setReach(null);
    const timer = setTimeout(() => {
      api<Reach>('/api/push/campaigns', org, {method: 'POST', body: {unit: unit.id, action: 'preview', data: {targets, audience}}})
        .then(setReach)
        .catch(() => setReach(null));
    }, 400);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options, targets.join(), cells.join(), groups.join(), roles.join(), JSON.stringify(extra)]);
  async function send() {
    if (busy) return;
    const data = {
      title: title.trim(),
      body: body.trim(),
      targets,
      audience,
      link: {screen: 'inbox' as const, ...(image ? {image} : {})},
      mode,
      ...(mode === 'schedule' ? {sendAt: scheduleAt(day, time)} : {}),
      recurrence: 'none' as const,
      request,
    };
    // Same rules as the panel and the API (shared/contract/push.ts).
    const check = pushCampaignSchema.safeParse(data);
    if (!check.success) {
      const f = fieldErrors(check.error);
      setFields(f);
      setError(Object.values(f)[0]);
      return;
    }
    setFields({});
    setBusy(true);
    setError('');
    try {
      await api('/api/push/campaigns', org, {method: 'POST', body: {unit: unit.id, action: 'create', data}});
      setDone(
        mode === 'schedule'
          ? `Agendado para ${new Date(scheduleAt(day, time)).toLocaleString('pt-BR', {dateStyle: 'short', timeStyle: 'short'})}.`
          : `Enviado para ${reach?.people ?? 'as'} pessoas. Os avisos chegam em até um minuto.`,
      );
      setTitle('');
      setBody('');
      setRequest(Crypto.randomUUID());
    } catch (e) {
      setError((e as Error).message);
      setFields(e instanceof ApiError ? e.fields : {});
    } finally {
      setBusy(false);
    }
  }
  const toggle = (list: string[], set: (v: string[]) => void, id: string) => set(list.includes(id) ? list.filter((x) => x !== id) : [...list, id]);
  const valid =
    title.trim().length >= 2 && body.trim().length >= 2 && targets.length > 0 && (mode === 'now' || (!!day && /^([01]\d|2[0-3]):[0-5]\d$/.test(time)));
  const next14 = Array.from({length: 14}, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() + i);
    return d;
  });
  return (
    <ScrollView contentContainerStyle={ui.pad} keyboardShouldPersistTaps="handled">
      <Pressable accessibilityRole="button" onPress={back}>
        <Text style={{color: colors.brand, fontWeight: '600'}}>← Voltar</Text>
      </Pressable>
      <Text style={ui.over}>ENVIAR PUSH</Text>
      <Text style={ui.h1}>Novo aviso</Text>
      {!options ? (
        error ? (
          <Text style={ui.error}>{error}</Text>
        ) : (
          <ActivityIndicator color={colors.brand} />
        )
      ) : (
        <>
          <Text style={ui.label}>
            Título ({title.length}/{pushLimits.title})
          </Text>
          <TextInput
            style={[ui.input, !!fields.title && ui.inputInvalid]}
            maxLength={pushLimits.title}
            value={title}
            onChangeText={setTitle}
            placeholder="Culto de domingo"
            accessibilityHint={fields.title}
          />
          <FieldError message={fields.title} />
          <Text style={ui.label}>
            Mensagem ({body.length}/{pushLimits.body})
          </Text>
          <TextInput
            style={[ui.input, {minHeight: 90, paddingTop: 12, textAlignVertical: 'top'}, !!fields.body && ui.inputInvalid]}
            multiline
            maxLength={pushLimits.body}
            value={body}
            onChangeText={setBody}
            placeholder="Hoje às 19h. Traga sua família!"
            accessibilityHint={fields.body}
          />
          <FieldError message={fields.body} />
          <View style={[ui.card, {backgroundColor: '#eef3ef'}]}>
            <Text style={{fontWeight: '700', color: colors.text}}>{title || 'Título da notificação'}</Text>
            <Text style={ui.copy}>{body || 'Assim o aviso aparece na tela do celular.'}</Text>
            {!!image && <Image source={{uri: pushImageUrl(image), headers}} style={{height: 140, borderRadius: 12, marginTop: 6}} resizeMode="cover" />}
          </View>
          <Text style={ui.label}>Imagem de capa (opcional)</Text>
          {images === null ? (
            <Pressable accessibilityRole="button" style={ui.chip} onPress={loadImages}>
              <Text style={{color: colors.text}}>{image ? 'Trocar imagem' : 'Escolher do banco de imagens'}</Text>
            </Pressable>
          ) : !images.length ? (
            <Text style={ui.copy}>Nenhuma imagem no banco. Envie imagens pelo painel, em Comunicação.</Text>
          ) : (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap: 8}}>
              <Pressable accessibilityRole="button" onPress={() => setImage('')} style={[ui.chip, {justifyContent: 'center'}, !image && ui.chipOn]}>
                <Text style={{color: !image ? '#fff' : colors.text}}>Sem capa</Text>
              </Pressable>
              {images.map((im) => (
                <Pressable
                  key={im.id}
                  accessibilityRole="radio"
                  accessibilityLabel={im.name}
                  accessibilityState={{checked: image === im.id}}
                  onPress={() => setImage(im.id)}
                >
                  <Image
                    source={{uri: pushImageUrl(im.id), headers}}
                    style={{width: 96, height: 72, borderRadius: 10, borderWidth: 3, borderColor: image === im.id ? colors.gold : 'transparent'}}
                  />
                </Pressable>
              ))}
            </ScrollView>
          )}
          <FieldError message={fields['link.image']} />
          {!!segments.length && (
            <>
              <Text style={ui.label}>Públicos salvos</Text>
              <Chips items={segments} selected={segment ? [segment] : []} toggle={(id) => applySegment(segments.find((x) => x.id === id)!)} />
            </>
          )}
          <Text style={ui.label}>Igrejas que recebem</Text>
          <Chips items={options.units} selected={targets} toggle={(id) => toggle(targets, setTargets, id)} />
          <FieldError message={fields.targets} />
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
          <Text style={ui.label}>Somente estas funções (opcional)</Text>
          <Chips items={pushRoles.map((r) => ({id: r, name: roleNames[r]}))} selected={roles} toggle={(id) => toggle(roles, setRoles, id)} />
          <Text style={ui.label}>Quando enviar</Text>
          <Chips
            items={[
              {id: 'now', name: 'Agora'},
              {id: 'schedule', name: 'Agendar'},
            ]}
            selected={[mode]}
            toggle={(id) => setMode(id as 'now' | 'schedule')}
          />
          {mode === 'schedule' && (
            <>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap: 8}}>
                {next14.map((d) => {
                  const k = isoDay(d),
                    on = day === k;
                  return (
                    <Pressable
                      key={k}
                      accessibilityRole="radio"
                      accessibilityState={{checked: on}}
                      onPress={() => setDay(k)}
                      style={[ui.chip, {alignItems: 'center'}, on && ui.chipOn]}
                    >
                      <Text style={{color: on ? '#fff' : colors.muted, fontSize: 11, fontWeight: '700'}}>
                        {d.toLocaleDateString('pt-BR', {weekday: 'short'})}
                      </Text>
                      <Text style={{color: on ? '#fff' : colors.text, fontWeight: '800', fontSize: 16}}>
                        {d.getDate()}/{d.getMonth() + 1}
                      </Text>
                    </Pressable>
                  );
                })}
              </ScrollView>
              <Text style={ui.label}>Horário</Text>
              <TextInput
                style={[ui.input, {width: 120}, !!fields.sendAt && ui.inputInvalid]}
                value={time}
                keyboardType="number-pad"
                maxLength={5}
                onChangeText={(v) => {
                  const d = v.replace(/\D/g, '').slice(0, 4);
                  setTime(d.length <= 2 ? d : d.slice(0, 2) + ':' + d.slice(2));
                }}
              />
              <FieldError message={fields.sendAt} />
            </>
          )}
          <Text style={ui.copy} accessibilityLiveRegion="polite">
            {!targets.length
              ? 'Escolha ao menos uma igreja.'
              : reach
                ? `Alcance agora: ${reach.people} pessoas em ${reach.devices} aparelhos.`
                : 'Calculando alcance…'}
          </Text>
          {!!error && <Text style={ui.error}>{error}</Text>}
          {!!done && <Text style={{color: colors.ok, fontWeight: '600'}}>{done}</Text>}
          <Pressable accessibilityRole="button" style={[ui.primary, (!valid || busy) && {opacity: 0.5}]} disabled={!valid || busy} onPress={() => void send()}>
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>{mode === 'schedule' ? 'Agendar envio' : 'Enviar agora'}</Text>}
          </Pressable>
          <Text style={[ui.copy, {fontSize: 13}]}>
            Repetição, filtros por idade e novos públicos salvos ficam no painel da Vinha, em Comunicação → Push para o app.
          </Text>
        </>
      )}
    </ScrollView>
  );
}

const roleNames: Record<string, string> = {
  owner: 'Responsável',
  pastor: 'Pastores',
  admin: 'Administração',
  secretary: 'Secretaria',
  finance: 'Financeiro',
  leader: 'Líderes',
  member: 'Membros',
  viewer: 'Visitantes do app',
};
const isoDay = (d: Date) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
/** Data e hora escolhidas no aparelho (horário local) em ISO. */
const scheduleAt = (day: string, time: string) => (day && time ? new Date(day + 'T' + time + ':00').toISOString() : '');

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

function FieldError({message}: {message?: string}) {
  return message ? (
    <Text style={ui.fieldError} accessibilityRole="alert">
      {message}
    </Text>
  ) : null;
}
