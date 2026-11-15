import {useState} from 'react';
import {Pressable, Text, View} from 'react-native';
import {colors, ui} from './theme';
import type {Unit} from './api';
import KidsReception from './KidsReception';
import KidsBoard from './KidsBoard';
import KidsSetupScreen from './KidsSetupScreen';

type Tab = 'reception' | 'rooms' | 'setup';

/** Vinha Equipe › Kids: uma entrada só, com Recepção (QR), Salas e Configurar (coordenação). */
export default function KidsHub({
  org,
  unit,
  canOperate,
  canConfigure,
  back,
}: {
  org: string;
  unit: Unit;
  canOperate: boolean;
  canConfigure: boolean;
  back: () => void;
}) {
  const tabs: [Tab, string][] = [
    ...(canOperate
      ? ([
          ['reception', 'Recepção'],
          ['rooms', 'Salas'],
        ] as [Tab, string][])
      : []),
    ...(canConfigure ? ([['setup', 'Configurar']] as [Tab, string][]) : []),
  ];
  const [tab, setTab] = useState<Tab>(tabs[0]?.[0] || 'setup');
  return (
    <View style={{flex: 1}}>
      <View style={{paddingHorizontal: 20, paddingTop: 16, gap: 10, backgroundColor: colors.bg}}>
        <View style={{flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'}}>
          <View>
            <Text style={ui.over}>KIDS · {unit.name.toUpperCase()}</Text>
            <Text style={ui.h1}>Kids</Text>
          </View>
          <Pressable accessibilityRole="button" accessibilityLabel="Voltar ao início" onPress={back} style={[ui.chip, {paddingHorizontal: 16}]}>
            <Text style={{color: colors.text, fontWeight: '800'}}>Início</Text>
          </Pressable>
        </View>
        <View
          accessibilityRole="tablist"
          style={{flexDirection: 'row', backgroundColor: colors.surface, borderRadius: 14, borderWidth: 1, borderColor: colors.line, padding: 4}}
        >
          {tabs.map(([k, l]) => (
            <Pressable
              key={k}
              accessibilityRole="tab"
              accessibilityState={{selected: tab === k}}
              onPress={() => setTab(k)}
              style={{
                flex: 1,
                minHeight: 42,
                borderRadius: 10,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: tab === k ? colors.brand : 'transparent',
              }}
            >
              <Text style={{color: tab === k ? '#fff' : colors.text, fontWeight: '800'}}>{l}</Text>
            </Pressable>
          ))}
        </View>
      </View>
      <View style={{flex: 1}}>
        {tab === 'reception' ? (
          <KidsReception org={org} unit={unit} back={back} embedded />
        ) : tab === 'rooms' ? (
          <KidsBoard org={org} unit={unit} back={back} embedded />
        ) : (
          <KidsSetupScreen org={org} unit={unit} back={back} embedded />
        )}
      </View>
    </View>
  );
}
