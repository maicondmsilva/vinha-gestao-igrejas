import {useCallback,useEffect,useState} from 'react';
import {ActivityIndicator,Linking,Pressable,ScrollView,StyleSheet,Switch,Text,TextInput,View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import type {ChurchRpc} from '../../shared/member-church';
import {durationLabel,pastoralKinds,pastoralModes,pastoralStatus} from '../../shared/pastoral';
import {monthShort,initials,whatsappLink} from '../../shared/cell-leader';
import {onBrand} from './experience-model';
import Icon from './Icon';
type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
type Hour={weekday:number;starts:string;ends:string};
export type TeamAttendant={id:string;name:string;role:string;autoConfirm:boolean;durations:number[];kinds:string[];modes:string[];active:boolean;version:number;self:boolean;hours:Hour[]};
type Item={id:string;attendantId:string;attendant:string;person:string;kind:string;mode:string;startsAt:string;endsAt:string;status:string;origin:string;memberAck:boolean;message:string;link:string;notes:string;version:number;address:string};
type Overview={canEdit:boolean;attendants:TeamAttendant[];items:Item[]};
type Found={id:string;name:string;phone?:string};
const week=['dom','seg','ter','qua','qui','sex','sáb'];
const all=[15,30,45,60,90,120];
const hm=(iso:string)=>new Date(iso).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
const dayKey=(iso:string)=>{const t=new Date(iso).toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long'});return t.charAt(0).toUpperCase()+t.slice(1)};
const staffMode=(m:string)=>m==='visita'?'Na casa do membro':pastoralModes[m]||m;
const isoDay=(d:Date)=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');

/** Diz se a pessoa logada atende (ou organiza a agenda) nesta igreja; sem isso o cartão nem aparece. */
export function usePastoralTeam(rpc:ChurchRpc,org:string,unit:string,authenticated:boolean){
 const [data,setData]=useState<Overview|null>(null),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;setData(null);if(!authenticated||!unit)return;
  const from=new Date(Date.now()-864e5).toISOString(),to=new Date(Date.now()+42*864e5).toISOString();
  void Promise.resolve(rpc.rpc('pastoral_staff',{p_org:org,p_unit:unit,p_action:'overview',p_data:{from,to}})).then(r=>{if(!live||r.error)return;const d=r.data as Overview;if(d.attendants.some(a=>a.self)||d.canEdit)setData(d)}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,unit,authenticated,rev]);
 return {data,refresh:()=>setRev(n=>n+1)};
}

/** "Minha agenda de atendimento": pedidos para confirmar, próximos atendimentos, marcar visita e confirmação automática. */
export default function PastoralTeamScreen({rpc,org,unit,team,palette:p}:{rpc:ChurchRpc;org:string;unit:string;team:{data:Overview|null;refresh:()=>void};palette:Palette}){
 const ac=p.accent,onB=onBrand(p.brand),data=team.data;
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[noteFor,setNoteFor]=useState(''),[note,setNote]=useState(''),[declineFor,setDeclineFor]=useState(''),[reason,setReason]=useState(''),[planning,setPlanning]=useState(false);
 const run=useCallback(async(action:string,payload:object,done:string)=>{setBusy(true);setError('');setNotice('');try{const r=await rpc.rpc('pastoral_staff',{p_org:org,p_unit:unit,p_action:action,p_data:payload});if(r.error)throw Error(/slot_taken/.test(r.error.message)?'Esse horário já está ocupado.':/changed/.test(r.error.message)?'A agenda mudou. Atualize e tente de novo.':'Não foi possível concluir agora.');if(done){setNotice(done);team.refresh()}return r.data}catch(e){setError(e instanceof Error?e.message:'Não foi possível.');return null}finally{setBusy(false)}},[rpc,org,unit,team]);
 if(!data)return <ActivityIndicator color={ac} style={{marginTop:30}}/>;
 const mine=data.attendants.filter(a=>a.self),me=mine[0],now=Date.now();
 const pending=data.items.filter(i=>i.status==='requested'),next=data.items.filter(i=>i.status==='confirmed'&&Date.parse(i.endsAt)>now-6*36e5);
 const groups=new Map<string,Item[]>();for(const i of next)groups.set(dayKey(i.startsAt),[...(groups.get(dayKey(i.startsAt))||[]),i]);
 const over=(t:string)=><Text style={[s.over,{color:ac}]}>{t}</Text>;
 const btn=(label:string,press:()=>void,primary=false)=><Pressable accessibilityRole="button" disabled={busy} onPress={press} style={[s.small,primary?{backgroundColor:p.brand}:{borderWidth:1,borderColor:p.line}]}><Text style={{color:primary?onB:p.text,fontWeight:'800'}}>{label}</Text></Pressable>;
 const card=(i:Item)=><View key={i.id} style={[s.card,{backgroundColor:p.surface,borderColor:i.status==='requested'?'#f2a33a':p.line}]}>
  <View style={s.row}><View style={[s.date,{borderColor:ac}]}><Text style={{color:ac,fontWeight:'900',fontSize:16}}>{hm(i.startsAt)}</Text><Text style={{color:ac,fontSize:10,fontWeight:'800'}}>{Math.round((Date.parse(i.endsAt)-Date.parse(i.startsAt))/6e4)} MIN</Text></View>
   <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'900'}}>{i.person}</Text><Text style={{color:p.muted}}>{pastoralKinds[i.kind]||i.kind} · {staffMode(i.mode)}{mine.length>1||!me?' · com '+i.attendant:''}</Text>
    {i.status==='requested'&&<Text style={{color:p.muted,fontSize:12}}>{new Date(i.startsAt).toLocaleDateString('pt-BR',{weekday:'short',day:'2-digit',month:'2-digit'})}</Text>}</View></View>
  {!!i.message&&<Text style={[s.quote,{color:p.text,borderLeftColor:ac}]}>“{i.message}”</Text>}
  {!!i.address&&<Pressable accessibilityRole="link" onPress={()=>void Linking.openURL('https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(i.address))}><Text style={{color:ac,fontWeight:'700',marginTop:8}}>📍 {i.address}</Text></Pressable>}
  {i.origin==='staff'&&!i.memberAck&&<Text style={{color:p.muted,fontSize:12,marginTop:6}}>O membro ainda não confirmou presença.</Text>}
  {!!i.notes&&noteFor!==i.id&&<Text style={{color:p.muted,fontSize:12,marginTop:6}}>Tem anotação sigilosa.</Text>}
  <View style={s.actions}>
   {i.status==='requested'&&(declineFor===i.id?<View style={{flex:1}}><TextInput value={reason} onChangeText={setReason} maxLength={200} placeholder="Motivo (opcional, o membro vê)" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/><View style={{flexDirection:'row',gap:8}}>{btn('Recusar pedido',()=>void run('decide',{id:i.id,version:i.version,decision:'decline',reason:reason.trim(),link:''},'Pedido recusado. O membro pode escolher outro dia.').then(()=>{setDeclineFor('');setReason('')}),true)}{btn('Voltar',()=>setDeclineFor(''))}</View></View>
    :<>{btn('Confirmar',()=>void run('decide',{id:i.id,version:i.version,decision:'confirm',reason:'',link:''},'Confirmado. O membro recebe o aviso no app.'),true)}{btn('Recusar',()=>{setDeclineFor(i.id);setReason('')})}</>)}
   {i.status==='confirmed'&&Date.parse(i.startsAt)<now&&<>{btn('Realizado',()=>void run('status',{id:i.id,version:i.version,status:'done',reason:''},'Marcado como realizado.'),true)}{btn('Não veio',()=>void run('status',{id:i.id,version:i.version,status:'missed',reason:''},'Marcado como não compareceu.'))}</>}
   {i.status==='confirmed'&&Date.parse(i.startsAt)>now&&btn('Desmarcar',()=>void run('status',{id:i.id,version:i.version,status:'cancelled',reason:''},'Atendimento desmarcado.'))}
   {data.attendants.find(a=>a.id===i.attendantId)?.self&&btn(noteFor===i.id?'Fechar':'Anotação',()=>{setNoteFor(noteFor===i.id?'':i.id);setNote(i.notes)})}
  </View>
  {noteFor===i.id&&<View><TextInput value={note} onChangeText={setNote} multiline maxLength={4000} placeholder="Só você e quem tem permissão veem." placeholderTextColor={p.muted} style={[s.input,{minHeight:90,color:p.text,borderColor:p.line,backgroundColor:p.bg,textAlignVertical:'top'}]}/>{btn('Salvar anotação sigilosa',()=>void run('note',{id:i.id,version:i.version,notes:note},'Anotação salva.').then(()=>setNoteFor('')),true)}</View>}
 </View>;

 return <View>
  <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/>
   <Text style={[s.coverOver,{color:onB}]}>AGENDA DE ATENDIMENTO</Text><Text style={[s.coverTitle,{color:onB}]}>{me?me.name:'Atendimentos da igreja'}</Text>
   <View style={s.stats}>{[[String(pending.length),'para confirmar'],[String(next.filter(i=>new Date(i.startsAt).toDateString()===new Date().toDateString()).length),'hoje'],[String(next.length),'próximos']].map(([n,l])=><View key={l} style={[s.stat,{backgroundColor:onB+'1a'}]}><Text style={{color:onB,fontSize:22,fontWeight:'900'}}>{n}</Text><Text style={{color:onB,opacity:.85,fontSize:12}}>{l}</Text></View>)}</View></View>
  {!!error&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:ac}]}>{error}</Text>}
  {!!notice&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:p.line,backgroundColor:p.surface}]}>{notice}</Text>}
  <Pressable accessibilityRole="button" onPress={()=>setPlanning(!planning)} style={[s.primary,{backgroundColor:planning?p.surface:p.brand,borderColor:p.line,borderWidth:planning?1:0}]}><Icon name="plus" color={planning?p.text:onB} size={20}/><Text style={{color:planning?p.text:onB,fontWeight:'900'}}>{planning?'Fechar':'Marcar visita ou atendimento'}</Text></Pressable>
  {planning&&<ScheduleVisit rpc={rpc} org={org} unit={unit} attendants={data.attendants.filter(a=>a.active&&(a.self||data.canEdit))} palette={p} busy={busy} run={run} done={()=>setPlanning(false)}/>}

  {over('PARA CONFIRMAR')}
  {pending.length?pending.map(card):<Text style={{color:p.muted,marginBottom:10}}>{me?.autoConfirm?'Sua confirmação automática está ligada: os pedidos já chegam confirmados.':'Nenhum pedido aguardando.'}</Text>}
  {over('PRÓXIMOS ATENDIMENTOS')}
  {groups.size?[...groups].map(([d,list])=><View key={d}><Text style={{color:p.text,fontWeight:'900',marginBottom:6}}>{d}</Text>{list.map(card)}</View>):<Text style={{color:p.muted}}>Nada marcado nas próximas semanas.</Text>}

  {mine.map(a=><SelfSettings key={a.id+':'+a.version} rpc={rpc} org={org} unit={unit} attendant={a} palette={p} done={(m:string)=>{setNotice(m);team.refresh()}} fail={setError}/>)}
 </View>;
}

