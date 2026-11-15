import {useCallback, useEffect, useState} from 'react';
import {ActivityIndicator, Alert, Pressable, ScrollView, Switch, Text, TextInput, View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {colors, ui} from './theme';
import type {Unit} from './api';
import {
  describeSeries,
  kidsRuleLabels,
  kidsSetupError,
  kidsTeamRoles,
  openBeforeOptions,
  seriesProblem,
  weekdayShort,
  type KidsSeries,
  type KidsSeriesRoom,
  type KidsSetup,
  type KidsTeamRole,
  type KidsReportRow,
  occupancy,
  rotationLetter,
  sessionTimes,
} from '../../shared/kids-setup.ts';

type Tab = 'sessions' | 'team' | 'rooms' | 'classes';
const tabs: [Tab, string][] = [
  ['sessions', 'Sessões'],
  ['team', 'Equipe'],
  ['rooms', 'Salas'],
  ['classes', 'Turmas'],
];
const today = () => new Date().toISOString().slice(0, 10);
const fmt = (iso: string) => new Date(iso).toLocaleString('pt-BR', {weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit'});
const timeMask = (v: string) => {
  const d = v.replace(/\D/g, '').slice(0, 4);
  return d.length <= 2 ? d : d.slice(0, 2) + ':' + d.slice(2);
};

function Chip({on, label, onPress}: {on: boolean; label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" accessibilityState={{selected: on}} onPress={onPress} style={[ui.chip, on && ui.chipOn]}>
      <Text style={{color: on ? '#fff' : colors.text, fontWeight: '700'}}>{label}</Text>
    </Pressable>
  );
}
function Ghost({label, onPress}: {label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" style={ui.ghost} onPress={onPress}>
      <Text style={ui.ghostText}>{label}</Text>
    </Pressable>
  );
}

/** Vinha Equipe › Configurar Kids: salas, turmas, equipe fixa (sem precisar de sessão) e sessões que se repetem. */
export default function KidsSetupScreen({org, unit, back, embedded = false}: {org: string; unit: Unit; back: () => void; embedded?: boolean}) {
  const [data, setData] = useState<KidsSetup | null>(null),
    [tab, setTab] = useState<Tab>('sessions'),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const load = useCallback(async () => {
    if (!supabase) return;
    const r = await supabase.rpc('kids_setup', {p_org: org, p_unit: unit.id, p_action: 'overview', p_data: {}});
    if (r.error) setError(kidsSetupError(r.error.message));
    else setData(r.data as KidsSetup);
  }, [org, unit.id]);
  useEffect(() => {
    void load();
  }, [load]);
  const setup = async (action: string, payload: object, done: string) => {
    if (!supabase) return false;
    setBusy(true);
    setError('');
    setNotice('');
    const r = await supabase.rpc('kids_setup', {p_org: org, p_unit: unit.id, p_action: action, p_data: payload});
    setBusy(false);
    if (r.error) {
      setError(kidsSetupError(r.error.message));
      return false;
    }
    setNotice(done);
    await load();
    return true;
  };
  const op = async (action: string, id: string, version: number, payload: object, done: string) => {
    if (!supabase) return false;
    setBusy(true);
    setError('');
    setNotice('');
    const r = await supabase.rpc('kids_operations_save', {
      p_org: org,
      p_unit: unit.id,
      p_request: randomUUID(),
      p_action: action,
      p_id: id,
      p_version: version,
      p_data: payload,
    });
    setBusy(false);
    if (r.error) {
      setError(kidsSetupError(r.error.message));
      return false;
    }
    if (done) setNotice(done);
    await load();
    return true;
  };
  return (
    <ScrollView contentContainerStyle={[ui.pad, {paddingTop: embedded ? 12 : 24}]} keyboardShouldPersistTaps="handled">
      {!embedded && <Text style={ui.over}>KIDS · {unit.name.toUpperCase()}</Text>}
      {!embedded && <Text style={ui.h1}>Configurar Kids</Text>}
      <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
        {tabs.map(([k, l]) => (
          <Chip key={k} on={tab === k} label={l} onPress={() => setTab(k)} />
        ))}
      </View>
      {!!error && (
        <Text accessibilityRole="alert" style={ui.error}>
          {error}
        </Text>
      )}
      {!!notice && <Text style={{color: colors.ok, fontWeight: '700'}}>{notice}</Text>}
      {!data ? (
        <ActivityIndicator color={colors.brand} />
      ) : tab === 'rooms' ? (
        <Rooms data={data} busy={busy} op={op} setup={setup} />
      ) : tab === 'classes' ? (
        <Classes data={data} busy={busy} op={op} setup={setup} />
      ) : tab === 'team' ? (
        <Team data={data} busy={busy} setup={setup} org={org} unit={unit.id} />
      ) : (
        <Sessions
          data={data}
          busy={busy}
          setup={setup}
          op={op}
          report={async () => {
            const r = await supabase!.rpc('kids_setup', {p_org: org, p_unit: unit.id, p_action: 'report', p_data: {}});
            return ((r.data as {items?: KidsReportRow[]})?.items || []) as KidsReportRow[];
          }}
        />
      )}
      {!embedded && <Ghost label="Voltar" onPress={back} />}
    </ScrollView>
  );
}

type Op = (action: string, id: string, version: number, payload: object, done: string) => Promise<boolean>;
type Setup = (action: string, payload: object, done: string) => Promise<boolean>;

/** Confirmação antes de excluir; com histórico, explica que só dá para desativar. */
function confirmDelete(what: string, run: () => void) {
  Alert.alert('Excluir ' + what + '?', 'Não dá para desfazer. Só é possível porque ainda não há lançamentos.', [
    {text: 'Cancelar', style: 'cancel'},
    {text: 'Excluir', style: 'destructive', onPress: run},
  ]);
}

function ItemActions({locked, busy, editing, onEdit, onDelete}: {locked?: boolean; busy: boolean; editing: boolean; onEdit: () => void; onDelete: () => void}) {
  return (
    <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center'}}>
      {!editing && (
        <Pressable accessibilityRole="button" disabled={busy} onPress={onEdit} style={ui.chip}>
          <Text style={{color: colors.brand, fontWeight: '800'}}>Editar</Text>
        </Pressable>
      )}
      {locked ? (
        <Text style={[ui.copy, {fontSize: 12}]}>Tem histórico: desative em vez de excluir.</Text>
      ) : (
        <Pressable accessibilityRole="button" disabled={busy} onPress={onDelete} style={[ui.chip, {borderColor: colors.warn}]}>
          <Text style={{color: colors.warn, fontWeight: '800'}}>Excluir</Text>
        </Pressable>
      )}
    </View>
  );
}

function Rooms({data, busy, op, setup}: {data: KidsSetup; busy: boolean; op: Op; setup: Setup}) {
  const [form, setForm] = useState<{id: string; version: number; name: string; location: string; capacity: string; active: boolean} | null>(null);
  const blank = {id: '', version: 0, name: '', location: '', capacity: '15', active: true};
  const f = form || blank;
  async function save() {
    const id = f.id || randomUUID();
    if (
      await op(
        'room',
        id,
        f.version,
        {name: f.name.trim(), location: f.location.trim(), capacity: Number(f.capacity), active: f.active},
        f.id ? 'Sala atualizada.' : 'Sala criada.',
      )
    )
      setForm(null);
  }
  const editor = (
    <View style={[ui.card, {borderColor: colors.gold}]}>
      <Text style={ui.h2}>{f.id ? 'Editar sala' : 'Nova sala'}</Text>
      <TextInput
        style={ui.input}
        placeholder="Nome (ex.: Sala Azul)"
        placeholderTextColor={colors.muted}
        value={f.name}
        onChangeText={(v) => setForm({...f, name: v})}
        maxLength={80}
      />
      <TextInput
        style={ui.input}
        placeholder="Local (ex.: 1º andar)"
        placeholderTextColor={colors.muted}
        value={f.location}
        onChangeText={(v) => setForm({...f, location: v})}
        maxLength={80}
      />
      <TextInput
        style={ui.input}
        placeholder="Vagas"
        keyboardType="number-pad"
        value={f.capacity}
        onChangeText={(v) => setForm({...f, capacity: v.replace(/\D/g, '').slice(0, 3)})}
      />
      <Pressable
        accessibilityRole="button"
        disabled={busy || f.name.trim().length < 2 || !Number(f.capacity)}
        style={[ui.primary, (busy || f.name.trim().length < 2 || !Number(f.capacity)) && {opacity: 0.5}]}
        onPress={() => void save()}
      >
        <Text style={ui.primaryText}>{f.id ? 'Salvar sala' : 'Criar sala'}</Text>
      </Pressable>
      {!!form && <Ghost label="Cancelar" onPress={() => setForm(null)} />}
    </View>
  );
  return (
    <>
      <Text style={ui.copy}>Salas físicas do Kids. Não precisam de sessão aberta.</Text>
      {data.rooms.map((r) =>
        form?.id === r.id ? (
          <View key={r.id}>{editor}</View>
        ) : (
          <View key={r.id} style={[ui.card, {gap: 8}]}>
            <View style={{flexDirection: 'row', alignItems: 'center'}}>
              <View style={{flex: 1}}>
                <Text style={ui.h2}>{r.name}</Text>
                <Text style={ui.copy}>
                  {r.location || 'Sem local'} · {r.capacity} vagas{r.active ? '' : ' · inativa'}
                </Text>
              </View>
              <Switch
                accessibilityLabel={'Sala ativa: ' + r.name}
                value={r.active}
                disabled={busy}
                onValueChange={(v) =>
                  void op(
                    'room',
                    r.id,
                    r.version,
                    {name: r.name, location: r.location, capacity: r.capacity, active: v},
                    v ? 'Sala ativada.' : 'Sala desativada.',
                  )
                }
              />
            </View>
            <ItemActions
              locked={r.locked}
              busy={busy}
              editing={false}
              onEdit={() => setForm({id: r.id, version: r.version, name: r.name, location: r.location || '', capacity: String(r.capacity), active: r.active})}
              onDelete={() => confirmDelete('a sala ' + r.name, () => void setup('room_delete', {id: r.id}, 'Sala excluída.'))}
            />
          </View>
        ),
      )}
      {!form?.id && editor}
    </>
  );
}

function Classes({data, busy, op, setup}: {data: KidsSetup; busy: boolean; op: Op; setup: Setup}) {
  const [form, setForm] = useState<{id: string; version: number; name: string; minY: string; maxY: string; active: boolean} | null>(null);
  const f = form || {id: '', version: 0, name: '', minY: '3', maxY: '6', active: true};
  const invalid = busy || f.name.trim().length < 2 || f.minY === '' || f.maxY === '' || Number(f.maxY) < Number(f.minY);
  async function save() {
    if (
      await op(
        'class',
        f.id || randomUUID(),
        f.version,
        {name: f.name.trim(), minMonths: Number(f.minY) * 12, maxMonths: Number(f.maxY) * 12 + 11, active: f.active},
        f.id ? 'Turma atualizada.' : 'Turma criada.',
      )
    )
      setForm(null);
  }
  const editor = (
    <View style={[ui.card, {borderColor: colors.gold}]}>
      <Text style={ui.h2}>{f.id ? 'Editar turma' : 'Nova turma'}</Text>
      <TextInput
        style={ui.input}
        placeholder="Nome (ex.: Maternal)"
        placeholderTextColor={colors.muted}
        value={f.name}
        onChangeText={(v) => setForm({...f, name: v})}
        maxLength={80}
      />
      <View style={{flexDirection: 'row', gap: 8, alignItems: 'center'}}>
        <Text style={ui.copy}>De</Text>
        <TextInput
          style={[ui.input, {width: 70}]}
          keyboardType="number-pad"
          value={f.minY}
          onChangeText={(v) => setForm({...f, minY: v.replace(/\D/g, '').slice(0, 2)})}
        />
        <Text style={ui.copy}>a</Text>
        <TextInput
          style={[ui.input, {width: 70}]}
          keyboardType="number-pad"
          value={f.maxY}
          onChangeText={(v) => setForm({...f, maxY: v.replace(/\D/g, '').slice(0, 2)})}
        />
        <Text style={ui.copy}>anos</Text>
      </View>
      <Pressable accessibilityRole="button" disabled={invalid} style={[ui.primary, invalid && {opacity: 0.5}]} onPress={() => void save()}>
        <Text style={ui.primaryText}>{f.id ? 'Salvar turma' : 'Criar turma'}</Text>
      </Pressable>
      {!!form && <Ghost label="Cancelar" onPress={() => setForm(null)} />}
    </View>
  );
  return (
    <>
      <Text style={ui.copy}>Turmas por idade. A criança entra na turma que combina com a idade dela.</Text>
      {data.classes.map((c) =>
        form?.id === c.id ? (
          <View key={c.id}>{editor}</View>
        ) : (
          <View key={c.id} style={[ui.card, {gap: 8}]}>
            <View style={{flexDirection: 'row', alignItems: 'center'}}>
              <View style={{flex: 1}}>
                <Text style={ui.h2}>{c.name}</Text>
                <Text style={ui.copy}>
                  {Math.floor(c.minMonths / 12)} a {Math.floor(c.maxMonths / 12)} anos{c.active ? '' : ' · inativa'}
                </Text>
              </View>
              <Switch
                accessibilityLabel={'Turma ativa: ' + c.name}
                value={c.active}
                disabled={busy}
                onValueChange={(v) =>
                  void op(
                    'class',
                    c.id,
                    c.version,
                    {name: c.name, minMonths: c.minMonths, maxMonths: c.maxMonths, active: v},
                    v ? 'Turma ativada.' : 'Turma desativada.',
                  )
                }
              />
            </View>
            <ItemActions
              locked={c.locked}
              busy={busy}
              editing={false}
              onEdit={() =>
                setForm({
                  id: c.id,
                  version: c.version,
                  name: c.name,
                  minY: String(Math.floor(c.minMonths / 12)),
                  maxY: String(Math.floor(c.maxMonths / 12)),
                  active: c.active,
                })
              }
              onDelete={() => confirmDelete('a turma ' + c.name, () => void setup('class_delete', {id: c.id}, 'Turma excluída.'))}
            />
          </View>
        ),
      )}
      {!form?.id && editor}
    </>
  );
}

function Team({data, busy, setup, org, unit}: {data: KidsSetup; busy: boolean; setup: Setup; org: string; unit: string}) {
  const [q, setQ] = useState(''),
    [found, setFound] = useState<{id: string; name: string}[]>([]),
    [role, setRole] = useState<KidsTeamRole>('teacher'),
    [classId, setClassId] = useState('');
  useEffect(() => {
    let live = true;
    if (q.trim().length < 2 || !supabase) {
      setFound([]);
      return;
    }
    const t = setTimeout(() => {
      void supabase!.rpc('kids_setup', {p_org: org, p_unit: unit, p_action: 'people', p_data: {q: q.trim()}}).then((r) => {
        if (live && !r.error)
          setFound(((r.data as {items?: {id: string; name: string}[]})?.items || []).filter((p) => !data.team.some((t) => t.personId === p.id)));
      });
    }, 300);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [q, org, unit, data.team]);
  const className = (id: string | null) => data.classes.find((c) => c.id === id)?.name || 'qualquer turma';
  return (
    <>
      <Text style={ui.copy}>Monte a equipe sem precisar de sessão. Nas sessões repetidas, cada pessoa já entra escalada na turma dela.</Text>
      {data.team.map((t) => (
        <View key={t.id} style={[ui.card, {flexDirection: 'row', alignItems: 'center', gap: 8}]}>
          <View style={{flex: 1}}>
            <Text style={ui.h2}>{t.name}</Text>
            <Text style={ui.copy}>
              {kidsTeamRoles.find(([k]) => k === t.role)?.[1]}
              {['teacher', 'assistant'].includes(t.role) ? ' · ' + className(t.classId) : ''}
              {t.active ? '' : ' · afastado'}
              {t.unavailable?.length ? ' · indisponível em ' + t.unavailable.length + ' dia(s)' : ''}
            </Text>
            <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 6}}>
              {[0, 1, 2, 3].map((n) => (
                <Chip
                  key={n}
                  on={(t.rotation || 0) === n}
                  label={n ? 'Equipe ' + rotationLetter(n) : 'Sempre'}
                  onPress={() =>
                    void setup(
                      'team_save',
                      {id: t.id, version: t.version, role: t.role, classId: t.classId || '', canCare: t.canCare, active: t.active, rotation: n || ''},
                      n ? 'Agora serve na equipe ' + rotationLetter(n) + ' do revezamento.' : 'Serve em todas as sessões.',
                    )
                  }
                />
              ))}
            </View>
          </View>
          <Switch
            accessibilityLabel={'Ativo na equipe: ' + t.name}
            value={t.active}
            disabled={busy}
            onValueChange={(v) =>
              void setup(
                'team_save',
                {id: t.id, version: t.version, role: t.role, classId: t.classId || '', canCare: t.canCare, active: v},
                v ? 'Voltou para a equipe.' : 'Afastado da equipe.',
              )
            }
          />
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={'Remover ' + t.name}
            onPress={() => void setup('team_remove', {id: t.id}, 'Removido da equipe.')}
          >
            <Text style={{color: colors.muted, fontWeight: '900', fontSize: 18}}>×</Text>
          </Pressable>
        </View>
      ))}
      <View style={[ui.card, {borderColor: colors.gold}]}>
        <Text style={ui.h2}>Adicionar à equipe</Text>
        <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
          {kidsTeamRoles.map(([k, l]) => (
            <Chip key={k} on={role === k} label={l} onPress={() => setRole(k)} />
          ))}
        </View>
        {['teacher', 'assistant'].includes(role) && (
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
            <Chip on={!classId} label="Qualquer turma" onPress={() => setClassId('')} />
            {data.classes
              .filter((c) => c.active)
              .map((c) => (
                <Chip key={c.id} on={classId === c.id} label={c.name} onPress={() => setClassId(c.id)} />
              ))}
          </View>
        )}
        <TextInput style={ui.input} placeholder="Buscar pelo nome" placeholderTextColor={colors.muted} value={q} onChangeText={setQ} maxLength={80} />
        {found.map((p) => (
          <Pressable
            key={p.id}
            accessibilityRole="button"
            disabled={busy}
            style={[ui.chip, {alignSelf: 'flex-start'}]}
            onPress={() =>
              void setup(
                'team_save',
                {
                  id: randomUUID(),
                  personId: p.id,
                  role,
                  classId: ['teacher', 'assistant'].includes(role) ? classId : '',
                  canCare: role === 'teacher',
                  active: true,
                },
                p.name + ' entrou na equipe.',
              ).then((ok) => ok && setQ(''))
            }
          >
            <Text style={{color: colors.brand, fontWeight: '800'}}>+ {p.name}</Text>
          </Pressable>
        ))}
        <Text style={[ui.copy, {fontSize: 13}]}>Só aparecem adultos com conta ativa no app da igreja.</Text>
      </View>
    </>
  );
}

const blankSeries = (): KidsSeries => ({
  id: randomUUID(),
  name: '',
  rule: 'weekly',
  weekdays: [0],
  monthDay: 1,
  monthWeek: 1,
  startsTime: '09:00',
  durationMinutes: 120,
  validFrom: today(),
  validUntil: null,
  openBeforeHours: 24,
  rooms: [],
  autoTeam: true,
  active: true,
  version: 0,
  next: [],
});

function Sessions({data, busy, setup, op, report}: {data: KidsSetup; busy: boolean; setup: Setup; op: Op; report: () => Promise<KidsReportRow[]>}) {
  const [rows, setRows] = useState<KidsReportRow[] | null>(null),
    [sessionEdit, setSessionEdit] = useState<{id: string; version: number; name: string; date: string; start: string; end: string} | null>(null);
  const hhmm = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'});
  async function saveSession() {
    if (!sessionEdit) return;
    const t = sessionTimes(sessionEdit.date, sessionEdit.start, sessionEdit.end);
    if (!t) return;
    if (await op('session', sessionEdit.id, sessionEdit.version, {name: sessionEdit.name.trim(), ...t}, 'Sessão atualizada.')) setSessionEdit(null);
  }
  const Report = () =>
    rows ? (
      <View style={ui.card}>
        <Text style={ui.h2}>Relatório das últimas sessões</Text>
        {!rows.length && <Text style={ui.copy}>Ainda não há sessões das repetições.</Text>}
        {rows.slice(0, 12).map((r) => (
          <Text key={r.id} style={ui.copy}>
            {new Date(r.startsAt).toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit'})} · {r.series}: {r.children} criança(s) · {occupancy(r)}% ·
            equipe {r.confirmed}/{r.staff} confirmada
          </Text>
        ))}
        <Ghost label="Fechar relatório" onPress={() => setRows(null)} />
      </View>
    ) : (
      <Ghost label="Ver relatório das sessões" onPress={() => void report().then(setRows)} />
    );
  const [edit, setEdit] = useState<KidsSeries | null>(null),
    [problem, setProblem] = useState('');
  async function save() {
    if (!edit) return;
    const p = seriesProblem(edit);
    if (p) return setProblem(p);
    setProblem('');
    const {next: _next, ...payload} = edit;
    if (
      await setup(
        'series_save',
        {...payload, monthDay: edit.monthDay ?? '', monthWeek: edit.monthWeek ?? '', validUntil: edit.validUntil || ''},
        'Repetição salva. As sessões são criadas sozinhas.',
      )
    ) {
      await setup(
        'series_options',
        {id: edit.id, rotationGroups: edit.rotationGroups || 1, autoOpen: !!edit.autoOpen},
        'Repetição salva. As sessões são criadas sozinhas.',
      );
      setEdit(null);
    }
  }
  const toggleRoom = (r: KidsSeriesRoom) => {
    if (!edit) return;
    const has = edit.rooms.some((x) => x.roomId === r.roomId && x.classId === r.classId);
    setEdit({...edit, rooms: has ? edit.rooms.filter((x) => !(x.roomId === r.roomId && x.classId === r.classId)) : [...edit.rooms, r]});
  };
  const roomName = (id: string) => data.rooms.find((r) => r.id === id)?.name || 'Sala';
  const className = (id: string) => data.classes.find((c) => c.id === id)?.name || 'Turma';
  return (
    <>
      <Text style={ui.over}>PRÓXIMAS SESSÕES</Text>
      {!data.sessions.length ? (
        <Text style={ui.copy}>Nenhuma sessão nos próximos dias.</Text>
      ) : (
        data.sessions.map((s) => (
          <View key={s.id} style={ui.card}>
            <Text style={ui.h2}>{s.name}</Text>
            <Text style={ui.copy}>
              {fmt(s.startsAt)} · {s.status === 'open' ? 'aberta' : 'preparando'} · {s.rooms} sala(s) · {s.staff} na equipe
            </Text>
            {!!s.bookableFrom && (
              <Text style={[ui.copy, {fontSize: 13}]}>
                {Date.parse(s.bookableFrom) <= Date.now() ? 'Famílias já podem reservar.' : 'Reservas a partir de ' + fmt(s.bookableFrom)}
              </Text>
            )}
            {sessionEdit?.id === s.id ? (
              <View style={{gap: 8}}>
                <TextInput
                  style={ui.input}
                  placeholder="Nome da sessão"
                  placeholderTextColor={colors.muted}
                  value={sessionEdit.name}
                  maxLength={100}
                  onChangeText={(v) => setSessionEdit({...sessionEdit, name: v})}
                />
                <TextInput
                  style={ui.input}
                  placeholder="Data (dd/mm/aaaa)"
                  placeholderTextColor={colors.muted}
                  keyboardType="number-pad"
                  value={sessionEdit.date}
                  maxLength={10}
                  onChangeText={(v) =>
                    setSessionEdit({
                      ...sessionEdit,
                      date: v
                        .replace(/\D/g, '')
                        .slice(0, 8)
                        .replace(/^(\d{2})(\d)/, '$1/$2')
                        .replace(/^(\d{2}\/\d{2})(\d)/, '$1/$2'),
                    })
                  }
                />
                <View style={{flexDirection: 'row', gap: 8, alignItems: 'center'}}>
                  <TextInput
                    style={[ui.input, {flex: 1}]}
                    placeholder="Início"
                    keyboardType="number-pad"
                    value={sessionEdit.start}
                    onChangeText={(v) => setSessionEdit({...sessionEdit, start: timeMask(v)})}
                  />
                  <Text style={ui.copy}>até</Text>
                  <TextInput
                    style={[ui.input, {flex: 1}]}
                    placeholder="Fim"
                    keyboardType="number-pad"
                    value={sessionEdit.end}
                    onChangeText={(v) => setSessionEdit({...sessionEdit, end: timeMask(v)})}
                  />
                </View>
                {!sessionTimes(sessionEdit.date, sessionEdit.start, sessionEdit.end) && (
                  <Text style={[ui.copy, {fontSize: 13}]}>Informe a data e o horário de início e de fim.</Text>
                )}
                <Pressable
                  accessibilityRole="button"
                  disabled={busy || sessionEdit.name.trim().length < 2 || !sessionTimes(sessionEdit.date, sessionEdit.start, sessionEdit.end)}
                  style={[ui.primary, (busy || !sessionTimes(sessionEdit.date, sessionEdit.start, sessionEdit.end)) && {opacity: 0.5}]}
                  onPress={() => void saveSession()}
                >
                  <Text style={ui.primaryText}>Salvar sessão</Text>
                </Pressable>
                <Ghost label="Cancelar" onPress={() => setSessionEdit(null)} />
              </View>
            ) : (
              <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center'}}>
                {s.status === 'draft' && (
                  <Pressable
                    accessibilityRole="button"
                    disabled={busy}
                    style={ui.chip}
                    onPress={() => void op('sessionState', s.id, s.version, {status: 'open'}, 'Sessão aberta para a entrada das crianças.')}
                  >
                    <Text style={{color: colors.brand, fontWeight: '800'}}>Abrir para entrada</Text>
                  </Pressable>
                )}
                {s.status === 'draft' && !s.locked && (
                  <Pressable
                    accessibilityRole="button"
                    disabled={busy}
                    style={ui.chip}
                    onPress={() =>
                      setSessionEdit({
                        id: s.id,
                        version: s.version,
                        name: s.name,
                        date: new Date(s.startsAt).toLocaleDateString('pt-BR'),
                        start: hhmm(s.startsAt),
                        end: hhmm(s.endsAt),
                      })
                    }
                  >
                    <Text style={{color: colors.brand, fontWeight: '800'}}>Editar</Text>
                  </Pressable>
                )}
                {s.locked ? (
                  <Text style={[ui.copy, {fontSize: 12}]}>Já tem lançamentos: o histórico fica guardado.</Text>
                ) : (
                  <Pressable
                    accessibilityRole="button"
                    disabled={busy}
                    style={[ui.chip, {borderColor: colors.warn}]}
                    onPress={() =>
                      confirmDelete(
                        'a sessão ' + s.name,
                        () => void setup('session_delete', {id: s.id}, s.seriesId ? 'Sessão excluída. A repetição pula essa data.' : 'Sessão excluída.'),
                      )
                    }
                  >
                    <Text style={{color: colors.warn, fontWeight: '800'}}>Excluir</Text>
                  </Pressable>
                )}
              </View>
            )}
          </View>
        ))
      )}
      <Report />
      <Text style={ui.over}>REPETIÇÕES</Text>
      {data.series.map((s) => (
        <Pressable
          key={s.id}
          accessibilityRole="button"
          onPress={() => setEdit({...s, weekdays: [...s.weekdays]})}
          style={[ui.card, !s.active && {opacity: 0.6}]}
        >
          <Text style={ui.h2}>{s.name}</Text>
          <Text style={ui.copy}>
            {describeSeries(s)} · {s.durationMinutes} min · {s.rooms.length} sala(s)
          </Text>
          <Text style={[ui.copy, {fontSize: 13}]}>
            {s.active ? 'Próximas: ' + (s.next.map((d) => d.split('-').reverse().slice(0, 2).join('/')).join(', ') || '—') : 'Pausada'} · famílias reservam{' '}
            {openBeforeOptions.find(([h]) => h === s.openBeforeHours)?.[1] || s.openBeforeHours + ' h antes'}
          </Text>
        </Pressable>
      ))}
      {!edit ? (
        <Pressable accessibilityRole="button" style={ui.primary} onPress={() => setEdit(blankSeries())}>
          <Text style={ui.primaryText}>+ Nova sessão que se repete</Text>
        </Pressable>
      ) : (
        <View style={[ui.card, {borderColor: colors.gold, borderWidth: 2}]}>
          <Text style={ui.h2}>{edit.version ? 'Editar repetição' : 'Nova repetição'}</Text>
          <TextInput
            style={ui.input}
            placeholder="Nome (ex.: Kids domingo manhã)"
            placeholderTextColor={colors.muted}
            value={edit.name}
            onChangeText={(v) => setEdit({...edit, name: v})}
            maxLength={100}
          />
          <Text style={ui.label}>Repete</Text>
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
            {kidsRuleLabels.map(([k, l]) => (
              <Chip
                key={k}
                on={edit.rule === k}
                label={l}
                onPress={() => setEdit({...edit, rule: k, weekdays: k === 'monthly_week' ? edit.weekdays.slice(0, 1) : edit.weekdays})}
              />
            ))}
          </View>
          {(edit.rule === 'weekly' || edit.rule === 'monthly_week') && (
            <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
              {weekdayShort.map((d, i) => (
                <Chip
                  key={d}
                  on={edit.weekdays.includes(i)}
                  label={d}
                  onPress={() =>
                    setEdit({
                      ...edit,
                      weekdays: edit.rule === 'monthly_week' ? [i] : edit.weekdays.includes(i) ? edit.weekdays.filter((x) => x !== i) : [...edit.weekdays, i],
                    })
                  }
                />
              ))}
            </View>
          )}
          {edit.rule === 'monthly_week' && (
            <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
              {[1, 2, 3, 4, 5].map((n) => (
                <Chip key={n} on={edit.monthWeek === n} label={n + 'ª semana'} onPress={() => setEdit({...edit, monthWeek: n})} />
              ))}
            </View>
          )}
          {edit.rule === 'monthly_day' && (
            <TextInput
              style={[ui.input, {width: 110}]}
              keyboardType="number-pad"
              placeholder="Dia"
              value={String(edit.monthDay || '')}
              onChangeText={(v) => setEdit({...edit, monthDay: Math.min(31, Number(v.replace(/\D/g, '')) || 0) || null})}
            />
          )}
          <View style={{flexDirection: 'row', gap: 10, alignItems: 'center'}}>
            <Text style={ui.label}>Início</Text>
            <TextInput
              style={[ui.input, {width: 90}]}
              keyboardType="number-pad"
              value={edit.startsTime}
              onChangeText={(v) => setEdit({...edit, startsTime: timeMask(v)})}
            />
            <Text style={ui.label}>Duração (min)</Text>
            <TextInput
              style={[ui.input, {width: 80}]}
              keyboardType="number-pad"
              value={String(edit.durationMinutes)}
              onChangeText={(v) => setEdit({...edit, durationMinutes: Number(v.replace(/\D/g, '').slice(0, 3)) || 0})}
            />
          </View>
          <Text style={ui.copy}>{describeSeries(edit)}</Text>
          <Text style={ui.label}>Famílias podem reservar</Text>
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
            {openBeforeOptions.map(([h, l]) => (
              <Chip key={h} on={edit.openBeforeHours === h} label={l} onPress={() => setEdit({...edit, openBeforeHours: h})} />
            ))}
          </View>
          <Text style={ui.label}>Salas e turmas</Text>
          {!data.rooms.length || !data.classes.length ? (
            <Text style={ui.copy}>Crie salas e turmas nas abas ao lado.</Text>
          ) : (
            data.rooms
              .filter((r) => r.active)
              .map((r) => (
                <View key={r.id} style={{gap: 6}}>
                  <Text style={{color: colors.text, fontWeight: '700'}}>{r.name}</Text>
                  <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
                    {data.classes
                      .filter((c) => c.active)
                      .map((c) => (
                        <Chip
                          key={c.id}
                          on={edit.rooms.some((x) => x.roomId === r.id && x.classId === c.id)}
                          label={c.name}
                          onPress={() => toggleRoom({roomId: r.id, classId: c.id, capacity: r.capacity, minStaff: 1})}
                        />
                      ))}
                  </View>
                </View>
              ))
          )}
          {!!edit.rooms.length && (
            <Text style={[ui.copy, {fontSize: 13}]}>{edit.rooms.map((x) => roomName(x.roomId) + ' · ' + className(x.classId)).join('  |  ')}</Text>
          )}
          <View style={{flexDirection: 'row', alignItems: 'center', gap: 10}}>
            <Switch accessibilityLabel="Escalar a equipe fixa automaticamente" value={edit.autoTeam} onValueChange={(v) => setEdit({...edit, autoTeam: v})} />
            <Text style={[ui.copy, {flex: 1}]}>Escalar a equipe fixa automaticamente (cada um na turma dele)</Text>
          </View>
          <View style={{flexDirection: 'row', alignItems: 'center', gap: 10}}>
            <Switch accessibilityLabel="Abrir sozinha no horário" value={!!edit.autoOpen} onValueChange={(v) => setEdit({...edit, autoOpen: v})} />
            <Text style={[ui.copy, {flex: 1}]}>Abrir sozinha 30 min antes, se cada sala tiver a equipe mínima</Text>
          </View>
          <Text style={ui.label}>Revezamento da equipe</Text>
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
            {[1, 2, 3].map((n) => (
              <Chip
                key={n}
                on={(edit.rotationGroups || 1) === n}
                label={n === 1 ? 'Sem revezamento' : n + ' equipes (A' + (n === 3 ? ', B e C' : ' e B') + ')'}
                onPress={() => setEdit({...edit, rotationGroups: n})}
              />
            ))}
          </View>
          <View style={{flexDirection: 'row', alignItems: 'center', gap: 10}}>
            <Switch accessibilityLabel="Repetição ativa" value={edit.active} onValueChange={(v) => setEdit({...edit, active: v})} />
            <Text style={[ui.copy, {flex: 1}]}>{edit.active ? 'Ativa' : 'Pausada'}</Text>
          </View>
          {!!problem && <Text style={ui.error}>{problem}</Text>}
          <Pressable accessibilityRole="button" disabled={busy} style={[ui.primary, busy && {opacity: 0.6}]} onPress={() => void save()}>
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Salvar repetição</Text>}
          </Pressable>
          {!!edit.version && (
            <Ghost
              label="Apagar repetição"
              onPress={() =>
                void setup('series_delete', {id: edit.id}, 'Repetição apagada. As sessões já criadas continuam.').then((ok) => ok && setEdit(null))
              }
            />
          )}
          <Ghost label="Cancelar" onPress={() => setEdit(null)} />
        </View>
      )}
    </>
  );
}
