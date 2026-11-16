// App da igreja: relatório de atendimento (com sigilo), minha semana (calendário) e Integração Visitante do acompanhante.
import {useCallback, useEffect, useState} from 'react';
import {ActivityIndicator, Linking, Pressable, StyleSheet, Text, TextInput, View} from 'react-native';
import type {ChurchRpc} from '../../shared/member-church';
import {contactKinds, emptyDraft, faithLabel, privacyHelp, privacyLabel, reportReferrals, reportTopics, type Privacy, type ReportDraft} from '../../shared/pastoral-care';
import {whatsappLink} from '../../shared/cell-leader';
import {onBrand} from './experience-model';

type Palette = {bg: string; surface: string; text: string; muted: string; line: string; brand: string; accent: string};
type Follow = {person: string; name: string; phone: string; status: string; faith: string; previousChurch: string; next: string | null; startedAt: string; contacts: number; last: string | null};
type CalEvent = {type: 'appointment' | 'invite' | 'request' | 'report' | 'attended' | 'followup'; id: string; at: string; end: string | null; title: string; detail: string; role: string};

const statusLabel: Record<string, string> = {pending: 'Aguardando contato', contacted: 'Contato feito', in_cell: 'Em uma célula', integrated: 'Integrado', stopped: 'Sem retorno'};
const eventTone: Record<CalEvent['type'], [string, string]> = {
  appointment: ['#285c45', 'Atendimento'],
  invite: ['#c9a24c', 'Aguardando aceite'],
  request: ['#b8741a', 'Pedido para confirmar'],
  report: ['#8c2f39', 'Relatório pendente'],
  attended: ['#1f4e79', 'Você será atendido'],
  followup: ['#5b3a6e', 'Contato de integração'],
};
const hm = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'});
const dayTitle = (iso: string) => {
  const t = new Date(iso).toLocaleDateString('pt-BR', {weekday: 'long', day: '2-digit', month: 'long'});
  return t.charAt(0).toUpperCase() + t.slice(1);
};

