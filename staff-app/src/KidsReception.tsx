import {useCallback, useEffect, useMemo, useState} from 'react';
import {ActivityIndicator, Pressable, ScrollView, Share, Text, TextInput, View} from 'react-native';
import {CameraView, useCameraPermissions} from 'expo-camera';
import {getRandomBytes, randomUUID} from 'expo-crypto';
import QRCode from 'qrcode';
import {supabase} from './supabase';
import {kidsPage} from './kids';
import {colors, ui} from './theme';
import type {Unit} from './api';
import type {KidsOperationsPage} from '../../shared/contract/kids.ts';
import {receiptCode, receptionError} from '../../shared/kids-reception.ts';
import KidsPassFlow from './KidsPassFlow';
import KidsChildPhoto from './KidsChildPhoto';

type Admission = {id: string; name: string; birthDate: string; guardians: {id: string; name: string}[]};
type Guardian = {id: string; name: string; relationship: string; arrived: boolean};

/** QR Code desenhado com quadradinhos (sem biblioteca gráfica). */
function Qr({value, size = 220}: {value: string; size?: number}) {
  const matrix = useMemo(() => {
    const q = QRCode.create(value, {errorCorrectionLevel: 'M'});
    const n = q.modules.size,
      rows: boolean[][] = [];
    for (let y = 0; y < n; y++) rows.push(Array.from({length: n}, (_, x) => !!q.modules.get(x, y)));
    return rows;
  }, [value]);
  const cell = Math.floor(size / (matrix.length + 4));
  return (
    <View accessibilityLabel="QR Code do comprovante" style={{padding: cell * 2, backgroundColor: '#fff', alignSelf: 'center', borderRadius: 12}}>
      {matrix.map((row, y) => (
        <View key={y} style={{flexDirection: 'row'}}>
          {row.map((on, x) => (
            <View key={x} style={{width: cell, height: cell, backgroundColor: on ? '#163d2f' : '#fff'}} />
          ))}
        </View>
      ))}
    </View>
  );
}
function Ghost({label, onPress}: {label: string; onPress: () => void}) {
  return (
    <Pressable accessibilityRole="button" style={ui.ghost} onPress={onPress}>
      <Text style={ui.ghostText}>{label}</Text>
    </Pressable>
  );
}
function Check({on, label, onPress}: {on: boolean; label: string; onPress: () => void}) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{checked: on}}
      onPress={onPress}
      style={{flexDirection: 'row', gap: 10, alignItems: 'center', paddingVertical: 6}}
    >
      <View
        style={{
          width: 24,
          height: 24,
          borderRadius: 7,
          borderWidth: 2,
          borderColor: colors.brand,
          backgroundColor: on ? colors.brand : 'transparent',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {on && <Text style={{color: '#fff', fontWeight: '900'}}>✓</Text>}
      </View>
      <Text style={[ui.copy, {color: colors.text, flex: 1}]}>{label}</Text>
    </Pressable>
  );
}

