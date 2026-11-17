import {useEffect, useRef, useState} from 'react';
import {ActivityIndicator, Pressable, Text, View} from 'react-native';
import {CameraView, useCameraPermissions} from 'expo-camera';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {colors, ui} from './theme';
import KidsChildPhoto from './KidsChildPhoto';
import {kidsPassCode, receptionError, type KidsPass} from '../../shared/kids-reception.ts';

type Screen =
  | {kind: 'scan'}
  | {kind: 'busy'}
  | {kind: 'ok'; child: string; room: string; tag: number | null; profile: string}
  | {kind: 'stop'; title: string; text: string};

/**
 * Modo totem: o tablet fica na entrada e a família faz a ENTRADA sozinha com o QR Code da reserva do app.
 * O QR só existe para responsável logado no app, e a entrada fica em nome do responsável que reservou.
 * A SAÍDA continua sempre com a equipe, conferindo o adulto e o comprovante.
 * Para sair do totem, a equipe mantém o botão pressionado por 2 segundos.
 */
export default function KidsKiosk({org, unit, unitName, exit}: {org: string; unit: string; unitName: string; exit: () => void}) {
  const [screen, setScreen] = useState<Screen>({kind: 'scan'}),
    [permission, requestPermission] = useCameraPermissions(),
    lock = useRef(false),
    timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => void (timer.current && clearTimeout(timer.current)), []);
  function later(ms = 7000) {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      lock.current = false;
      setScreen({kind: 'scan'});
    }, ms);
  }
  function stop(title: string, text: string) {
    setScreen({kind: 'stop', title, text});
    later(8000);
  }
  async function read(raw: string) {
    const code = kidsPassCode(raw);
    if (!code || !supabase || lock.current) return;
    lock.current = true;
    setScreen({kind: 'busy'});
    const r = await supabase.rpc('kids_pass', {p_org: org, p_unit: unit, p_code: code});
    if (r.error) return stop('Não foi possível ler', receptionError(r.error.message));
    const pass = r.data as KidsPass;
    if (!pass.found) return stop('QR Code não encontrado', 'A reserva foi cancelada ou já foi usada. Procure a recepção.');
    if (pass.attendance?.status === 'present')
      return stop('Para a saída, procure a equipe', 'A retirada é sempre conferida pela equipe da recepção ou da sala.');
    if (pass.attendance) return stop('Reserva já utilizada', 'Esta criança já entrou e saiu nesta sessão. Procure a recepção.');
    if (pass.sessionStatus !== 'open') return stop('Sessão ainda não aberta', 'Aguarde a equipe abrir a sessão ou procure a recepção.');
    const guardian = pass.reservedBy && pass.guardians.some((g) => g.id === pass.reservedBy) ? pass.reservedBy : '';
    if (!guardian) return stop('Procure a recepção', 'A pessoa que fez a reserva não está autorizada para esta criança.');
    const save = await supabase.rpc('kids_operations_save', {
      p_org: org,
      p_unit: unit,
      p_request: randomUUID(),
      p_action: 'checkin',
      p_id: randomUUID(),
      p_version: 0,
      p_data: {sessionId: pass.sessionId, groupId: pass.groupId, profileId: pass.profileId, guardianId: guardian, identityConfirmed: true, receiptSecret: code},
    });
    if (save.error) return stop('Entrada não confirmada', receptionError(save.error.message));
    const after = await supabase.rpc('kids_pass', {p_org: org, p_unit: unit, p_code: code});
    const tag = (after.data as KidsPass | null)?.attendance?.tag ?? null;
    setScreen({kind: 'ok', child: pass.child.split(' ')[0] || pass.child, room: pass.room || 'sala', tag, profile: pass.profileId});
    later();
  }
  return (
    <View style={{flex: 1, backgroundColor: colors.bg, padding: 20, gap: 16}}>
      <View style={{alignItems: 'center', gap: 4}}>
        <Text style={ui.over}>KIDS · {unitName.toUpperCase()}</Text>
        <Text style={[ui.h1, {fontSize: 30, textAlign: 'center'}]}>Bem-vindos!</Text>
        <Text style={[ui.copy, {textAlign: 'center'}]}>Mostre o QR Code da reserva no app da igreja para fazer a entrada.</Text>
      </View>
      <View style={{flex: 1, borderRadius: 24, overflow: 'hidden', backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center'}}>
        {screen.kind === 'scan' &&
          (permission?.granted ? (
            <CameraView
              style={{alignSelf: 'stretch', flex: 1}}
              facing="front"
              barcodeScannerSettings={{barcodeTypes: ['qr']}}
              onBarcodeScanned={(s) => void read(s.data || '')}
            />
          ) : (
            <Pressable accessibilityRole="button" style={ui.primary} onPress={() => void requestPermission()}>
              <Text style={ui.primaryText}>Permitir a câmera</Text>
            </Pressable>
          ))}
        {screen.kind === 'busy' && <ActivityIndicator size="large" color={colors.brand} />}
        {screen.kind === 'ok' && (
          <View style={{alignItems: 'center', gap: 12, padding: 24}}>
            <KidsChildPhoto org={org} unit={unit} profile={screen.profile} name={screen.child} size={120} />
            <Text style={[ui.h1, {fontSize: 34, textAlign: 'center'}]}>Oi, {screen.child}!</Text>
            <Text style={[ui.copy, {fontSize: 20, textAlign: 'center'}]}>Entrada confirmada na {screen.room}.</Text>
            {screen.tag !== null && <Text style={{fontSize: 56, fontWeight: '900', color: colors.brand}}>nº {screen.tag}</Text>}
            <Text style={[ui.copy, {textAlign: 'center'}]}>Peça a etiqueta à equipe. O aviso de entrada chega no seu app.</Text>
          </View>
        )}
        {screen.kind === 'stop' && (
          <View style={{alignItems: 'center', gap: 10, padding: 24}}>
            <Text style={[ui.h1, {textAlign: 'center', color: colors.warn}]}>{screen.title}</Text>
            <Text style={[ui.copy, {fontSize: 18, textAlign: 'center'}]}>{screen.text}</Text>
          </View>
        )}
      </View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Sair do modo totem (manter pressionado)"
        delayLongPress={2000}
        onLongPress={exit}
        style={ui.ghost}
      >
        <Text style={[ui.ghostText, {fontSize: 13}]}>Equipe: mantenha pressionado para sair do totem</Text>
      </Pressable>
    </View>
  );
}