/** Relatório depois do atendimento (appointment) ou registro de contato da integração (person). */
export function AppReportForm({
  rpc,
  org,
  unit,
  appointment,
  person,
  personName,
  palette: p,
  onDone,
  onCancel,
}: {
  rpc: ChurchRpc;
  org: string;
  unit: string;
  appointment?: string;
  person?: string;
  personName: string;
  palette: Palette;
  onDone: (msg: string) => void;
  onCancel: () => void;
}) {
  const [d, setD] = useState<ReportDraft>({...emptyDraft}),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  const toggle = (k: 'topics' | 'referrals', v: string) => setD({...d, [k]: d[k].includes(v) ? d[k].filter((x) => x !== v) : [...d[k], v]});
  const chip = (on: boolean, label: string, press: () => void) => (
    <Pressable key={label} accessibilityRole="button" accessibilityState={{selected: on}} onPress={press} style={[s.chip, on ? {backgroundColor: p.brand, borderColor: p.brand} : {borderColor: p.line}]}>
      <Text style={{color: on ? onBrand(p.brand) : p.text, fontWeight: '700', fontSize: 13}}>{label}</Text>
    </Pressable>
  );
  async function save() {
    setBusy(true);
    setError('');
    const r = await rpc.rpc('pastoral_reports', {
      p_org: org,
      p_unit: unit,
      p_action: 'save',
      p_data: {
        ...(appointment ? {appointment} : {person, contact: d.contact}),
        summary: d.summary.trim(),
        topics: d.topics,
        prayer: d.prayer.trim(),
        referrals: d.referrals,
        nextStep: /^\d{4}-\d{2}-\d{2}$/.test(d.nextStep) ? d.nextStep : '',
        privacy: d.privacy,
      },
    });
    setBusy(false);
    if (r.error) return setError(/too_early/.test(r.error.message) ? 'O relatório fica disponível depois do horário.' : 'Não foi possível salvar. Confira o texto e tente de novo.');
    onDone(appointment ? 'Relatório salvo no histórico de atendimento.' : 'Contato registrado.');
  }
  const dateMask = (v: string) => {
    const n = v.replace(/\D/g, '').slice(0, 8);
    return n.length > 4 ? n.slice(0, 2) + '/' + n.slice(2, 4) + '/' + n.slice(4) : n.length > 2 ? n.slice(0, 2) + '/' + n.slice(2) : n;
  };
  const [nextText, setNextText] = useState('');
  return (
    <View style={[s.card, {backgroundColor: p.surface, borderColor: p.accent}]}>
      <Text style={[s.over, {color: p.accent}]}>{appointment ? 'RELATÓRIO DE ATENDIMENTO' : 'REGISTRAR CONTATO'}</Text>
      <Text style={{color: p.text, fontWeight: '900', fontSize: 18, marginTop: 4}}>{personName}</Text>
      {!appointment && <View style={s.chips}>{contactKinds.map(([k, l]) => chip(d.contact === k, l, () => setD({...d, contact: k})))}</View>}
      <TextInput
        value={d.summary}
        onChangeText={(v) => setD({...d, summary: v})}
        multiline
        maxLength={8000}
        placeholder="Resumo: o que foi conversado e combinado"
        placeholderTextColor={p.muted}
        style={[s.input, s.area, {color: p.text, borderColor: p.line, backgroundColor: p.bg}]}
      />
      <Text style={[s.label, {color: p.muted}]}>Assuntos</Text>
      <View style={s.chips}>{reportTopics.map(([k, l]) => chip(d.topics.includes(k), l, () => toggle('topics', k)))}</View>
      <Text style={[s.label, {color: p.muted}]}>Encaminhamentos</Text>
      <View style={s.chips}>{reportReferrals.map(([k, l]) => chip(d.referrals.includes(k), l, () => toggle('referrals', k)))}</View>
      <TextInput
        value={d.prayer}
        onChangeText={(v) => setD({...d, prayer: v})}
        multiline
        maxLength={2000}
        placeholder="Pedidos de oração (opcional)"
        placeholderTextColor={p.muted}
        style={[s.input, {color: p.text, borderColor: p.line, backgroundColor: p.bg, minHeight: 60, textAlignVertical: 'top'}]}
      />
      <TextInput
        value={nextText}
        onChangeText={(v) => {
          const m = dateMask(v);
          setNextText(m);
          const x = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(m);
          setD({...d, nextStep: x ? x[3] + '-' + x[2] + '-' + x[1] : ''});
        }}
        keyboardType="number-pad"
        placeholder="Próximo contato (dd/mm/aaaa, opcional)"
        placeholderTextColor={p.muted}
        style={[s.input, {color: p.text, borderColor: p.line, backgroundColor: p.bg}]}
      />
      <Text style={[s.label, {color: p.muted}]}>Quem pode ler</Text>
      {(['team', 'restricted', 'secret'] as Privacy[]).map((k) => (
        <Pressable
          key={k}
          accessibilityRole="radio"
          accessibilityState={{checked: d.privacy === k}}
          onPress={() => setD({...d, privacy: k})}
          style={[s.privacy, {borderColor: d.privacy === k ? p.brand : p.line, backgroundColor: d.privacy === k ? p.brand + '14' : 'transparent'}]}
        >
          <Text style={{color: p.text, fontWeight: '800'}}>{privacyLabel[k]}</Text>
          <Text style={{color: p.muted, fontSize: 12, marginTop: 2}}>{privacyHelp[k]}</Text>
        </Pressable>
      ))}
      <Text style={{color: p.muted, fontSize: 12, marginTop: 10}}>O membro nunca vê o relatório. Toda leitura fica registrada.</Text>
      {!!error && <Text style={{color: '#8c2f39', marginTop: 8}}>{error}</Text>}
      <View style={s.actions}>
        <Pressable accessibilityRole="button" onPress={onCancel} style={[s.btn, {borderColor: p.line, borderWidth: 1}]}>
          <Text style={{color: p.text, fontWeight: '700'}}>Cancelar</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          disabled={busy || d.summary.trim().length < 3}
          onPress={() => void save()}
          style={[s.btn, {backgroundColor: p.brand, opacity: busy || d.summary.trim().length < 3 ? 0.5 : 1}]}
        >
          <Text style={{color: onBrand(p.brand), fontWeight: '900'}}>{busy ? 'Salvando…' : 'Salvar'}</Text>
        </Pressable>
      </View>
    </View>
  );
}

