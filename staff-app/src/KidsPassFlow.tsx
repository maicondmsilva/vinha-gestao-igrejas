import {useState} from 'react';
import {ActivityIndicator, Pressable, Text, View} from 'react-native';
import {CameraView, useCameraPermissions} from 'expo-camera';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {colors, ui} from './theme';
import KidsChildPhoto from './KidsChildPhoto';
import {kidsPassCode, receptionError, type KidsPass} from '../../shared/kids-reception.ts';

/** Leitura do QR Code da reserva: a mesma leitura faz a entrada (se a criança ainda não entrou) ou a saída. */
export default function KidsPassFlow({org, unit, done, fail}: {org: string; unit: string; done: (m: string) => void; fail: (m: string) => void}) {
  const [scanning, setScanning] = useState(false),
    [code, setCode] = useState(''),
    [pass, setPass] = useState<KidsPass | null>(null),
    [guardian, setGuardian] = useState(''),
    [checked, setChecked] = useState(false),
    [busy, setBusy] = useState(false),
    [permission, requestPermission] = useCameraPermissions();
  async function read(raw: string) {
    const c = kidsPassCode(raw);
    if (!c || !supabase || busy) return;
    setScanning(false);
    setBusy(true);
    fail('');
    const r = await supabase.rpc('kids_pass', {p_org: org, p_unit: unit, p_code: c});
    setBusy(false);
    if (r.error) return fail(receptionError(r.error.message));
    const d = r.data as KidsPass;
    if (!d.found) return fail('QR Code não encontrado: a reserva foi cancelada ou a criança já saiu.');
    setCode(c);
    setPass(d);
    setGuardian(d.attendance ? '' : d.reservedBy && d.guardians.some((g) => g.id === d.reservedBy) ? d.reservedBy : '');
    setChecked(false);
  }
  async function confirm() {
    if (!pass || !guardian || !checked || !supabase) return;
    setBusy(true);
    fail('');
    const entering = !pass.attendance;
    const r = await supabase.rpc('kids_operations_save', {
      p_organization: org,
      p_unit: unit,
      p_request: randomUUID(),
      p_action: entering ? 'checkin' : 'checkout',
      p_id: entering ? randomUUID() : pass.attendance!.id,
      p_version: entering ? 0 : pass.attendance!.version,
      p_data: entering
        ? {sessionId: pass.sessionId, groupId: pass.groupId, profileId: pass.profileId, guardianId: guardian, identityConfirmed: true, receiptSecret: code}
        : {guardianId: guardian, identityConfirmed: true, receiptSecret: code},
    });
    setBusy(false);
    if (r.error) return fail(receptionError(r.error.message));
    if ((r.data as {ok?: boolean})?.ok === false) return fail('O QR Code não confere com a entrada desta criança. Chame a coordenação.');
    done(pass.child.split(' ')[0] + (entering ? ' entrou na ' + (pass.room || 'sala') + '.' : ' saiu com o responsável conferido.'));
    setPass(null);
    setCode('');
  }
  if (scanning)
    return (
      <View style={{height: 380, borderRadius: 16, overflow: 'hidden', gap: 8}}>
        {permission?.granted ? (
          <CameraView style={{flex: 1}} facing="back" barcodeScannerSettings={{barcodeTypes: ['qr']}} onBarcodeScanned={(s) => void read(s.data || '')} />
        ) : (
          <Pressable accessibilityRole="button" style={ui.primary} onPress={() => void requestPermission()}>
            <Text style={ui.primaryText}>Permitir a câmera</Text>
          </Pressable>
        )}
        <Pressable accessibilityRole="button" style={ui.ghost} onPress={() => setScanning(false)}>
          <Text style={ui.ghostText}>Cancelar leitura</Text>
        </Pressable>
      </View>
    );
  if (!pass)
    return (
      <Pressable accessibilityRole="button" disabled={busy} style={[ui.primary, {minHeight: 64}]} onPress={() => setScanning(true)}>
        {busy ? <ActivityIndicator color="#fff" /> : <Text style={[ui.primaryText, {fontSize: 18}]}>Ler QR Code da reserva</Text>}
      </Pressable>
    );
  const entering = !pass.attendance,
    out = pass.attendance?.status === 'out';
  return (
    <View style={[ui.card, {borderColor: colors.gold, borderWidth: 2, gap: 10}]}>
      <View style={{flexDirection: 'row', gap: 14, alignItems: 'center'}}>
        <KidsChildPhoto org={org} unit={unit} profile={pass.profileId} name={pass.child} size={84} />
        <View style={{flex: 1}}>
          <Text style={ui.h2}>{pass.child}</Text>
          <Text style={ui.copy}>
            {pass.session} · {pass.room || 'Sala'}
            {pass.attendance?.tag ? ' · nº ' + pass.attendance.tag : ''}
          </Text>
          <Text style={{color: entering ? colors.brand : colors.warn, fontWeight: '800'}}>{out ? 'Já saiu' : entering ? 'Entrada' : 'Saída'}</Text>
        </View>
      </View>
      {!!pass.care && <Text style={[ui.copy, {color: colors.text}]}>Cuidados: {pass.care}</Text>}
      {out ? (
        <Text style={ui.copy}>Esta criança já saiu nesta sessão.</Text>
      ) : (
        <>
          <Text style={ui.label}>{entering ? 'Quem trouxe' : 'Quem está buscando'}</Text>
          {pass.guardians.map((g) => (
            <Pressable
              key={g.id}
              accessibilityRole="radio"
              accessibilityState={{checked: guardian === g.id}}
              onPress={() => setGuardian(g.id)}
              style={[ui.card, {padding: 12, borderColor: guardian === g.id ? colors.brand : colors.line, borderWidth: guardian === g.id ? 2 : 1}]}
            >
              <Text style={{color: colors.text, fontWeight: '800'}}>{g.name}</Text>
              <Text style={ui.copy}>{g.temporary ? 'Responsável temporário até ' + String(g.validUntil).split('-').reverse().join('/') : g.relationship}</Text>
            </Pressable>
          ))}
          <Pressable
            accessibilityRole="checkbox"
            accessibilityState={{checked}}
            onPress={() => setChecked(!checked)}
            style={{flexDirection: 'row', gap: 10, alignItems: 'center'}}
          >
            <View
              style={{
                width: 24,
                height: 24,
                borderRadius: 7,
                borderWidth: 2,
                borderColor: colors.brand,
                backgroundColor: checked ? colors.brand : 'transparent',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {checked && <Text style={{color: '#fff', fontWeight: '900'}}>✓</Text>}
            </View>
            <Text style={[ui.copy, {color: colors.text, flex: 1}]}>
              Conferi a identidade (documento ou rosto) de quem está {entering ? 'trazendo' : 'buscando'}
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            disabled={busy || !guardian || !checked}
            style={[ui.primary, (busy || !guardian || !checked) && {opacity: 0.5}]}
            onPress={() => void confirm()}
          >
            {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>{entering ? 'Confirmar entrada' : 'Confirmar saída'}</Text>}
          </Pressable>
        </>
      )}
      <Pressable accessibilityRole="button" style={ui.ghost} onPress={() => setPass(null)}>
        <Text style={ui.ghostText}>Ler outro QR Code</Text>
      </Pressable>
    </View>
  );
}
