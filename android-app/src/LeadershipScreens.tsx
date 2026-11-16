// App da igreja: Minhas funções (perfil), Liderança da igreja (mensagem; telefone só se o líder autorizar) e conversas.
import {useCallback, useEffect, useState} from 'react';
import {ActivityIndicator, Linking, Pressable, StyleSheet, Switch, Text, TextInput, View} from 'react-native';
import type {ChurchRpc} from '../../shared/member-church';
import {onBrand} from './experience-model';

type Palette = {bg: string; surface: string; text: string; muted: string; line: string; brand: string; accent: string};
type Mine = {
  positions: {id: string; name: string; since: string | null}[];
  groups: {kind: string; group: string; function: string; leadership: boolean}[];
  label: string;
  labelPlural?: string;
  leader: boolean;
  showPhone?: boolean;
};
type Leader = {person: string; name: string; self: boolean; positions: string[]; functions: string[]; phone: string};
type Message = {id: string; mine: boolean; with: string; name: string; body: string; at: string};

const kindLabel: Record<string, string> = {cell: 'Célula', network: 'Rede', ministry: 'Ministério', scale: 'Escala', kids: 'Kids'};
const initials = (n: string) =>
  n
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((x) => x[0])
    .join('')
    .toUpperCase();
const when = (iso: string) => {
  const d = new Date(iso);
  return d.toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit'}) + ' ' + d.toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'});
};
const errorText = (m: string) =>
  /rate_limited/.test(m)
    ? 'Você enviou muitas mensagens na última hora. Tente mais tarde.'
    : /profile_required/.test(m)
      ? 'Complete o seu cadastro na igreja para enviar mensagens.'
      : 'Não foi possível concluir. Tente de novo.';

export function useMyRoles(rpc: ChurchRpc, org: string, unit: string, authenticated: boolean) {
  const [data, setData] = useState<Mine | null>(null);
  const reload = useCallback(() => {
    if (!authenticated || !unit) return;
    void Promise.resolve(rpc.rpc('member_roles', {p_org: org, p_unit: unit, p_action: 'mine', p_data: {}})).then((r) => {
      if (!r.error) setData(r.data as Mine);
    });
  }, [rpc, org, unit, authenticated]);
  useEffect(reload, [reload]);
  return {data, reload, setData};
}

/** Cartão "Minhas funções" no perfil: cargos, grupos e a escolha de mostrar o telefone na página Liderança. */
export function MyRolesCard({rpc, org, unit, authenticated, palette: p}: {rpc: ChurchRpc; org: string; unit: string; authenticated: boolean; palette: Palette}) {
  const {data, setData} = useMyRoles(rpc, org, unit, authenticated);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  if (!data || (!data.positions.length && !data.groups.length)) return null;
  async function togglePhone(v: boolean) {
    setBusy(true);
    setError('');
    const r = await rpc.rpc('member_roles', {p_org: org, p_unit: unit, p_action: 'privacy', p_data: {showPhone: v}});
    setBusy(false);
    if (r.error) setError('Não foi possível salvar. Tente de novo.');
    else setData({...data!, showPhone: v});
  }
  return (
    <View style={[s.card, {backgroundColor: p.surface, borderColor: p.line}]}>
      <Text style={[s.over, {color: p.muted}]}>MINHAS FUNÇÕES</Text>
      {!!data.positions.length && (
        <View style={s.chips}>
          {data.positions.map((x) => (
            <View key={x.id} style={[s.chip, {backgroundColor: p.accent}]}>
              <Text style={{color: onBrand(p.accent), fontWeight: '800', fontSize: 13}}>{x.name}</Text>
            </View>
          ))}
        </View>
      )}
      {data.groups.map((g, i) => (
        <View key={g.group + g.function + i} style={[s.groupRow, {borderColor: p.line}]}>
          <Text style={[s.kind, {color: p.muted, borderColor: p.line}]}>{kindLabel[g.kind] || 'Grupo'}</Text>
          <View style={{flex: 1}}>
            <Text style={{color: p.text, fontWeight: '700', fontSize: 15}}>{g.group}</Text>
            <Text style={{color: p.muted, fontSize: 13, marginTop: 2}}>
              {g.leadership ? '★ ' : ''}
              {g.function}
            </Text>
          </View>
        </View>
      ))}
      {data.leader && (
        <View style={[s.privacy, {borderColor: p.line}]}>
          <View style={{flex: 1}}>
            <Text style={{color: p.text, fontWeight: '700'}}>Mostrar meu telefone na página Liderança</Text>
            <Text style={{color: p.muted, fontSize: 13, marginTop: 3}}>Desligado, os membros só conseguem enviar mensagem pelo app.</Text>
          </View>
          <Switch value={!!data.showPhone} disabled={busy} onValueChange={(v) => void togglePhone(v)} trackColor={{true: p.brand, false: p.line}} accessibilityLabel="Mostrar meu telefone" />
        </View>
      )}
      {!!error && <Text style={{color: p.text, marginTop: 8}}>{error}</Text>}
    </View>
  );
}