/** Minha semana: atendimentos, convites, pedidos, relatórios pendentes e próximos contatos de integração. */
export function MyCareCalendar({rpc, org, unit, palette: p, rev, onReport}: {rpc: ChurchRpc; org: string; unit: string; palette: Palette; rev: number; onReport: (id: string, name: string) => void}) {
  const [items, setItems] = useState<CalEvent[] | null>(null);
  useEffect(() => {
    void Promise.resolve(rpc.rpc('member_followups', {p_org: org, p_unit: unit, p_action: 'calendar', p_data: {}})).then((r) => setItems(r.error ? [] : (r.data as {items: CalEvent[]}).items));
  }, [rpc, org, unit, rev]);
  if (!items) return <ActivityIndicator color={p.accent} style={{marginTop: 12}} />;
  const groups = new Map<string, CalEvent[]>();
  for (const e of items.filter((x) => Date.parse(x.at) < Date.now() + 14 * 864e5)) groups.set(dayTitle(e.at), [...(groups.get(dayTitle(e.at)) || []), e]);
  return (
    <View style={{marginTop: 18}}>
      <Text style={[s.over, {color: p.accent}]}>MINHA AGENDA · 14 DIAS</Text>
      <View style={[s.chips, {marginBottom: 6}]}>
        {Object.values(eventTone).map(([c, l]) => (
          <View key={l} style={{flexDirection: 'row', alignItems: 'center', gap: 5}}>
            <View style={{width: 10, height: 10, borderRadius: 3, backgroundColor: c}} />
            <Text style={{color: p.muted, fontSize: 11}}>{l}</Text>
          </View>
        ))}
      </View>
      {!groups.size && <Text style={{color: p.muted, marginTop: 6}}>Nada marcado para os próximos 14 dias.</Text>}
      {[...groups.entries()].map(([day, list]) => (
        <View key={day} style={{marginTop: 10}}>
          <Text style={{color: p.text, fontWeight: '800', marginBottom: 6}}>{day}</Text>
          {list.map((e) => (
            <Pressable
              key={e.type + e.id}
              accessibilityRole={e.type === 'report' ? 'button' : 'text'}
              disabled={e.type !== 'report'}
              onPress={() => onReport(e.id, e.title)}
              style={[s.event, {borderLeftColor: eventTone[e.type][0], backgroundColor: p.surface, borderColor: p.line}]}
            >
              <Text style={{color: p.text, fontWeight: '900', width: 52}}>{e.type === 'followup' ? '—' : hm(e.at)}</Text>
              <View style={{flex: 1}}>
                <Text style={{color: p.text, fontWeight: '700'}}>{e.title}</Text>
                <Text style={{color: eventTone[e.type][0], fontSize: 12, fontWeight: '700'}}>
                  {eventTone[e.type][1]}
                  {e.type === 'report' ? ' · toque para preencher' : ''}
                </Text>
              </View>
            </Pressable>
          ))}
        </View>
      ))}
    </View>
  );
}

export function useIntegration(rpc: ChurchRpc, org: string, unit: string, authenticated: boolean) {
  const [items, setItems] = useState<Follow[]>([]),
    [rev, setRev] = useState(0);
  useEffect(() => {
    if (!authenticated || !unit) return setItems([]);
    void Promise.resolve(rpc.rpc('member_followups', {p_org: org, p_unit: unit, p_action: 'list', p_data: {}})).then((r) => setItems(r.error ? [] : (r.data as {items: Follow[]}).items));
  }, [rpc, org, unit, authenticated, rev]);
  return {items, refresh: () => setRev((n) => n + 1)};
}

