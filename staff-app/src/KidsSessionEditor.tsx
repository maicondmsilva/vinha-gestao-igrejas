import {useEffect, useState} from 'react';
import {ActivityIndicator, Alert, Pressable, Switch, Text, TextInput, View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {colors, ui} from './theme';
import {
  blankSessionForm,
  describeSession,
  durationOptions,
  sessionFormFrom,
  sessionFormProblem,
  sessionPayload,
  weekdayShort,
  type KidsSetup,
  type SessionForm,
} from '../../shared/kids-setup.ts';

type Setup = (action: string, payload: object, done: string) => Promise<boolean>;

function Chip({on, label, onPress}: {on: boolean; label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" accessibilityState={{selected: on}} onPress={onPress} style={[ui.chip, on && ui.chipOn]}>
      <Text style={{color: on ? '#fff' : colors.text, fontWeight: '700'}}>{label}</Text>
    </Pressable>
  );
}
const dateMask = (v: string) =>
  v
    .replace(/\D/g, '')
    .slice(0, 8)
    .replace(/^(\d{2})(\d)/, '$1/$2')
    .replace(/^(\d{2}\/\d{2})(\d)/, '$1/$2');
const timeMask = (v: string) => {
  const d = v.replace(/\D/g, '').slice(0, 4);
  return d.length <= 2 ? d : d.slice(0, 2) + ':' + d.slice(2);
};

/** Responsáveis de uma sala: escolher da equipe ou buscar e incluir uma pessoa nova. */
function RoomStaff({
  data,
  staff,
  onChange,
  setup,
  org,
  unit,
}: {
  data: KidsSetup;
  staff: string[];
  onChange: (s: string[]) => void;
  setup: Setup;
  org: string;
  unit: string;
}) {
  const [q, setQ] = useState(''),
    [found, setFound] = useState<{id: string; name: string}[]>([]);
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
  const team = data.team.filter((t) => t.active);
  return (
    <View style={{gap: 6}}>
      <Text style={[ui.copy, {fontSize: 13, fontWeight: '700'}]}>Responsáveis da sala</Text>
      <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
        {team.map((t) => (
          <Chip
            key={t.id}
            on={staff.includes(t.id)}
            label={t.name.split(' ').slice(0, 2).join(' ')}
            onPress={() => onChange(staff.includes(t.id) ? staff.filter((x) => x !== t.id) : [...staff, t.id])}
          />
        ))}
      </View>
      <TextInput
        style={ui.input}
        placeholder="Incluir pessoa (buscar pelo nome)"
        placeholderTextColor={colors.muted}
        value={q}
        onChangeText={setQ}
        maxLength={80}
      />
      {found.map((p) => (
        <Pressable
          key={p.id}
          accessibilityRole="button"
          style={[ui.chip, {alignSelf: 'flex-start'}]}
          onPress={() => {
            const id = randomUUID();
            void setup(
              'team_save',
              {id, personId: p.id, role: 'teacher', classId: '', canCare: true, active: true},
              p.name.split(' ')[0] + ' incluído na equipe do Kids.',
            ).then((ok) => {
              if (ok) {
                onChange([...staff, id]);
                setQ('');
              }
            });
          }}
        >
          <Text style={{color: colors.brand, fontWeight: '800'}}>+ {p.name}</Text>
        </Pressable>
      ))}
      {q.trim().length >= 2 && !found.length && <Text style={[ui.copy, {fontSize: 12}]}>Só aparecem adultos com conta ativa no app da igreja.</Text>}
    </View>
  );
}

/** Sessões: lista e o formulário único (nome, repetir, horário, salas com turma e responsáveis). */
export default function KidsSessionEditor({data, busy, setup, org, unit}: {data: KidsSetup; busy: boolean; setup: Setup; org: string; unit: string}) {
  const [form, setForm] = useState<SessionForm | null>(null),
    [problem, setProblem] = useState('');
  const roomName = (id: string) => data.rooms.find((r) => r.id === id)?.name || 'Sala';
  const className = (id: string) => data.classes.find((c) => c.id === id)?.name || 'Turma';
  const staffName = (id: string) => data.team.find((t) => t.id === id)?.name.split(' ')[0] || '';
  async function save() {
    if (!form) return;
    const p = sessionFormProblem(form);
    if (p) return setProblem(p);
    setProblem('');
    const payload = sessionPayload(form, (id) => data.rooms.find((r) => r.id === id)?.capacity || 10);
    if (await setup('series_save', payload, form.repeat === 'once' ? 'Sessão salva.' : 'Sessão salva. As próximas datas são criadas sozinhas.')) {
      await setup('series_options', {id: form.id, autoOpen: true}, 'Sessão salva.');
      setForm(null);
    }
  }
  if (form) {
    const f = form,
      set = (x: Partial<SessionForm>) => setForm({...f, ...x}),
      rooms = data.rooms.filter((r) => r.active),
      classes = data.classes.filter((c) => c.active);
    return (
      <View style={[ui.card, {borderColor: colors.gold, borderWidth: 2, gap: 12}]}>
        <Text style={ui.h2}>{f.version ? 'Editar sessão' : 'Nova sessão'}</Text>
        <TextInput
          style={ui.input}
          placeholder="Nome (ex.: Kids domingo manhã)"
          placeholderTextColor={colors.muted}
          value={f.name}
          onChangeText={(v) => set({name: v})}
          maxLength={100}
        />
        <Text style={ui.label}>Repetir</Text>
        <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
          <Chip on={f.repeat === 'once'} label="Não repete" onPress={() => set({repeat: 'once'})} />
          <Chip on={f.repeat === 'weekly'} label="Toda semana" onPress={() => set({repeat: 'weekly'})} />
          {f.repeat === 'legacy' && <Chip on label="Mensal (como estava)" onPress={() => {}} />}
        </View>
        {f.repeat === 'once' ? (
          <TextInput
            style={ui.input}
            placeholder="Data (dd/mm/aaaa)"
            keyboardType="number-pad"
            value={f.date}
            maxLength={10}
            onChangeText={(v) => set({date: dateMask(v)})}
          />
        ) : f.repeat === 'weekly' ? (
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
            {weekdayShort.map((d, i) => (
              <Chip
                key={d}
                on={f.weekdays.includes(i)}
                label={d}
                onPress={() => set({weekdays: f.weekdays.includes(i) ? f.weekdays.filter((x) => x !== i) : [...f.weekdays, i]})}
              />
            ))}
          </View>
        ) : null}
        <View style={{flexDirection: 'row', gap: 10, alignItems: 'center'}}>
          <Text style={ui.label}>Começa às</Text>
          <TextInput style={[ui.input, {width: 90}]} keyboardType="number-pad" value={f.start} onChangeText={(v) => set({start: timeMask(v)})} />
        </View>
        <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
          {durationOptions.map(([m, l]) => (
            <Chip key={m} on={f.duration === m} label={l} onPress={() => set({duration: m})} />
          ))}
        </View>
        <Text style={ui.label}>Salas desta sessão</Text>
        {!rooms.length || !classes.length ? (
          <Text style={ui.copy}>Crie antes uma sala e uma turma (abas Salas e Turmas).</Text>
        ) : (
          rooms.map((r) => {
            const sel = f.rooms.find((x) => x.roomId === r.id);
            return (
              <View key={r.id} style={[ui.card, {gap: 8, borderColor: sel ? colors.brand : colors.line}]}>
                <Pressable
                  accessibilityRole="checkbox"
                  accessibilityState={{checked: !!sel}}
                  onPress={() =>
                    set({rooms: sel ? f.rooms.filter((x) => x.roomId !== r.id) : [...f.rooms, {roomId: r.id, classId: classes[0]!.id, staff: []}]})
                  }
                  style={{flexDirection: 'row', alignItems: 'center', gap: 10}}
                >
                  <View
                    style={{
                      width: 22,
                      height: 22,
                      borderRadius: 6,
                      borderWidth: 2,
                      borderColor: colors.brand,
                      backgroundColor: sel ? colors.brand : 'transparent',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    {sel && <Text style={{color: '#fff', fontWeight: '900', fontSize: 12}}>✓</Text>}
                  </View>
                  <Text style={[ui.h2, {flex: 1}]}>
                    {r.name} <Text style={ui.copy}>· {r.capacity} vagas</Text>
                  </Text>
                </Pressable>
                {sel && (
                  <>
                    <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 6}}>
                      {classes.map((c) => (
                        <Chip
                          key={c.id}
                          on={sel.classId === c.id}
                          label={c.name}
                          onPress={() => set({rooms: f.rooms.map((x) => (x.roomId === r.id ? {...x, classId: c.id} : x))})}
                        />
                      ))}
                    </View>
                    <RoomStaff
                      data={data}
                      staff={sel.staff}
                      onChange={(s) => setForm((cur) => (cur ? {...cur, rooms: cur.rooms.map((x) => (x.roomId === r.id ? {...x, staff: s} : x))} : cur))}
                      setup={setup}
                      org={org}
                      unit={unit}
                    />
                  </>
                )}
              </View>
            );
          })
        )}
        <View style={{flexDirection: 'row', alignItems: 'center', gap: 10}}>
          <Switch accessibilityLabel="Sessão ativa" value={f.active} onValueChange={(v) => set({active: v})} />
          <Text style={[ui.copy, {flex: 1}]}>{f.active ? 'Ativa' : 'Pausada (não cria novas datas)'}</Text>
        </View>
        {!!problem && <Text style={ui.error}>{problem}</Text>}
        <Pressable accessibilityRole="button" disabled={busy} style={[ui.primary, busy && {opacity: 0.6}]} onPress={() => void save()}>
          {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Salvar sessão</Text>}
        </Pressable>
        {!!f.version && (
          <Pressable
            accessibilityRole="button"
            style={ui.ghost}
            onPress={() =>
              Alert.alert('Excluir esta sessão?', 'As datas que já aconteceram continuam no histórico.', [
                {text: 'Cancelar', style: 'cancel'},
                {
                  text: 'Excluir',
                  style: 'destructive',
                  onPress: () => void setup('series_delete', {id: f.id}, 'Sessão excluída.').then((ok) => ok && setForm(null)),
                },
              ])
            }
          >
            <Text style={[ui.ghostText, {color: colors.warn}]}>Excluir sessão</Text>
          </Pressable>
        )}
        <Pressable accessibilityRole="button" style={ui.ghost} onPress={() => setForm(null)}>
          <Text style={ui.ghostText}>Cancelar</Text>
        </Pressable>
      </View>
    );
  }
  return (
    <>
      <Text style={ui.over}>SESSÕES</Text>
      {!data.series.length && <Text style={ui.copy}>Nenhuma sessão ainda. Crie a primeira: nome, dia, horário, salas e responsáveis.</Text>}
      {data.series.map((s) => {
        const f = sessionFormFrom(s);
        return (
          <Pressable key={s.id} accessibilityRole="button" onPress={() => setForm(f)} style={[ui.card, {gap: 4}, !s.active && {opacity: 0.6}]}>
            <View style={{flexDirection: 'row', alignItems: 'center'}}>
              <Text style={[ui.h2, {flex: 1}]}>{s.name}</Text>
              <Text style={{color: colors.brand, fontWeight: '800'}}>Editar ›</Text>
            </View>
            <Text style={ui.copy}>
              {describeSession(f)} ·{' '}
              {s.active ? (s.next.length ? 'próxima ' + s.next[0]!.split('-').reverse().slice(0, 2).join('/') : 'sem próximas datas') : 'pausada'}
            </Text>
            {s.rooms.map((r) => (
              <Text key={r.roomId} style={[ui.copy, {fontSize: 13}]}>
                {roomName(r.roomId)} · {className(r.classId)}
                {r.staff?.length ? ' · ' + r.staff.map(staffName).filter(Boolean).join(', ') : s.autoTeam ? ' · equipe automática' : ' · sem responsável'}
              </Text>
            ))}
          </Pressable>
        );
      })}
      <Pressable accessibilityRole="button" style={ui.primary} onPress={() => setForm(blankSessionForm(randomUUID()))}>
        <Text style={ui.primaryText}>+ Nova sessão</Text>
      </Pressable>
    </>
  );
}
