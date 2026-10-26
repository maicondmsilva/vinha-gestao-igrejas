import {useEffect,useState} from 'react';
import {Platform,Pressable,Text,View} from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import Constants from 'expo-constants';
import type {ChurchRpc} from '../../shared/member-church';
export const pushDeviceKey='vinha.push.device';
export default function PushSettings({rpc,org,unit,onInbox}:{rpc:ChurchRpc;org:string;unit:string;onInbox:()=>void}){
 const [notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 useEffect(()=>{const l=Notifications.addNotificationResponseReceivedListener(()=>onInbox());return()=>l.remove()},[onInbox]);
 async function enable(){if(busy)return;setBusy(true);try{
 const r=await rpc.rpc('member_services',{p_org:org,p_unit:unit,p_action:'push_status'}),config=r.data as {configured:boolean;project:string;application:string};if(r.error||!config?.configured)throw Error('A igreja ainda está configurando os alertas deste aplicativo.');
 if(!Device.isDevice)throw Error('Ative os alertas em um celular físico.');
 if(Constants.expoConfig?.extra?.eas?.projectId!==config.project||Constants.expoConfig?.android?.package!==config.application)throw Error('Esta instalação ainda não tem a configuração de push do ministério.');
 if(Platform.OS==='android')await Notifications.setNotificationChannelAsync('igreja',{name:'Avisos da igreja',importance:Notifications.AndroidImportance.DEFAULT});
 const permissions=await Notifications.requestPermissionsAsync();if(permissions.status!=='granted')throw Error('Permissão não concedida. Você pode alterar isso nos ajustes do celular.');
 const token=await Notifications.getExpoPushTokenAsync({projectId:config.project});let id=await SecureStore.getItemAsync(pushDeviceKey);if(!id){id=Crypto.randomUUID();await SecureStore.setItemAsync(pushDeviceKey,id)}
 const save=await rpc.rpc('member_services',{p_org:org,p_unit:unit,p_action:'push_register',p_data:{id,token:token.data,project:config.project,application:config.application}});if(save.error||!(save.data as {ok?:boolean})?.ok)throw Error('Não foi possível registrar o celular. Confira a conta e tente novamente.');setNotice('Alertas ativados neste celular. O conteúdo privado aparece somente ao abrir sua conta.');
 }catch(e){setNotice(e instanceof Error?e.message:'Não foi possível ativar.')}finally{setBusy(false)}}
 async function disable(){setBusy(true);try{const id=await SecureStore.getItemAsync(pushDeviceKey);if(id){const r=await rpc.rpc('member_services',{p_org:org,p_unit:unit,p_action:'push_disable',p_data:{id}});if(r.error)throw Error();await SecureStore.deleteItemAsync(pushDeviceKey)}setNotice('Alertas desativados neste celular.')}catch{setNotice('Desativação não confirmada. Tente novamente.')}finally{setBusy(false)}}
 return <View style={{padding:16,backgroundColor:'#e5eee9',borderRadius:12,marginVertical:16}}><Text style={{color:'#173e2e',fontSize:18,fontWeight:'700'}}>Alertas no celular</Text><Text style={{color:'#173e2e',marginVertical:10}}>Receba um aviso quando houver novidades. Textos privados não aparecem na tela bloqueada.</Text>{notice&&<Text accessibilityRole="alert" style={{color:'#173e2e'}}>{notice}</Text>}{[['Ativar alertas',enable],['Desativar neste celular',disable]].map(([label,action])=><Pressable key={String(label)} accessibilityRole="button" disabled={busy} onPress={()=>void (action as ()=>Promise<void>)()} style={{padding:14}}><Text style={{color:'#173e2e',fontWeight:'700'}}>{String(label)}</Text></Pressable>)}</View>;
}