function SelfSettings({rpc,org,unit,attendant:a,palette:p,done,fail}:{rpc:ChurchRpc;org:string;unit:string;attendant:TeamAttendant;palette:Palette;done:(m:string)=>void;fail:(m:string)=>void}){
 const ac=p.accent,[auto,setAuto]=useState(a.autoConfirm),[durations,setDurations]=useState<number[]>(a.durations),[busy,setBusy]=useState(false);
 const save=async(nextAuto:boolean,nextDur:number[])=>{if(!nextDur.length)return;setBusy(true);try{const r=await rpc.rpc('pastoral_self_settings',{p_org:org,p_unit:unit,p_attendant:a.id,p_auto:nextAuto,p_durations:nextDur,p_version:a.version});if(r.error)throw Error();done(nextAuto!==a.autoConfirm?(nextAuto?'Confirmação automática ligada.':'Confirmação automática desligada: você confirma cada pedido.'):'Durações atualizadas.')}catch{fail('Não foi possível salvar. Atualize e tente de novo.');setAuto(a.autoConfirm);setDurations(a.durations)}finally{setBusy(false)}};
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:p.line,marginTop:18}]}>
  <Text style={[s.over,{color:ac,marginTop:0}]}>MINHA AGENDA{a.role?' · '+a.role.toUpperCase():''}</Text>
  <View style={[s.row,{justifyContent:'space-between'}]}><View style={{flex:1}}><Text style={{color:p.text,fontWeight:'900'}}>Confirmação automática</Text><Text style={{color:p.muted,fontSize:13}}>{auto?'Ligada: o pedido do membro já entra confirmado.':'Desligada: você confirma cada pedido.'}</Text></View>
   <Switch accessibilityLabel="Confirmação automática" value={auto} disabled={busy} onValueChange={v=>{setAuto(v);void save(v,durations)}} trackColor={{true:ac,false:p.line}} thumbColor="#fff"/></View>
  <Text style={{color:p.text,fontWeight:'900',marginTop:14}}>Durações que o membro pode escolher</Text>
  <View style={[s.wrap,{marginTop:8}]}>{all.map(d=>{const on=durations.includes(d);return <Pressable key={d} accessibilityRole="checkbox" accessibilityState={{checked:on}} disabled={busy||(on&&durations.length===1)} onPress={()=>{const n=on?durations.filter(x=>x!==d):[...durations,d].sort((x,y)=>x-y);setDurations(n);void save(auto,n)}} style={[s.chip,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{durationLabel(d)}</Text></Pressable>})}</View>
  <Text style={{color:p.text,fontWeight:'900',marginTop:14}}>Horários da semana</Text>
  <Text style={{color:p.muted,marginTop:4,lineHeight:20}}>{a.hours.length?a.hours.map(h=>`${week[h.weekday]} ${h.starts}–${h.ends}`).join(' · '):'Nenhum horário cadastrado.'}</Text>
  <Text style={{color:p.muted,fontSize:12,marginTop:6}}>Horários e bloqueios de dias são ajustados no painel (Pessoas › Agenda pastoral).</Text>
 </View>;
}

function ScheduleVisit({rpc,org,unit,attendants,palette:p,busy,run,done}:{rpc:ChurchRpc;org:string;unit:string;attendants:TeamAttendant[];palette:Palette;busy:boolean;run:(a:string,d:object,m:string)=>Promise<unknown>;done:()=>void}){
 const ac=p.accent,onB=onBrand(p.brand);
 const [att,setAtt]=useState(attendants[0]?.id||''),[q,setQ]=useState(''),[found,setFound]=useState<Found[]>([]),[person,setPerson]=useState<Found|null>(null),[kind,setKind]=useState('visita'),[mode,setMode]=useState('visita'),[minutes,setMinutes]=useState(60),[day,setDay]=useState(''),[slots,setSlots]=useState<{startsAt:string;label:string}[]>([]),[slot,setSlot]=useState(''),[message,setMessage]=useState(''),[id,setId]=useState(randomUUID());
 const a=attendants.find(x=>x.id===att);
 useEffect(()=>{let live=true;if(q.trim().length<2){setFound([]);return}const t=setTimeout(()=>void Promise.resolve(rpc.rpc('pastoral_people',{p_org:org,p_unit:unit,p_query:q.trim()})).then(r=>{if(live&&!r.error)setFound(((r.data as {items?:Found[]})?.items)||[])}),300);return()=>{live=false;clearTimeout(t)}},[q,rpc,org,unit]);
 useEffect(()=>{let live=true;setSlot('');setSlots([]);if(!att||!day)return;void run('slots',{attendant:att,minutes,date:day},'').then(d=>{if(live)setSlots(((d as {slots?:{startsAt:string;label:string}[]})?.slots)||[])});return()=>{live=false}},[att,day,minutes]);
 const next14=Array.from({length:14},(_,i)=>{const d=new Date();d.setDate(d.getDate()+i);return d});
 const chip=(label:string,on:boolean,press:()=>void,key=label)=><Pressable key={key} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={press} style={[s.chip,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{label}</Text></Pressable>;
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:ac}]}>
  {attendants.length>1&&<><Text style={[s.label,{color:p.text}]}>Quem vai atender</Text><View style={s.wrap}>{attendants.map(x=>chip(x.name,att===x.id,()=>setAtt(x.id),x.id))}</View></>}
  <Text style={[s.label,{color:p.text}]}>Com quem</Text>
  {person?<View style={[s.row,{marginBottom:6}]}><View style={[s.avatar,{backgroundColor:ac+'22'}]}><Text style={{color:ac,fontWeight:'900'}}>{initials(person.name)}</Text></View><Text style={{color:p.text,fontWeight:'900',flex:1}}>{person.name}</Text>
   {!!person.phone&&!!whatsappLink(person.phone)&&<Pressable accessibilityRole="link" accessibilityLabel={'WhatsApp de '+person.name} onPress={()=>void Linking.openURL(whatsappLink(person.phone!))} style={[s.round,{borderColor:p.line}]}><Icon name="chat" color={ac} size={18}/></Pressable>}
   <Pressable accessibilityRole="button" onPress={()=>setPerson(null)}><Text style={{color:p.muted,fontWeight:'700'}}>trocar</Text></Pressable></View>
  :<><TextInput accessibilityLabel="Buscar membro" value={q} onChangeText={setQ} maxLength={80} placeholder="Digite o nome do membro" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
   {found.map(f=><Pressable key={f.id} accessibilityRole="button" onPress={()=>{setPerson(f);setQ('');setFound([])}} style={[s.found,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>{f.name}</Text></Pressable>)}</>}
  <Text style={[s.label,{color:p.text}]}>Assunto e onde</Text>
  <View style={s.wrap}>{(a?.kinds.includes('visita')?a.kinds:[...(a?.kinds||[]),'visita']).map(k=>chip(pastoralKinds[k]||k,kind===k,()=>{setKind(k);if(k==='visita')setMode('visita')},'k'+k))}</View>
  <View style={[s.wrap,{marginTop:8}]}>{['visita','presencial','online'].map(m=>chip(m==='visita'?'Na casa do membro':pastoralModes[m]||m,mode===m,()=>setMode(m),'m'+m))}</View>
  <View style={[s.wrap,{marginTop:8}]}>{[30,45,60,90,120].map(d=>chip(durationLabel(d),minutes===d,()=>setMinutes(d),'d'+d))}</View>
  <Text style={[s.label,{color:p.text}]}>Dia</Text>
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8}}>{next14.map(d=>{const k=isoDay(d),on=day===k;return <Pressable key={k} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={()=>setDay(k)} style={[s.dayChip,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.muted,fontSize:11,fontWeight:'800'}}>{week[d.getDay()]!.toUpperCase()}</Text><Text style={{color:on?onBrand(ac):p.text,fontWeight:'900',fontSize:18}}>{d.getDate()}</Text><Text style={{color:on?onBrand(ac):p.muted,fontSize:10,fontWeight:'800'}}>{monthShort[d.getMonth()]}</Text></Pressable>})}</ScrollView>
  {!!day&&<View style={[s.wrap,{marginTop:10}]}>{slots.length?slots.map(x=>chip(x.label,slot===x.startsAt,()=>setSlot(x.startsAt),x.startsAt)):<Text style={{color:p.muted}}>Sem horário livre neste dia. Confira seus horários da semana.</Text>}</View>}
  <TextInput accessibilityLabel="Mensagem para o membro" value={message} onChangeText={setMessage} maxLength={500} placeholder="Mensagem para o membro (opcional)" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg,marginTop:12}]}/>
  <Pressable accessibilityRole="button" disabled={busy||!person||!slot} onPress={()=>void run('schedule',{id,attendant:att,person:person!.id,minutes,startsAt:slot,kind,mode,message:message.trim(),link:''},'Marcado! O membro recebe o aviso no app.').then(r=>{if(r){setId(randomUUID());done()}})} style={[s.primary,{backgroundColor:p.brand,opacity:busy||!person||!slot?.5:1}]}><Text style={{color:onB,fontWeight:'900'}}>Marcar e avisar o membro</Text></Pressable>
 </View>;
}
const s=StyleSheet.create({
 cover:{borderRadius:24,padding:22,overflow:'hidden',marginBottom:14},blob:{position:'absolute',width:220,height:220,borderRadius:110,right:-80,top:-90},
 coverOver:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},coverTitle:{fontSize:24,fontWeight:'900',marginTop:6},stats:{flexDirection:'row',gap:8,marginTop:16},stat:{flex:1,borderRadius:16,padding:10},
 over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginTop:16,marginBottom:10},alert:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12,lineHeight:21},
 card:{borderWidth:1,borderRadius:22,padding:14,marginBottom:10},row:{flexDirection:'row',alignItems:'center',gap:12},
 date:{width:62,height:54,borderWidth:2,borderRadius:14,alignItems:'center',justifyContent:'center'},
 quote:{borderLeftWidth:3,paddingLeft:10,marginTop:10,fontStyle:'italic'},actions:{flexDirection:'row',flexWrap:'wrap',gap:8,marginTop:12},
 small:{paddingHorizontal:14,paddingVertical:10,borderRadius:20},primary:{flexDirection:'row',gap:8,borderRadius:16,minHeight:52,alignItems:'center',justifyContent:'center',marginTop:6,marginBottom:6},
 input:{borderWidth:1,borderRadius:14,padding:12,fontSize:15,minHeight:48,marginBottom:8},label:{fontWeight:'800',marginTop:12,marginBottom:8},
 wrap:{flexDirection:'row',flexWrap:'wrap',gap:8},chip:{borderWidth:1,borderRadius:20,paddingHorizontal:14,paddingVertical:9},
 dayChip:{width:58,borderWidth:1,borderRadius:16,paddingVertical:8,alignItems:'center'},avatar:{width:40,height:40,borderRadius:20,alignItems:'center',justifyContent:'center'},
 round:{width:40,height:40,borderRadius:20,borderWidth:1,alignItems:'center',justifyContent:'center'},found:{borderWidth:1,borderRadius:12,padding:12,marginBottom:6},
});
