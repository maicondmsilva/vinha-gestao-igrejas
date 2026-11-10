import {useEffect, useState} from 'react';
import {ActivityIndicator, Platform, Pressable, ScrollView, StatusBar as NativeStatusBar, Text, TextInput, View} from 'react-native';
import {StatusBar} from 'expo-status-bar';
import type {Session} from '@supabase/supabase-js';
import {configured, supabase} from './src/supabase';
import {compat, ministries, myAccess, type Ministry, type Unit} from './src/api';
import type {StaffUnitAccess} from '../shared/contract/staff.ts';
import {staffRoleLabel as roleLabel} from '../shared/contract/staff.ts';
import type {CompatResponse} from '../shared/contract/apps.ts';
import {colors, ui} from './src/theme';
import PushComposer from './src/PushComposer';
import TicketScanner from './src/TicketScanner';

type Screen = 'home' | 'push' | 'tickets';

export default function App() {
  const [session, setSession] = useState<Session | null>(null),
    [ready, setReady] = useState(!supabase),
    [version, setVersion] = useState<CompatResponse | null>(null);
  // The platform can retire an old build before an API change reaches it (offline: keep working).
  useEffect(() => {
    void compat().then(setVersion);
  }, []);
  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({data}) => {
      setSession(data.session);
      setReady(true);
    });
    const {data} = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);
  return (
    // Top inset: status bar height on Android, notch area on iOS.
    <View style={[ui.screen, {paddingTop: Platform.OS === 'android' ? NativeStatusBar.currentHeight || 24 : 48}]}>
      <StatusBar style="dark" />
      {version?.status === 'update_required' ? (
        <View style={ui.pad}>
          <Text style={ui.over}>VINHA EQUIPE</Text>
          <Text style={ui.h1}>Atualize o aplicativo</Text>
          <Text style={ui.copy}>{version.message}</Text>
        </View>
      ) : !configured ? (
        <View style={ui.pad}>
          <Text style={ui.h1}>Vinha Equipe</Text>
          <Text style={ui.copy}>Este aplicativo ainda não foi configurado com o servidor da Vinha.</Text>
        </View>
      ) : !ready ? (
        <ActivityIndicator style={{marginTop: 80}} color={colors.brand} />
      ) : !session ? (
        <Login />
      ) : (
        <>
          {version?.status === 'update_available' && <Text style={[ui.copy, {paddingHorizontal: 20, paddingTop: 8}]}>{version.message}</Text>}
          <Workspace email={session.user.email || ''} />
        </>
      )}
    </View>
  );
}

function Login() {
  const [email, setEmail] = useState(''),
    [password, setPassword] = useState(''),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  async function submit() {
    if (busy || !supabase) return;
    setBusy(true);
    setError('');
    const r = await supabase.auth.signInWithPassword({email: email.trim(), password});
    if (r.error) setError(r.error.message.includes('Invalid') ? 'E-mail ou senha incorretos.' : 'Não foi possível entrar agora.');
    setBusy(false);
  }
  return (
    <ScrollView contentContainerStyle={[ui.pad, {paddingTop: 60}]} keyboardShouldPersistTaps="handled">
      <Text style={ui.over}>VINHA EQUIPE</Text>
      <Text style={ui.h1}>A operação do culto na palma da mão</Text>
      <Text style={ui.copy}>Entre com a mesma conta que você usa no painel da Vinha.</Text>
      <Text style={ui.label}>E-mail</Text>
      <TextInput style={ui.input} autoCapitalize="none" autoComplete="email" keyboardType="email-address" value={email} onChangeText={setEmail} />
      <Text style={ui.label}>Senha</Text>
      <TextInput style={ui.input} secureTextEntry autoComplete="password" value={password} onChangeText={setPassword} onSubmitEditing={() => void submit()} />
      {!!error && <Text style={ui.error}>{error}</Text>}
      <Pressable accessibilityRole="button" style={[ui.primary, busy && {opacity: 0.6}]} disabled={busy} onPress={() => void submit()}>
        {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Entrar</Text>}
      </Pressable>
    </ScrollView>
  );
}