/** Vinha Equipe › Recepção Kids: entrada com comprovante (QR) e saída conferindo responsável e comprovante. */
export default function KidsReception({org, unit, back, embedded = false}: {org: string; unit: Unit; back: () => void; embedded?: boolean}) {
  const [page, setPage] = useState<KidsOperationsPage | null>(null),
    [mode, setMode] = useState<'in' | 'out'>('in'),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const load = useCallback(async () => {
    try {
      setPage(await kidsPage(org, unit.id));
    } catch (e) {
      setError((e as Error).message);
    }
  }, [org, unit.id]);
  useEffect(() => {
    void load();
  }, [load]);
  const session = page?.sessions.find((s) => s.id === page.sessionId);
  return (
    <ScrollView contentContainerStyle={[ui.pad, {paddingTop: embedded ? 12 : 24}]} keyboardShouldPersistTaps="handled">
      {!embedded && <Text style={ui.over}>RECEPÇÃO KIDS · {unit.name.toUpperCase()}</Text>}
      {!embedded && <Text style={ui.h1}>{mode === 'in' ? 'Entrada' : 'Saída'}</Text>}
      {!!error && <Text style={ui.error}>{error}</Text>}
      {!!notice && <Text style={{color: colors.ok, fontWeight: '700'}}>{notice}</Text>}
      {!page ? (
        <ActivityIndicator color={colors.brand} />
      ) : !page.sessionId || session?.status !== 'open' ? (
        <Text style={ui.copy}>Nenhuma sessão aberta agora. A coordenação abre a sessão em Configurar Kids ou no painel.</Text>
      ) : (
        <>
          <Text style={ui.copy}>
            {session.name} · {page.items.filter((i) => i.status === 'present').length} criança(s) presente(s)
          </Text>
          <View style={{flexDirection: 'row', gap: 8}}>
            {(['in', 'out'] as const).map((m) => (
              <Pressable
                key={m}
                accessibilityRole="button"
                accessibilityState={{selected: mode === m}}
                onPress={() => {
                  setMode(m);
                  setNotice('');
                  setError('');
                }}
                style={[ui.chip, mode === m && ui.chipOn]}
              >
                <Text style={{color: mode === m ? '#fff' : colors.text, fontWeight: '800'}}>{m === 'in' ? 'Registrar entrada' : 'Registrar saída'}</Text>
              </Pressable>
            ))}
          </View>
          <KidsPassFlow
            org={org}
            unit={unit.id}
            done={(m) => {
              setNotice(m);
              void load();
            }}
            fail={setError}
          />
          <Text style={[ui.over, {marginTop: 8}]}>SEM QR CODE DA RESERVA</Text>
          {mode === 'in' ? (
            <CheckIn
              org={org}
              unit={unit.id}
              page={page}
              done={(m) => {
                setNotice(m);
                void load();
              }}
              fail={setError}
            />
          ) : (
            <CheckOut
              org={org}
              unit={unit.id}
              page={page}
              done={(m) => {
                setNotice(m);
                void load();
              }}
              fail={setError}
            />
          )}
        </>
      )}
      {!embedded && <Ghost label="Voltar" onPress={back} />}
    </ScrollView>
  );
}

function CheckIn({org, unit, page, done, fail}: {org: string; unit: string; page: KidsOperationsPage; done: (m: string) => void; fail: (m: string) => void}) {
  const [q, setQ] = useState(''),
    [found, setFound] = useState<Admission[]>([]),
    [child, setChild] = useState<Admission | null>(null),
    [guardian, setGuardian] = useState(''),
    [group, setGroup] = useState(''),
    [checked, setChecked] = useState(false),
    [busy, setBusy] = useState(false),
    [receipt, setReceipt] = useState<{code: string; child: string} | null>(null);
  useEffect(() => {
    let live = true;
    if (q.trim().length < 2 || !supabase) return setFound([]);
    const t = setTimeout(() => {
      void supabase!.rpc('kids_admission_choices', {p_org: org, p_unit: unit, p_session: page.sessionId, p_search: q.trim()}).then((r) => {
        if (live && !r.error) setFound(((r.data as {items?: Admission[]})?.items || []) as Admission[]);
      });
    }, 300);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [q, org, unit, page.sessionId]);
  async function save() {
    if (!child || !guardian || !group || !checked || !supabase) return;
    setBusy(true);
    fail('');
    const code = receiptCode(getRandomBytes(32));
    const r = await supabase.rpc('kids_operations_save', {
      p_org: org,
      p_unit: unit,
      p_request: randomUUID(),
      p_action: 'checkin',
      p_id: randomUUID(),
      p_version: 0,
      p_data: {sessionId: page.sessionId, groupId: group, profileId: child.id, guardianId: guardian, identityConfirmed: true, receiptSecret: code},
    });
    setBusy(false);
    if (r.error) return fail(receptionError(r.error.message));
    setReceipt({code, child: child.name});
    done(child.name.split(' ')[0] + ' entrou. Entregue o comprovante ao responsável.');
    setChild(null);
    setQ('');
    setGuardian('');
    setChecked(false);
  }
  if (receipt)
    return (
      <View style={[ui.card, {borderColor: colors.gold, borderWidth: 2, gap: 12}]}>
        <Text style={ui.h2}>Comprovante de {receipt.child.split(' ')[0]}</Text>
        <Text style={ui.copy}>
          O responsável fotografa este QR Code ou recebe pelo WhatsApp. Na saída, a recepção lê o código. Sem ele, só a coordenação libera.
        </Text>
        <Qr value={receipt.code} />
        <Pressable
          accessibilityRole="button"
          style={ui.primary}
          onPress={() => void Share.share({message: `Comprovante Kids de ${receipt.child}. Mostre na saída:\n${receipt.code}`})}
        >
          <Text style={ui.primaryText}>Enviar comprovante</Text>
        </Pressable>
        <Ghost label="Próxima criança" onPress={() => setReceipt(null)} />
      </View>
    );
  return (
    <View style={{gap: 10}}>
      {!child ? (
        <>
          <TextInput
            style={ui.input}
            placeholder="Nome da criança"
            placeholderTextColor={colors.muted}
            value={q}
            onChangeText={setQ}
            maxLength={80}
            autoFocus
          />
          {found.map((c) => (
            <Pressable
              key={c.id}
              accessibilityRole="button"
              onPress={() => {
                setChild(c);
                setGuardian(c.guardians.length === 1 ? c.guardians[0]!.id : '');
              }}
              style={ui.card}
            >
              <Text style={ui.h2}>{c.name}</Text>
              <Text style={ui.copy}>{c.guardians.length} responsável(is) autorizado(s)</Text>
            </Pressable>
          ))}
          {q.trim().length >= 2 && !found.length && <Text style={ui.copy}>Ninguém encontrado (ou já entrou nesta sessão).</Text>}
        </>
      ) : (
        <View style={[ui.card, {gap: 10}]}>
          <Text style={ui.h2}>{child.name}</Text>
          <Text style={ui.label}>Quem trouxe</Text>
          {child.guardians.map((g) => (
            <Check key={g.id} on={guardian === g.id} label={g.name} onPress={() => setGuardian(g.id)} />
          ))}
          <Text style={ui.label}>Sala</Text>
          <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
            {page.groups.map((g) => (
              <Pressable
                key={g.id}
                accessibilityRole="radio"
                accessibilityState={{checked: group === g.id}}
                onPress={() => setGroup(g.id)}
                style={[ui.chip, group === g.id && ui.chipOn]}
              >
                <Text style={{color: group === g.id ? '#fff' : colors.text, fontWeight: '700'}}>
                  {g.room} · {g.className} ({g.occupied}/{g.capacity})
                </Text>
              </Pressable>
            ))}
          </View>
          <Check on={checked} label="Conferi a identidade de quem trouxe a criança" onPress={() => setChecked(!checked)} />
          <Pressable
            accessibilityRole="button"
            disabled={busy || !guardian || !group || !checked}
            style={[ui.primary, (busy || !guardian || !group || !checked) && {opacity: 0.5}]}
            onPress={() => void save()}
          >
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Registrar entrada</Text>}
          </Pressable>
          <Ghost label="Trocar criança" onPress={() => setChild(null)} />
        </View>
      )}
    </View>
  );
}

