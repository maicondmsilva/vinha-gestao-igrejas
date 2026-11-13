import {useState} from 'react';
import {ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import type {ChurchRpc} from '../../shared/member-church';
import {useVolunteerScales, type Availability, type VolunteerInvite} from '../../shared/use-volunteer-scales';
import {availabilityDraft, availabilityPayload, minutesText, type AvailabilityDraft} from '../../shared/scale-availability';
import {formatInZone} from '../../shared/timezone';
import {presenceStatus, responseStatus, serviceStatus, weekdays} from '../../shared/scale-operations';
import {onBrand} from './experience-model';
import WorshipMusician from './WorshipMusician';
type Palette = {surface: string; text: string; muted: string; line: string; brand: string};
export default function VolunteerScales({
  rpc,
  org,
  authenticated,
  palette,
  onLogin,
}: {
  rpc: ChurchRpc;
  org: string;
  authenticated: boolean;
  palette: Palette;
  onLogin: () => void;
}) {
  const m = useVolunteerScales(rpc, org, authenticated, randomUUID),
    [tab, setTab] = useState('invites'),
    [form, setForm] = useState<AvailabilityDraft | null>(null),
    [request, setRequest] = useState<VolunteerInvite | null>(null),
    [reason, setReason] = useState(''),
    [search, setSearch] = useState(''),
    [suggestion, setSuggestion] = useState(''),
    [people, setPeople] = useState<{id: string; name: string}[]>([]),
    [error, setError] = useState('');
  const zone = m.page?.timezone || m.availability?.timezone || 'America/Sao_Paulo';
  const text = (v: string, heading = false) => (
    <Text
      style={{
        color: heading ? palette.text : palette.muted,
        fontSize: heading ? 18 : 15,
        fontWeight: heading ? '700' : '400',
        lineHeight: 23,
        marginVertical: 5,
      }}
    >
      {v}
    </Text>
  );
  const button = (label: string, action: () => void, disabled = false, selected = false) => (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{disabled: disabled || m.busy, selected}}
      disabled={disabled || m.busy}
      onPress={action}
      style={[s.button, {backgroundColor: selected ? palette.brand : palette.surface, borderColor: palette.brand, opacity: disabled || m.busy ? 0.45 : 1}]}
    >
      <Text style={{color: selected ? onBrand(palette.brand) : palette.text, fontWeight: '600', textAlign: 'center'}}>{label}</Text>
    </Pressable>
  );
  const field = (label: string, value: string, change: (v: string) => void, maxLength = 100, multiline = false) => (
    <View style={{marginTop: 12}}>
      {text(label)}
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={change}
        maxLength={maxLength}
        multiline={multiline}
        editable={!m.busy}
        placeholder={label.includes('Data') ? 'DD/MM/AAAA' : label.includes('Horário') ? 'HH:mm' : undefined}
        placeholderTextColor={palette.muted}
        style={[s.input, {borderColor: palette.line, color: palette.text, backgroundColor: palette.surface, minHeight: multiline ? 90 : 48}]}
      />
    </View>
  );
  function edit(a?: Availability) {
    const f = availabilityDraft(randomUUID(), zone, a);
    f.startDate = f.startDate.split('-').reverse().join('/');
    f.endDate = f.endDate.split('-').reverse().join('/');
    setForm(f);
    setError('');
  }
  async function save() {
    if (!form) return;
    setError('');
    try {
      if (await m.command('available.save', availabilityPayload(form))) setForm(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function find() {
    if (!request) return;
    setError('');
    try {
      setPeople(await m.suggestions(request.id, search));
    } catch (e) {
      setError((e as Error).message);
    }
  }
  if (!authenticated)
    return (
      <View>
        {text('Minhas escalas', true)}
        {text('Entre com a mesma conta vinculada ao cadastro oficial para responder aos convites.')}
        {button('Entrar na minha conta', onLogin)}
      </View>
    );
  return (
    <View>
      {text('Minhas escalas', true)}
      {text(
        'Convites do cadastro oficial' + (m.page?.unitName ? ' · ' + m.page.unitName : '') + '. A igreja acompanhada para conteúdos não altera suas escalas.',
      )}
      <View style={s.row}>
        {button('Convites', () => setTab('invites'), false, tab === 'invites')}
        {button('Disponibilidade', () => setTab('availability'), false, tab === 'availability')}
        {button('Repertório', () => setTab('repertoire'), false, tab === 'repertoire')}
      </View>
      {button('Atualizar escalas', m.refresh, m.loading)}
      {m.loading && <ActivityIndicator color={palette.brand} />}
      <Text accessibilityLiveRegion="polite" style={{color: palette.text, lineHeight: 23}}>
        {m.error || error || m.notice}
      </Text>
      {tab === 'repertoire' ? (
        <WorshipMusician rpc={rpc} org={org} palette={palette} />
      ) : tab === 'invites' ? (
        <>
          {m.page && !m.page.items.length && text('Nenhum convite nesta página. A liderança precisa publicar a escala para o convite aparecer.')}
          {m.page?.items.map((i) => (
            <View key={i.id} style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
              {text(i.title, true)}
              {text(i.team + ' · ' + i.role)}
              {text(formatInZone(i.starts_at, zone) + ' até ' + formatInZone(i.ends_at, zone))}
              {text('Chegada: ' + formatInZone(i.arrival_at, zone))}
              {text(responseStatus[i.response] + ' · Presença: ' + presenceStatus[i.presence])}
              {i.active ? (
                <>
                  {text(serviceStatus[i.status] + ' · Responder até ' + formatInZone(i.deadline, zone))}
                  {i.location ? text('Local: ' + i.location) : null}
                  {i.notes ? text('Orientações: ' + i.notes) : null}
                  {i.recordedByLeader && text('Resposta registrada pela liderança.')}
                  {i.canReply ? (
                    <>
                      {button('Confirmar participação', () => void m.command('reply', {id: i.id, version: i.version, response: 'accepted'}))}
                      {button('Não poderei participar', () => void m.command('reply', {id: i.id, version: i.version, response: 'declined'}))}
                    </>
                  ) : (
                    i.status === 'published' && text('Resposta indisponível no aplicativo. Procure o responsável pela escala.')
                  )}
                  {i.replacement ? (
                    <>
                      {text('Pedido de substituição aguardando decisão.')}
                      {button(
                        'Cancelar pedido de substituição',
                        () => void m.command('replacement.cancel', {id: i.replacement!.id, version: i.replacement!.version}),
                      )}
                    </>
                  ) : (
                    i.status === 'published' &&
                    new Date(i.arrival_at).getTime() > Date.now() &&
                    button('Solicitar substituição', () => {
                      setRequest(i);
                      setReason('');
                      setSearch('');
                      setSuggestion('');
                      setPeople([]);
                      setError('');
                    })
                  )}
                </>
              ) : (
                text(
                  'Convite anterior: ' +
                    ({revision: 'escala em revisão', replaced: 'atribuição substituída', cancelled: 'escala cancelada'}[i.ended_reason] || 'encerrado') +
                    '. Sua resposta foi preservada; as instruções atuais não estão disponíveis.',
                )
              )}
            </View>
          ))}
          {text((m.page?.total || 0) + ' convite(s) · página ' + m.number)}
          <View style={s.row}>
            {button('Anteriores', () => m.setNumber((n) => n - 1), m.number === 1 || m.loading)}
            {button('Mais convites', () => m.setNumber((n) => n + 1), m.loading || !m.page || m.number * 20 >= m.page.total)}
          </View>
          {request && (
            <View style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
              {text('Pedir substituição · ' + request.title, true)}
              {text('A indicação é opcional. A liderança confere a pessoa antes de aprovar. Sua atribuição continua válida até a decisão.')}
              {field('Observação ao responsável (opcional)', reason, setReason, 500, true)}
              {field('Buscar pessoa habilitada', search, setSearch)}
              {button('Buscar sugestão', () => void find(), search.trim().length < 2)}
              {button('Sem indicação', () => setSuggestion(''), false, !suggestion)}
              {people.map((p) => (
                <View key={p.id}>{button(p.name, () => setSuggestion(p.id), false, suggestion === p.id)}</View>
              ))}
              {button(
                'Enviar pedido',
                () =>
                  void m.command('replacement.request', {id: request.id, version: request.version, reason, suggestion: suggestion || null}).then((ok) => {
                    if (ok) setRequest(null);
                  }),
              )}
              {button('Voltar', () => setRequest(null))}
            </View>
          )}
        </>
      ) : (
        <>
          {text(
            'Sem janelas semanais ativas, não há restrição por dia da semana. Períodos de indisponibilidade continuam valendo. Para atravessar a meia-noite, cadastre uma janela em cada dia; use 24:00 para o fim do dia.',
          )}
          {text('Motivos pessoais ficam somente na sua conta. A equipe recebe o aviso de conflito.')}
          {button('Adicionar disponibilidade', () => edit())}
          {m.availability?.items.map((a) => (
            <View key={a.id} style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
              {text((a.kind === 'weekly' ? 'Janela semanal' : 'Indisponibilidade') + ' · ' + (a.active ? 'Ativa' : 'Cancelada'), true)}
              {text(
                a.kind === 'weekly'
                  ? weekdays[a.weekday] + ' · ' + minutesText(a.start_minute) + ' às ' + minutesText(a.end_minute)
                  : formatInZone(a.starts_at, zone) + ' até ' + formatInZone(a.ends_at, zone),
              )}
              {a.reason ? text('Motivo particular: ' + a.reason) : null}
              {button(a.active ? 'Editar disponibilidade' : 'Reativar disponibilidade', () => edit(a))}
              {a.active && button('Cancelar disponibilidade', () => void m.command('available.save', {id: a.id, version: a.version, active: false}))}
            </View>
          ))}
          {text((m.availability?.total || 0) + ' período(s) · página ' + m.availabilityPage)}
          <View style={s.row}>
            {button('Anteriores', () => m.setAvailabilityPage((n) => n - 1), m.availabilityPage === 1 || m.loading)}
            {button(
              'Mais períodos',
              () => m.setAvailabilityPage((n) => n + 1),
              m.loading || !m.availability || m.availabilityPage * 30 >= m.availability.total,
            )}
          </View>
          {form && (
            <View style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
              {text('Disponibilidade', true)}
              {button('Janela semanal disponível', () => setForm({...form, kind: 'weekly'}), false, form.kind === 'weekly')}
              {button('Período em que não posso participar', () => setForm({...form, kind: 'unavailable'}), false, form.kind === 'unavailable')}
              {form.kind === 'weekly' ? (
                <View>
                  {text('Dia da semana')}
                  <View style={s.row}>
                    {weekdays.map((d, i) => (
                      <View key={d}>{button(d, () => setForm({...form, weekday: i}), false, form.weekday === i)}</View>
                    ))}
                  </View>
                </View>
              ) : (
                <>
                  {field('Data inicial', form.startDate, (v) => setForm({...form, startDate: v}), 10)}
                  {field('Data final', form.endDate, (v) => setForm({...form, endDate: v}), 10)}
                </>
              )}
              {field('Horário inicial', form.startTime, (v) => setForm({...form, startTime: v}), 5)}
              {field('Horário final', form.endTime, (v) => setForm({...form, endTime: v}), 5)}
              {field('Motivo particular (opcional)', form.reason, (v) => setForm({...form, reason: v}), 500, true)}
              {text(
                'Horário da igreja: ' + zone + '. Alterar disponibilidade não cancela uma confirmação existente. Avise a liderança ou solicite substituição.',
              )}
              {button('Salvar disponibilidade', () => void save())}
              {button('Voltar', () => setForm(null))}
            </View>
          )}
        </>
      )}
    </View>
  );
}
const s = StyleSheet.create({
  row: {flexDirection: 'row', flexWrap: 'wrap', gap: 8},
  button: {minHeight: 46, borderWidth: 1, borderRadius: 10, padding: 12, justifyContent: 'center', marginVertical: 5},
  input: {borderWidth: 1, borderRadius: 10, padding: 12, fontSize: 16},
  card: {borderWidth: 1, borderRadius: 16, padding: 18, marginVertical: 12},
});
