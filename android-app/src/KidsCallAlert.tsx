import {useCallback,useEffect,useState} from 'react';
import {AppState,Pressable,StyleSheet,Text,View} from 'react-native';
import {supabase} from './supabase';
import {onBrand} from './experience-model';
import {openKidsCalls,type KidsCall} from '../../shared/kids-calls';

type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent:string};

/** Chamado da sala Kids: aparece no topo do app até o responsável responder (consulta a cada 20 s com o app aberto). */
export function KidsCallAlert({org,authenticated,palette:p}:{org:string;authenticated:boolean;palette:Palette}){
 const [items,setItems]=useState<KidsCall[]>([]),[present,setPresent]=useState<{profile:string;child:string;tag:number|null;room:string}[]>([]),[busy,setBusy]=useState(''),[done,setDone]=useState('');
 const load=useCallback(async()=>{if(!supabase||!authenticated)return;const r=await supabase.rpc('member_kids_call',{p_org:org,p_action:'list'});if(!r.error)setItems(openKidsCalls(((r.data as {items?:KidsCall[]})?.items||[])));const k=await supabase.rpc('member_kids_present',{p_org:org});if(!k.error)setPresent(((k.data as {items?:typeof present})?.items||[]))},[org,authenticated]);
 useEffect(()=>{setItems([]);setPresent([]);if(!authenticated)return;void load();let t=setInterval(()=>void load(),20000);
  const sub=AppState.addEventListener('change',st=>{clearInterval(t);if(st==='active'){void load();t=setInterval(()=>void load(),20000)}});
  return()=>{clearInterval(t);sub.remove()}},[load,authenticated]);
 async function answer(id:string,a:'coming'|'ok'){
  setBusy(id);const r=await supabase!.rpc('member_kids_call',{p_org:org,p_action:'answer',p_id:id,p_answer:a});setBusy('');
  if(!r.error){setDone(a==='coming'?'Avisamos a sala que você está a caminho.':'Avisamos a sala que você viu o recado.');setItems(x=>x.filter(i=>i.id!==id))}
 }
 const tags=present.length?<View style={[s.tag,{backgroundColor:p.surface,borderColor:p.line}]}>{present.map(k=><Text key={k.profile} style={{color:p.text,fontWeight:'700'}}><Text style={{color:p.accent,fontWeight:'900'}}>Kids · etiqueta nº {k.tag??'—'}</Text>  {k.child}{k.room?' · '+k.room:''}</Text>)}</View>:null;
 if(!items.length)return <View>{done?<Text accessibilityRole="alert" style={[s.done,{color:p.text,borderColor:p.line}]}>{done}</Text>:null}{tags}</View>;
 return <View>{tags}{items.map(c=><View key={c.id} accessibilityRole="alert" style={[s.card,{backgroundColor:p.surface,borderColor:p.accent}]}>
  <Text style={[s.over,{color:p.accent}]}>SALA KIDS · AGORA</Text>
  <Text style={{color:p.text,fontWeight:'900',fontSize:18}}>A equipe chamou você para {c.child}</Text>
  <Text style={{color:p.text,marginTop:4,lineHeight:21}}>Motivo: {c.reasonText}{c.message?' — '+c.message:''}.</Text>
  <View style={s.row}>
   <Pressable accessibilityRole="button" disabled={busy===c.id} onPress={()=>void answer(c.id,'coming')} style={[s.btn,{backgroundColor:p.brand,opacity:busy===c.id?.6:1}]}><Text style={{color:onBrand(p.brand),fontWeight:'900'}}>Estou indo</Text></Pressable>
   <Pressable accessibilityRole="button" disabled={busy===c.id} onPress={()=>void answer(c.id,'ok')} style={[s.btn,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>Vi o recado</Text></Pressable>
  </View>
 </View>)}</View>;
}
const s=StyleSheet.create({card:{borderWidth:2,borderRadius:20,padding:16,marginBottom:12},over:{fontSize:11,fontWeight:'800',letterSpacing:1.6,marginBottom:4},row:{flexDirection:'row',gap:10,marginTop:12},btn:{flex:1,minHeight:48,borderRadius:16,alignItems:'center',justifyContent:'center'},done:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12},tag:{borderWidth:1,borderRadius:14,paddingVertical:10,paddingHorizontal:14,marginBottom:12,gap:4}});