function CheckOut({org, unit, page, done, fail}: {org: string; unit: string; page: KidsOperationsPage; done: (m: string) => void; fail: (m: string) => void}) {
  const [q, setQ] = useState(''),
    [pick, setPick] = useState<{id: string; name: string; version: number} | null>(null),
    [guardians, setGuardians] = useState<Guardian[]>([]),
    [guardian, setGuardian] = useState(''),
    [checked, setChecked] = useState(false),
    [code, setCode] = useState(''),
    [scanning, setScanning] = useState(false),
    [busy, setBusy] = useState(false),
    [permission, requestPermission] = useCameraPermissions();
  useEffect(() => {
    let live = true;
    setGuardians([]);
    setGuardian('');
    if (!pick || !supabase) return;
    void supabase.rpc('kids_pickup_guardians', {p_org: org, p_unit: unit, p_attendance: pick.id}).then((r) => {
      if (!live || r.error) return;
      const list = ((r.data as {items?: Guardian[]})?.items || []) as Guardian[];
      setGuardians(list);
      setGuardian(list.find((g) => g.arrived)?.id || '');
    });
    return () => {
      live = false;
    };
  }, [pick, org, unit]);
  const present = page.items.filter((i) => i.status === 'present' && (!q.trim() || i.name.toLowerCase().includes(q.trim().toLowerCase())));
  async function save() {
    if (!pick || !guardian || !checked || !supabase) return;
    const secret = code.trim().toLowerCase();
    if (!/^[a-f0-9]{64}$/.test(secret)) return fail('Leia o QR Code do comprovante ou cole o código completo.');
    setBusy(true);
    fail('');
    const r = await supabase.rpc('kids_operations_save', {
      p_org: org,
      p_unit: unit,
      p_request: randomUUID(),
      p_action: 'checkout',
      p_id: pick.id,
      p_version: pick.version,
      p_data: {guardianId: guardian, identityConfirmed: true, receiptSecret: secret},
    });
    setBusy(false);
    if (r.error) return fail(receptionError(r.error.message));
    const d = r.data as {ok?: boolean; remainingAttempts?: number; version?: number};
    if (d.ok === false) {
      setPick({...pick, version: d.version || pick.version + 1});
      setCode('');
      return fail(`Comprovante não confere. Restam ${d.remainingAttempts} tentativa(s); depois só a coordenação libera.`);
    }
    done(pick.name.split(' ')[0] + ' saiu com o responsável conferido.');
    setPick(null);
    setCode('');
    setChecked(false);
  }
  if (scanning)
    return (
      <View style={{height: 360, borderRadius: 16, overflow: 'hidden'}}>
        {permission?.granted ? (
          <CameraView
            style={{flex: 1}}
            facing="back"
            barcodeScannerSettings={{barcodeTypes: ['qr']}}
            onBarcodeScanned={(s) => {
              const m = /[a-f0-9]{64}/i.exec(s.data || '');
              if (m) {
                setCode(m[0].toLowerCase());
                setScanning(false);
              }
            }}
          />
        ) : (
          <Pressable accessibilityRole="button" style={ui.primary} onPress={() => void requestPermission()}>
            <Text style={ui.primaryText}>Permitir a câmera</Text>
          </Pressable>
        )}
        <Ghost label="Cancelar leitura" onPress={() => setScanning(false)} />
      </View>
    );
  return (
    <View style={{gap: 10}}>
      {!pick ? (
        <>
          <TextInput style={ui.input} placeholder="Buscar criança presente" placeholderTextColor={colors.muted} value={q} onChangeText={setQ} maxLength={80} />
          {!present.length && <Text style={ui.copy}>Nenhuma criança presente {q ? 'com esse nome' : 'agora'}.</Text>}
          {present.map((i) => {
            const g = page.groups.find((x) => x.id === i.groupId);
            return (
              <Pressable
                key={i.id}
                accessibilityRole="button"
                onPress={() => setPick({id: i.id, name: i.name, version: i.version})}
                style={[ui.card, {flexDirection: 'row', gap: 12, alignItems: 'center'}]}
              >
                <KidsChildPhoto org={org} unit={unit} profile={i.profileId} name={i.name} />
                <View style={{flex: 1}}>
                  <Text style={ui.h2}>
                    {i.tag ? 'nº ' + i.tag + ' · ' : ''}
                    {i.name}
                  </Text>
                  <Text style={ui.copy}>{g?.room || 'Sala'}</Text>
                </View>
              </Pressable>
            );
          })}
        </>
      ) : (
        <View style={[ui.card, {gap: 10}]}>
          <Text style={ui.h2}>{pick.name}</Text>
          <Text style={ui.label}>Quem está retirando</Text>
          {!guardians.length && <Text style={ui.copy}>Carregando responsáveis autorizados…</Text>}
          {guardians.map((g) => (
            <Check
              key={g.id}
              on={guardian === g.id}
              label={g.name + (g.relationship ? ' · ' + g.relationship : '') + (g.arrived ? ' (trouxe)' : '')}
              onPress={() => setGuardian(g.id)}
            />
          ))}
          <Text style={ui.label}>Comprovante</Text>
          <Pressable accessibilityRole="button" style={[ui.chip, {alignSelf: 'flex-start'}]} onPress={() => setScanning(true)}>
            <Text style={{color: colors.brand, fontWeight: '800'}}>{code ? '✓ Código lido — ler de novo' : 'Ler QR Code do comprovante'}</Text>
          </Pressable>
          <TextInput
            style={ui.input}
            placeholder="ou cole o código do comprovante"
            placeholderTextColor={colors.muted}
            value={code}
            onChangeText={setCode}
            autoCapitalize="none"
            autoCorrect={false}
            maxLength={80}
          />
          <Check on={checked} label="Conferi a identidade de quem está retirando" onPress={() => setChecked(!checked)} />
          <Pressable
            accessibilityRole="button"
            disabled={busy || !guardian || !checked || !code}
            style={[ui.primary, (busy || !guardian || !checked || !code) && {opacity: 0.5}]}
            onPress={() => void save()}
          >
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Registrar saída</Text>}
          </Pressable>
          <Ghost label="Trocar criança" onPress={() => setPick(null)} />
        </View>
      )}
    </View>
  );
}