function Workspace({email}: {email: string}) {
  const [list, setList] = useState<Ministry[] | null>(null),
    [error, setError] = useState(''),
    [ministry, setMinistry] = useState<Ministry | null>(null),
    [unit, setUnit] = useState<Unit | null>(null),
    [access, setAccess] = useState<StaffUnitAccess[] | null>(null),
    [screen, setScreen] = useState<Screen>('home');
  const chooseMinistry = (m: Ministry | null) => {
    setAccess(null);
    setUnit(null);
    setMinistry(m);
  };
  useEffect(() => {
    ministries()
      .then((m) => {
        setList(m);
        if (m.length === 1) chooseMinistry(m[0]);
      })
      .catch((e) => setError((e as Error).message));
  }, []);
  // What this person may do in each church comes from the platform (Comunicação → Equipe e fuso horário).
  useEffect(() => {
    if (!ministry) return;
    let live = true;
    myAccess(ministry.organization_id)
      .then((all) => {
        if (!live) return;
        const units = all.filter((u) => u.checkin || u.push);
        setAccess(units);
        setUnit(units.length === 1 ? units[0] : units.find((u) => u.id === ministry.default_unit_id) || null);
      })
      .catch((e) => live && setError((e as Error).message));
    return () => {
      live = false;
    };
  }, [ministry]);
  const here = access?.find((u) => u.id === unit?.id);
  const signOut = () => void supabase?.auth.signOut({scope: 'local'});
  if (error)
    return (
      <View style={ui.pad}>
        <Text style={ui.error}>{error}</Text>
        <Ghost label="Sair" onPress={signOut} />
      </View>
    );
  if (!list) return <ActivityIndicator style={{marginTop: 80}} color={colors.brand} />;
  if (!list.length)
    return (
      <View style={[ui.pad, {paddingTop: 40}]}>
        <Text style={ui.h1}>Nenhuma equipe encontrada</Text>
        <Text style={ui.copy}>{email} não tem função de equipe em nenhum ministério. Peça acesso à secretaria ou à administração da igreja.</Text>
        <Ghost label="Sair" onPress={signOut} />
      </View>
    );
  if (ministry && !access) return <ActivityIndicator style={{marginTop: 80}} color={colors.brand} />;
  if (ministry && access && !access.length)
    return (
      <View style={[ui.pad, {paddingTop: 40}]}>
        <Text style={ui.over}>{ministry.organization_name.toUpperCase()}</Text>
        <Text style={ui.h1}>Sem tarefas liberadas</Text>
        <Text style={ui.copy}>
          Você ainda não pode validar entradas nem enviar push em nenhuma igreja deste ministério. A administração libera em Comunicação → Equipe e fuso
          horário.
        </Text>
        {list.length > 1 && <Ghost label="Trocar ministério" onPress={() => chooseMinistry(null)} />}
        <Ghost label="Sair" onPress={signOut} />
      </View>
    );
  if (!ministry || !unit)
    return (
      <ScrollView contentContainerStyle={[ui.pad, {paddingTop: 40}]}>
        <Text style={ui.over}>{ministry ? 'ESCOLHA A IGREJA' : 'ESCOLHA O MINISTÉRIO'}</Text>
        <Text style={ui.h1}>{ministry ? ministry.organization_name : 'Onde você vai servir hoje?'}</Text>
        {(ministry ? access || [] : list).map((item) => {
          const id = 'organization_id' in item ? item.organization_id : item.id,
            name = 'organization_name' in item ? item.organization_name : item.name;
          return (
            <Pressable
              key={id}
              accessibilityRole="button"
              style={ui.card}
              onPress={() => (ministry ? setUnit(item as Unit) : chooseMinistry(item as Ministry))}
            >
              <Text style={ui.h2}>{name}</Text>
              {'role' in item && <Text style={ui.copy}>{roleLabel[item.role] || item.role}</Text>}
            </Pressable>
          );
        })}
        {ministry && list.length > 1 && <Ghost label="Trocar ministério" onPress={() => chooseMinistry(null)} />}
        <Ghost label="Sair" onPress={signOut} />
      </ScrollView>
    );
  if (screen === 'push') return <PushComposer org={ministry.organization_id} unit={unit} units={ministry.units} back={() => setScreen('home')} />;
  if (screen === 'tickets') return <TicketScanner org={ministry.organization_id} unit={unit} back={() => setScreen('home')} />;
  return (
    <ScrollView contentContainerStyle={[ui.pad, {paddingTop: 30}]}>
      <Text style={ui.over}>{ministry.organization_name.toUpperCase()}</Text>
      <Text style={ui.h1}>{unit.name}</Text>
      <Text style={ui.copy}>
        {roleLabel[ministry.role] || ministry.role} · {email}
      </Text>
      {here?.checkin && (
        <Action title="Validar entrada" text="Leia o QR Code de ingressos, inscrições e retiradas de vendas." onPress={() => setScreen('tickets')} />
      )}
      {here?.push && <Action title="Enviar push" text="Avise o ministério, a igreja local ou as igrejas que você atende." onPress={() => setScreen('push')} />}
      <Ghost label="Trocar igreja ou ministério" onPress={() => (list.length > 1 ? chooseMinistry(null) : setUnit(null))} />
      <Ghost label="Sair" onPress={signOut} />
    </ScrollView>
  );
}

function Action({title, text, onPress}: {title: string; text: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" style={[ui.card, {borderLeftWidth: 5, borderLeftColor: colors.gold}]} onPress={onPress}>
      <Text style={ui.h2}>{title} →</Text>
      <Text style={ui.copy}>{text}</Text>
    </Pressable>
  );
}

export function Ghost({label, onPress}: {label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" style={ui.ghost} onPress={onPress}>
      <Text style={ui.ghostText}>{label}</Text>
    </Pressable>
  );
}