/** Integração Visitante: as pessoas que eu acompanho, com contato rápido, registro e etapa. */
export function IntegrationScreen({rpc, org, unit, palette: p, data}: {rpc: ChurchRpc; org: string; unit: string; palette: Palette; data: {items: Follow[]; refresh: () => void}}) {
  const [contact, setContact] = useState<Follow | null>(null),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false);
  const setStatus = useCallback(
    async (f: Follow, status: string) => {
      setBusy(true);
      const r = await rpc.rpc('member_followups', {p_org: org, p_unit: unit, p_action: 'status', p_data: {person: f.person, status}});
      setBusy(false);
      setNotice(r.error ? 'Não foi possível atualizar.' : f.name.split(' ')[0] + ': ' + statusLabel[status] + '.');
      data.refresh();
    },
    [rpc, org, unit, data],
  );
  return (
    <View>
      <View style={[s.hero, {backgroundColor: p.brand}]}>
        <Text style={[s.over, {color: onBrand(p.brand), opacity: 0.85}]}>INTEGRAÇÃO VISITANTE</Text>
        <Text style={{color: onBrand(p.brand), fontSize: 24, fontWeight: '800', marginTop: 6}}>Quem eu acompanho</Text>
        <Text style={{color: onBrand(p.brand), opacity: 0.9, marginTop: 6, lineHeight: 21}}>Faça contato, registre cada conversa e atualize a etapa. A secretaria vê tudo no painel.</Text>
      </View>
      {!!notice && <Text style={[s.notice, {color: p.text, borderColor: p.line, backgroundColor: p.surface}]}>{notice}</Text>}
      {contact && (
        <AppReportForm
          rpc={rpc}
          org={org}
          unit={unit}
          person={contact.person}
          personName={contact.name}
          palette={p}
          onCancel={() => setContact(null)}
          onDone={(m) => {
            setNotice(m);
            setContact(null);
            data.refresh();
          }}
        />
      )}
      {!data.items.length && <Text style={{color: p.muted, marginTop: 16}}>Ninguém para acompanhar agora.</Text>}
      {data.items.map((f) => {
        const wa = whatsappLink(f.phone, 'Olá, ' + f.name.split(' ')[0] + '! Aqui é da igreja. Como você está?');
        const late = f.next && f.next < new Date().toISOString().slice(0, 10);
        return (
          <View key={f.person} style={[s.card, {backgroundColor: p.surface, borderColor: late ? '#8c2f39' : p.line}]}>
            <Text style={{color: p.text, fontWeight: '900', fontSize: 17}}>{f.name}</Text>
            <Text style={{color: p.accent, fontWeight: '700', marginTop: 2}}>
              {faithLabel[f.faith] || faithLabel.unknown}
              {f.previousChurch ? ' · ' + f.previousChurch : ''}
            </Text>
            <Text style={{color: p.muted, fontSize: 13, marginTop: 4}}>
              {statusLabel[f.status]} · {f.contacts === 1 ? '1 contato' : f.contacts + ' contatos'}
              {f.next ? ' · próximo: ' + f.next.split('-').reverse().join('/') : ''}
            </Text>
            <View style={s.actions}>
              {!!wa && (
                <Pressable accessibilityRole="link" onPress={() => void Linking.openURL(wa)} style={[s.btn, {borderColor: p.line, borderWidth: 1}]}>
                  <Text style={{color: p.text, fontWeight: '700'}}>WhatsApp</Text>
                </Pressable>
              )}
              <Pressable accessibilityRole="button" onPress={() => setContact(f)} style={[s.btn, {backgroundColor: p.brand}]}>
                <Text style={{color: onBrand(p.brand), fontWeight: '900'}}>Registrar contato</Text>
              </Pressable>
            </View>
            <View style={[s.chips, {marginTop: 10}]}>
              {['contacted', 'in_cell', 'integrated', 'stopped'].map((st) => (
                <Pressable
                  key={st}
                  accessibilityRole="button"
                  disabled={busy || f.status === st}
                  onPress={() => void setStatus(f, st)}
                  style={[s.chip, f.status === st ? {backgroundColor: p.accent, borderColor: p.accent} : {borderColor: p.line}]}
                >
                  <Text style={{color: f.status === st ? onBrand(p.accent) : p.text, fontSize: 12, fontWeight: '700'}}>{statusLabel[st]}</Text>
                </Pressable>
              ))}
            </View>
          </View>
        );
      })}
    </View>
  );
}

const s = StyleSheet.create({
  card: {borderWidth: 1, borderRadius: 18, padding: 16, marginTop: 12},
  hero: {borderRadius: 22, padding: 20},
  over: {fontSize: 11, fontWeight: '800', letterSpacing: 1.5},
  label: {fontSize: 12, fontWeight: '800', marginTop: 12, marginBottom: 6, letterSpacing: 0.5},
  chips: {flexDirection: 'row', flexWrap: 'wrap', gap: 6},
  chip: {borderWidth: 1, borderRadius: 999, paddingHorizontal: 12, paddingVertical: 7},
  input: {borderWidth: 1, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10, fontSize: 15, marginTop: 10},
  area: {minHeight: 110, textAlignVertical: 'top'},
  privacy: {borderWidth: 1, borderRadius: 12, padding: 12, marginTop: 6},
  actions: {flexDirection: 'row', gap: 10, marginTop: 14, flexWrap: 'wrap'},
  btn: {minHeight: 44, paddingHorizontal: 18, borderRadius: 12, alignItems: 'center', justifyContent: 'center'},
  event: {flexDirection: 'row', alignItems: 'center', gap: 10, borderWidth: 1, borderLeftWidth: 5, borderRadius: 12, padding: 12, marginTop: 6},
  notice: {borderWidth: 1, borderRadius: 12, padding: 12, marginTop: 12},
});