/** Página "Liderança da igreja": pastores e líderes, mensagem pelo app e as conversas. */
export function LeadershipScreen({rpc, org, unit, authenticated, onLogin, palette: p}: {rpc: ChurchRpc; org: string; unit: string; authenticated: boolean; onLogin: () => void; palette: Palette}) {
  const [items, setItems] = useState<Leader[] | null>(null),
    [label, setLabel] = useState('Cargo'),
    [messages, setMessages] = useState<Message[]>([]),
    [to, setTo] = useState<{person: string; name: string} | null>(null),
    [body, setBody] = useState(''),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState(''),
    [error, setError] = useState(''),
    [query, setQuery] = useState('');
  const load = useCallback(() => {
    if (!unit) return;
    void Promise.resolve(rpc.rpc('member_roles', {p_org: org, p_unit: unit, p_action: 'leadership', p_data: {}})).then((r) => {
      if (r.error) {
        setError(authenticated ? 'Não foi possível carregar a liderança.' : '');
        setItems([]);
      } else {
        const d = r.data as {items: Leader[]; label: string};
        setItems(d.items);
        setLabel(d.label);
      }
    });
    if (authenticated)
      void Promise.resolve(rpc.rpc('member_roles', {p_org: org, p_unit: unit, p_action: 'messages', p_data: {}})).then((r) => {
        if (!r.error) setMessages((r.data as {items: Message[]}).items);
      });
  }, [rpc, org, unit, authenticated]);
  useEffect(load, [load]);
  async function send() {
    if (!to) return;
    setBusy(true);
    setError('');
    const r = await rpc.rpc('member_roles', {p_org: org, p_unit: unit, p_action: 'send', p_data: {to: to.person, body: body.trim()}});
    setBusy(false);
    if (r.error) return setError(errorText(r.error.message));
    setNotice('Mensagem enviada para ' + to.name.split(' ')[0] + '. A resposta chega nas suas notificações.');
    setTo(null);
    setBody('');
    load();
  }
  if (!authenticated)
    return (
      <View style={[s.card, {backgroundColor: p.surface, borderColor: p.line}]}>
        <Text style={[s.title, {color: p.text}]}>Liderança da igreja</Text>
        <Text style={{color: p.muted, fontSize: 15, lineHeight: 22, marginTop: 6}}>Entre na sua conta para ver os pastores e líderes e enviar uma mensagem.</Text>
        <Pressable accessibilityRole="button" onPress={onLogin} style={[s.primary, {backgroundColor: p.brand}]}>
          <Text style={{color: onBrand(p.brand), fontWeight: '800'}}>Entrar</Text>
        </Pressable>
      </View>
    );
  if (!items) return <ActivityIndicator color={p.brand} style={{marginTop: 30}} />;
  const q = query.trim().toLowerCase();
  const list = items.filter((x) => !x.self && (!q || (x.name + ' ' + x.positions.join(' ') + ' ' + x.functions.join(' ')).toLowerCase().includes(q)));
  const threads = new Map<string, Message[]>();
  for (const m of messages) threads.set(m.with, [...(threads.get(m.with) || []), m]);
  return (
    <View>
      <View style={[s.hero, {backgroundColor: p.brand}]}>
        <Text style={[s.over, {color: onBrand(p.brand), opacity: 0.85}]}>QUEM CUIDA DE NÓS</Text>
        <Text style={{color: onBrand(p.brand), fontSize: 26, fontWeight: '800', marginTop: 6}}>Liderança da igreja</Text>
        <Text style={{color: onBrand(p.brand), opacity: 0.9, marginTop: 8, fontSize: 15, lineHeight: 22}}>
          Pastores e líderes da sua igreja. Envie uma mensagem pelo app; a resposta chega nas suas notificações.
        </Text>
      </View>
      {!!notice && <Text style={[s.notice, {color: p.text, borderColor: p.line, backgroundColor: p.surface}]}>{notice}</Text>}
      {!!error && <Text style={[s.notice, {color: p.text, borderColor: p.line, backgroundColor: p.surface}]}>{error}</Text>}
      {items.length > 6 && (
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder={'Buscar por nome, ' + label.toLowerCase() + ' ou célula'}
          placeholderTextColor={p.muted}
          style={[s.input, {color: p.text, borderColor: p.line, backgroundColor: p.surface}]}
        />
      )}
      {!list.length && <Text style={{color: p.muted, marginTop: 16}}>Nenhum líder cadastrado nesta igreja ainda.</Text>}
      {list.map((x) => (
        <View key={x.person} style={[s.card, {backgroundColor: p.surface, borderColor: p.line}]}>
          <View style={{flexDirection: 'row', gap: 14, alignItems: 'center'}}>
            <View style={[s.avatar, {backgroundColor: p.bg, borderColor: p.accent}]}>
              <Text style={{color: p.text, fontWeight: '800', fontSize: 16}}>{initials(x.name)}</Text>
            </View>
            <View style={{flex: 1}}>
              <Text style={{color: p.text, fontWeight: '800', fontSize: 17}}>{x.name}</Text>
              {!!x.positions.length && <Text style={{color: p.accent, fontWeight: '700', marginTop: 3}}>{x.positions.join(' · ')}</Text>}
              {x.functions.slice(0, 3).map((f) => (
                <Text key={f} style={{color: p.muted, fontSize: 13, marginTop: 2}}>
                  ★ {f}
                </Text>
              ))}
            </View>
          </View>
          <View style={s.actions}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={'Enviar mensagem para ' + x.name}
              onPress={() => (setTo({person: x.person, name: x.name}), setNotice(''), setError(''))}
              style={[s.action, {backgroundColor: p.brand, borderColor: p.brand}]}
            >
              <Text style={{color: onBrand(p.brand), fontWeight: '800'}}>Mensagem</Text>
            </Pressable>
            {!!x.phone && (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={'WhatsApp de ' + x.name}
                onPress={() => void Linking.openURL('https://wa.me/55' + x.phone.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, ''))}
                style={[s.action, {backgroundColor: p.surface, borderColor: p.line}]}
              >
                <Text style={{color: p.text, fontWeight: '700'}}>WhatsApp</Text>
              </Pressable>
            )}
          </View>
          {to?.person === x.person && (
            <View style={{marginTop: 12}}>
              <TextInput
                value={body}
                onChangeText={setBody}
                multiline
                maxLength={1000}
                autoFocus
                placeholder={'Escreva para ' + x.name.split(' ')[0] + '…'}
                placeholderTextColor={p.muted}
                style={[s.input, s.area, {color: p.text, borderColor: p.line, backgroundColor: p.bg}]}
              />
              <View style={s.actions}>
                <Pressable accessibilityRole="button" onPress={() => setTo(null)} style={[s.action, {backgroundColor: p.surface, borderColor: p.line}]}>
                  <Text style={{color: p.text, fontWeight: '700'}}>Cancelar</Text>
                </Pressable>
                <Pressable
                  accessibilityRole="button"
                  disabled={busy || body.trim().length < 2}
                  onPress={() => void send()}
                  style={[s.action, {backgroundColor: p.brand, borderColor: p.brand, opacity: busy || body.trim().length < 2 ? 0.5 : 1}]}
                >
                  <Text style={{color: onBrand(p.brand), fontWeight: '800'}}>{busy ? 'Enviando…' : 'Enviar'}</Text>
                </Pressable>
              </View>
            </View>
          )}
        </View>
      ))}
      {threads.size > 0 && (
        <View style={{marginTop: 18}}>
          <Text style={[s.section, {color: p.text}]}>Minhas conversas</Text>
          {[...threads.entries()].map(([who, list]) => (
            <View key={who} style={[s.card, {backgroundColor: p.surface, borderColor: p.line}]}>
              <Text style={{color: p.text, fontWeight: '800', fontSize: 16}}>{list[0]!.name}</Text>
              {list
                .slice(0, 6)
                .reverse()
                .map((m) => (
                  <View key={m.id} style={[s.bubble, m.mine ? {alignSelf: 'flex-end', backgroundColor: p.brand} : {alignSelf: 'flex-start', backgroundColor: p.bg, borderColor: p.line, borderWidth: 1}]}>
                    <Text style={{color: m.mine ? onBrand(p.brand) : p.text, fontSize: 15, lineHeight: 21}}>{m.body}</Text>
                    <Text style={{color: m.mine ? onBrand(p.brand) : p.muted, opacity: 0.8, fontSize: 11, marginTop: 4}}>{when(m.at)}</Text>
                  </View>
                ))}
              {to?.person !== who && (
                <Pressable accessibilityRole="button" onPress={() => (setTo({person: who, name: list[0]!.name}), setNotice(''))} style={{marginTop: 8}}>
                  <Text style={{color: p.text, fontWeight: '800'}}>Responder →</Text>
                </Pressable>
              )}
              {to?.person === who && !items.some((x) => x.person === who) && (
                <View style={{marginTop: 10}}>
                  <TextInput
                    value={body}
                    onChangeText={setBody}
                    multiline
                    maxLength={1000}
                    autoFocus
                    placeholder="Sua resposta…"
                    placeholderTextColor={p.muted}
                    style={[s.input, s.area, {color: p.text, borderColor: p.line, backgroundColor: p.bg}]}
                  />
                  <View style={s.actions}>
                    <Pressable accessibilityRole="button" onPress={() => setTo(null)} style={[s.action, {backgroundColor: p.surface, borderColor: p.line}]}>
                      <Text style={{color: p.text, fontWeight: '700'}}>Cancelar</Text>
                    </Pressable>
                    <Pressable
                      accessibilityRole="button"
                      disabled={busy || body.trim().length < 2}
                      onPress={() => void send()}
                      style={[s.action, {backgroundColor: p.brand, borderColor: p.brand, opacity: busy || body.trim().length < 2 ? 0.5 : 1}]}
                    >
                      <Text style={{color: onBrand(p.brand), fontWeight: '800'}}>{busy ? 'Enviando…' : 'Enviar'}</Text>
                    </Pressable>
                  </View>
                </View>
              )}
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  card: {borderWidth: 1, borderRadius: 18, padding: 16, marginTop: 12},
  hero: {borderRadius: 22, padding: 22},
  over: {fontSize: 11, fontWeight: '800', letterSpacing: 1.6},
  title: {fontSize: 22, fontWeight: '800'},
  section: {fontSize: 20, fontWeight: '800'},
  chips: {flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 10},
  chip: {borderRadius: 999, paddingHorizontal: 12, paddingVertical: 6},
  groupRow: {flexDirection: 'row', alignItems: 'center', gap: 12, borderTopWidth: 1, paddingTop: 12, marginTop: 12},
  kind: {fontSize: 11, fontWeight: '800', letterSpacing: 0.6, borderWidth: 1, borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4, textTransform: 'uppercase'},
  privacy: {flexDirection: 'row', alignItems: 'center', gap: 12, borderTopWidth: 1, paddingTop: 14, marginTop: 14},
  avatar: {width: 54, height: 54, borderRadius: 27, borderWidth: 2, alignItems: 'center', justifyContent: 'center'},
  actions: {flexDirection: 'row', gap: 10, marginTop: 12, flexWrap: 'wrap'},
  action: {minHeight: 44, paddingHorizontal: 18, borderRadius: 12, borderWidth: 1, alignItems: 'center', justifyContent: 'center'},
  primary: {minHeight: 46, borderRadius: 12, alignItems: 'center', justifyContent: 'center', marginTop: 16},
  input: {borderWidth: 1, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, marginTop: 14},
  area: {minHeight: 96, textAlignVertical: 'top', marginTop: 0},
  notice: {borderWidth: 1, borderRadius: 12, padding: 12, marginTop: 12},
  bubble: {maxWidth: '86%', borderRadius: 14, paddingHorizontal: 12, paddingVertical: 8, marginTop: 8},
});
