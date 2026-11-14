import {useCallback,useEffect,useRef,useState} from 'react';
import {ActivityIndicator,Linking,Pressable,ScrollView,StyleSheet,Text,TextInput,View,useWindowDimensions} from 'react-native';
import {randomUUID} from 'expo-crypto';
import type {ChurchRpc} from '../../shared/member-church';
import {canCancel,dayLegend,durationLabel,monthGrid,monthTitle,pastoralError,pastoralKinds,pastoralModes,pastoralStatus,shiftMonth,sortAttendants,type DayState,type PastoralAppointment,type PastoralAttendant,type PastoralDay,type PastoralSlot} from '../../shared/pastoral';
import {monthShort,initials} from '../../shared/cell-leader';
import {onBrand} from './experience-model';
import Icon from './Icon';
type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
const weekLetters=['D','S','T','Q','Q','S','S'];
const tone=(state:DayState,ac:string,p:Palette)=>state==='available'?{bg:ac,fg:onBrand(ac),border:ac}:state==='full'?{bg:'#f2a33a33',fg:p.text,border:'#f2a33a'}:state==='none'?{bg:p.line,fg:p.muted,border:p.line}:{bg:'transparent',fg:p.muted,border:'transparent'};
const today=()=>{const d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')};
const when=(iso:string)=>{const d=new Date(iso);return d.toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long'})+' às '+d.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})};

/** "Falar com o pastor": escolher com quem, o motivo e a duração, ver o mês colorido e tocar no dia para ver os horários. */
export default function PastoralBooking({rpc,org,unit,authenticated,palette:p,onLogin}:{rpc:ChurchRpc;org:string;unit:string;authenticated:boolean;palette:Palette;onLogin:()=>void}){
 const {width}=useWindowDimensions(),ac=p.accent,onB=onBrand(p.brand);
 const [list,setList]=useState<PastoralAttendant[]>([]),[linked,setLinked]=useState(true),[mine,setMine]=useState<PastoralAppointment[]>([]),[att,setAtt]=useState(''),[kind,setKind]=useState(''),[mode,setMode]=useState(''),[minutes,setMinutes]=useState(0);
 const [month,setMonth]=useState(today()),[days,setDays]=useState<PastoralDay[]>([]),[day,setDay]=useState(''),[slots,setSlots]=useState<PastoralSlot[]>([]),[slot,setSlot]=useState<PastoralSlot|null>(null),[message,setMessage]=useState('');
 const [loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[reload,setReload]=useState(0),[confirmCancel,setConfirmCancel]=useState('');
 const nonce=useRef(randomUUID()),a=list.find(x=>x.id===att);
 const call=useCallback((action:string,data:object)=>Promise.resolve(rpc.rpc('pastoral_member',{p_org:org,p_unit:unit,p_action:action,p_data:data})),[rpc,org,unit]);
 useEffect(()=>{let live=true;if(!authenticated||!unit)return;setError('');
  void Promise.all([call('attendants',{}),call('mine',{})]).then(([r1,r2])=>{if(!live)return;if(r1.error){setError(pastoralError(r1.error.message));return}const d=r1.data as {items:PastoralAttendant[];linked:boolean};setList(sortAttendants(d.items||[]));setLinked(d.linked);if(!r2.error)setMine(((r2.data as {items?:PastoralAppointment[]})?.items)||[])}).catch(()=>{if(live)setError('Sem conexão. Tente de novo.')});
  return()=>{live=false}},[call,authenticated,unit,reload]);
 useEffect(()=>{if(a){setKind(a.kinds[0]||'');setMode(a.modes[0]||'');setMinutes(a.durations.includes(45)?45:a.durations[0]||0)}setDay('');setSlot(null)},[att]);
 useEffect(()=>{let live=true;if(!a||!minutes)return;setLoading(true);setDays([]);
  void call('month',{attendant:a.id,minutes,month}).then(r=>{if(!live)return;if(r.error)setError(pastoralError(r.error.message));else setDays(((r.data as {days?:PastoralDay[]})?.days)||[])}).finally(()=>{if(live)setLoading(false)});
  return()=>{live=false}},[call,a?.id,minutes,month,reload]);
 useEffect(()=>{let live=true;setSlots([]);setSlot(null);if(!a||!day)return;
  void call('day',{attendant:a.id,minutes,date:day}).then(r=>{if(live&&!r.error)setSlots(((r.data as {slots?:PastoralSlot[]})?.slots)||[])});
  return()=>{live=false}},[call,a?.id,minutes,day]);

 async function request(){if(!a||!slot||busy)return;setBusy(true);setError('');
  try{const r=await call('request',{id:nonce.current,attendant:a.id,minutes,startsAt:slot.startsAt,kind,mode,message:message.trim()});if(r.error)throw Error(pastoralError(r.error.message));
   const st=(r.data as {status?:string})?.status;nonce.current=randomUUID();setNotice(st==='confirmed'?'Horário marcado! Ele já está em "Meus horários".':'Pedido enviado. Você recebe o aviso quando '+a.name.split(' ')[0]+' confirmar.');setSlot(null);setDay('');setMessage('');setReload(n=>n+1)}
  catch(e){setError(e instanceof Error?e.message:'Não foi possível pedir agora.');setReload(n=>n+1)}finally{setBusy(false)}}
 async function act(action:'cancel'|'ack',x:PastoralAppointment){if(busy)return;setBusy(true);setError('');try{const r=await call(action,{id:x.id,version:x.version});if(r.error)throw Error(pastoralError(r.error.message));setNotice(action==='cancel'?'Horário cancelado.':'Presença confirmada. Obrigado!');setConfirmCancel('');setReload(n=>n+1)}catch(e){setError(e instanceof Error?e.message:'Não foi possível.')}finally{setBusy(false)}}

 const chip=(label:string,on:boolean,press:()=>void,key=label)=><Pressable key={key} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={press} style={[s.chip,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{label}</Text></Pressable>;
 const over=(t:string)=><Text style={[s.over,{color:ac}]}>{t}</Text>;
 const cell=Math.min(52,Math.floor((Math.min(width,760)-40-12*2-6*6)/7));
 const upcoming=mine.filter(x=>Date.parse(x.endsAt)>Date.now()&&['requested','confirmed'].includes(x.status)),past=mine.filter(x=>!upcoming.includes(x));

 return <View>
  <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/><View style={[s.blob2,{backgroundColor:onB,opacity:.06}]}/>
   <Text style={[s.coverOver,{color:onB}]}>UM TEMPO PARA CONVERSAR</Text><Text style={[s.coverTitle,{color:onB}]}>Falar com a liderança</Text>
   <Text style={{color:onB,opacity:.88,marginTop:6,lineHeight:22}}>Escolha com quem, veja os dias livres e marque o melhor horário para você.</Text></View>
  {!!error&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:ac}]}>{error}</Text>}
  {!!notice&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:p.line,backgroundColor:p.surface}]}>{notice}</Text>}
  {!authenticated?<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}><Text style={{color:p.muted,lineHeight:22}}>Entre na sua conta para pedir um horário com o pastor ou com a liderança.</Text><Pressable accessibilityRole="button" onPress={onLogin} style={[s.primary,{backgroundColor:p.brand}]}><Text style={{color:onB,fontWeight:'900'}}>Entrar</Text></Pressable></View>
  :<>
  {upcoming.length>0&&<>{over('MEUS HORÁRIOS')}{upcoming.map(x=><View key={x.id} style={[s.block,{backgroundColor:p.surface,borderColor:x.status==='confirmed'?ac:p.line}]}>
   <View style={s.row}><View style={[s.date,{borderColor:ac}]}><Text style={{color:ac,fontWeight:'900',fontSize:18}}>{new Date(x.startsAt).getDate()}</Text><Text style={{color:ac,fontSize:10,fontWeight:'800'}}>{monthShort[new Date(x.startsAt).getMonth()]}</Text></View>
    <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'900'}}>{x.attendant}</Text><Text style={{color:p.muted}}>{when(x.startsAt)}</Text><Text style={{color:p.muted}}>{pastoralKinds[x.kind]||x.kind} · {pastoralModes[x.mode]||x.mode}</Text></View></View>
   <View style={[s.status,{backgroundColor:x.status==='confirmed'?ac+'22':'transparent',borderColor:ac}]}><Text style={{color:ac,fontWeight:'800',fontSize:12}}>{x.origin==='staff'&&!x.memberAck?'A igreja marcou para você':pastoralStatus[x.status]}</Text></View>
   {!!x.link&&x.status==='confirmed'&&<Pressable accessibilityRole="link" onPress={()=>void Linking.openURL(x.link)}><Text style={{color:ac,fontWeight:'800',marginTop:8}}>Entrar na conversa online</Text></Pressable>}
   {x.origin==='staff'&&!x.memberAck&&x.status==='confirmed'&&<Pressable accessibilityRole="button" disabled={busy} onPress={()=>void act('ack',x)} style={[s.primary,{backgroundColor:p.brand}]}><Text style={{color:onB,fontWeight:'900'}}>Confirmar minha presença</Text></Pressable>}
   {canCancel(x)?(confirmCancel===x.id?<View style={{flexDirection:'row',gap:8,marginTop:10}}><Pressable accessibilityRole="button" disabled={busy} onPress={()=>void act('cancel',x)} style={[s.small,{backgroundColor:p.brand}]}><Text style={{color:onB,fontWeight:'800'}}>Sim, cancelar</Text></Pressable><Pressable accessibilityRole="button" onPress={()=>setConfirmCancel('')} style={[s.small,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>Manter</Text></Pressable></View>
    :<Pressable accessibilityRole="button" onPress={()=>setConfirmCancel(x.id)}><Text style={{color:p.muted,fontWeight:'700',marginTop:10}}>Cancelar este horário</Text></Pressable>):<Text style={{color:p.muted,fontSize:12,marginTop:8}}>Faltam menos de 12 h: para desmarcar, fale com a secretaria.</Text>}
  </View>)}</>}

  {!linked&&<Text style={[s.alert,{color:p.text,borderColor:p.line}]}>Seu cadastro ainda não está vinculado à igreja. Complete em Meu perfil para poder pedir horários.</Text>}
  {over('1 · COM QUEM VOCÊ QUER CONVERSAR')}
  {!list.length&&<Text style={{color:p.muted,marginBottom:14}}>Ainda não há horários de atendimento abertos nesta igreja.</Text>}
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:10,paddingBottom:6}}>{list.map(x=>{const on=x.id===att;return <Pressable key={x.id} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={()=>setAtt(x.id)} style={[s.person,{borderColor:on?ac:p.line,backgroundColor:on?ac+'18':p.surface}]}>
   <View style={[s.avatar,{backgroundColor:on?ac:ac+'22'}]}><Text style={{color:on?onBrand(ac):ac,fontWeight:'900',fontSize:18}}>{initials(x.name)}</Text></View>
   <Text numberOfLines={2} style={{color:p.text,fontWeight:'900',marginTop:8,textAlign:'center'}}>{x.name}</Text><Text style={{color:p.muted,fontSize:12,textAlign:'center'}}>{x.role}</Text>
   {(x.myLeader||x.pastor)&&<Text style={{color:ac,fontSize:11,fontWeight:'800',marginTop:4}}>{x.myLeader?'LÍDER DA SUA CÉLULA':'PASTOR'}</Text>}</Pressable>})}</ScrollView>

  {a&&<>
   {!!a.about&&<Text style={{color:p.muted,marginTop:8,lineHeight:21}}>{a.about}</Text>}
   {over('2 · ASSUNTO, FORMA E DURAÇÃO')}
   <View style={s.wrap}>{a.kinds.map(k=>chip(pastoralKinds[k]||k,kind===k,()=>setKind(k),'k'+k))}</View>
   {a.modes.length>1&&<View style={[s.wrap,{marginTop:8}]}>{a.modes.map(k=>chip(pastoralModes[k]||k,mode===k,()=>setMode(k),'m'+k))}</View>}
   <View style={[s.wrap,{marginTop:8}]}>{a.durations.map(d=>chip(durationLabel(d),minutes===d,()=>{setMinutes(d);setDay('')},'d'+d))}</View>

   {over('3 · ESCOLHA O DIA')}
   <View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
    <View style={s.monthRow}><Pressable accessibilityRole="button" accessibilityLabel="Mês anterior" disabled={month<=today()} onPress={()=>{setMonth(shiftMonth(month,-1));setDay('')}} style={[s.nav,{borderColor:p.line,opacity:month<=today()?.35:1}]}><Text style={{color:p.text,fontSize:20}}>‹</Text></Pressable>
     <Text style={{color:p.text,fontWeight:'900',fontSize:17}}>{monthTitle(month)}</Text>
     <Pressable accessibilityRole="button" accessibilityLabel="Próximo mês" disabled={month>=shiftMonth(today(),2)} onPress={()=>{setMonth(shiftMonth(month,1));setDay('')}} style={[s.nav,{borderColor:p.line,opacity:month>=shiftMonth(today(),2)?.35:1}]}><Text style={{color:p.text,fontSize:20}}>›</Text></Pressable></View>
    <View style={s.week}>{weekLetters.map((l,i)=><Text key={i} style={{width:cell,textAlign:'center',color:p.muted,fontWeight:'800',fontSize:12}}>{l}</Text>)}</View>
    {loading?<ActivityIndicator color={ac} style={{marginVertical:30}}/>:monthGrid(month).map((w,i)=><View key={i} style={s.week}>{w.map((d,j)=>{if(!d)return <View key={j} style={{width:cell,height:cell}}/>;const info=days.find(x=>x.date===d),state:DayState=info?.state||'closed',t=tone(state,ac,p),on=d===day;
     return <Pressable key={j} accessibilityRole="button" accessibilityLabel={d.split('-').reverse().join('/')+': '+(state==='available'?info!.slots+' horários livres':state==='full'?'agenda cheia':state==='none'?'sem atendimento':'indisponível')} accessibilityState={{disabled:state!=='available',selected:on}} disabled={state!=='available'} onPress={()=>setDay(d)}
      style={[s.day,{width:cell,height:cell,backgroundColor:t.bg,borderColor:on?p.text:t.border,borderWidth:on?2.5:1,opacity:state==='past'||state==='closed'?.45:1}]}><Text style={{color:t.fg,fontWeight:state==='available'?'900':'600'}}>{Number(d.slice(8))}</Text></Pressable>})}</View>)}
    <View style={[s.wrap,{marginTop:12,gap:14}]}>{dayLegend.map(([st,label])=>{const t=tone(st,ac,p);return <View key={st} style={{flexDirection:'row',alignItems:'center',gap:6}}><View style={{width:14,height:14,borderRadius:5,backgroundColor:t.bg,borderWidth:1,borderColor:t.border}}/><Text style={{color:p.muted,fontSize:12}}>{label}</Text></View>})}</View>
   </View>

   {!!day&&<>{over('4 · HORÁRIOS LIVRES EM '+day.split('-').reverse().slice(0,2).join('/'))}
    {!slots.length?<Text style={{color:p.muted}}>Os horários deste dia acabaram de ser ocupados. Escolha outro dia.</Text>:<View style={s.wrap}>{slots.map(x=>chip(x.label,slot?.startsAt===x.startsAt,()=>setSlot(x),x.startsAt))}</View>}</>}

   {slot&&<View style={[s.block,{backgroundColor:p.surface,borderColor:ac,marginTop:14}]}>
    <View style={s.row}><View style={[s.date,{borderColor:ac,backgroundColor:ac}]}><Text style={{color:onBrand(ac),fontWeight:'900',fontSize:18}}>{Number(day.slice(8))}</Text><Text style={{color:onBrand(ac),fontSize:10,fontWeight:'800'}}>{monthShort[Number(day.slice(5,7))-1]}</Text></View>
     <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'900'}}>{slot.label} · {durationLabel(minutes)}</Text><Text style={{color:p.muted}}>{a.name} · {pastoralKinds[kind]} · {pastoralModes[mode]}</Text></View></View>
    <TextInput accessibilityLabel="Mensagem para quem vai atender (opcional)" value={message} onChangeText={setMessage} maxLength={500} multiline placeholder="Quer adiantar algo? (opcional e sigiloso)" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
    <Pressable accessibilityRole="button" disabled={busy||!linked} onPress={()=>void request()} style={[s.primary,{backgroundColor:p.brand,opacity:busy||!linked?.5:1}]}>{busy?<ActivityIndicator color={onB}/>:<Text style={{color:onB,fontWeight:'900',fontSize:16}}>{a.autoConfirm?'Marcar este horário':'Pedir este horário'}</Text>}</Pressable>
    <Text style={{color:p.muted,fontSize:12,marginTop:8,lineHeight:18}}>{a.autoConfirm?'O horário fica confirmado na hora.':'O pedido fica aguardando a confirmação.'} Você pode cancelar até 12 h antes. Máximo de 2 pedidos em aberto.</Text>
   </View>}
  </>}

  {past.length>0&&<>{over('HISTÓRICO')}{past.slice(0,10).map(x=><View key={x.id} style={[s.histRow,{borderColor:p.line}]}><Icon name="calendar" color={p.muted} size={18}/><Text style={{color:p.text,flex:1}}>{x.attendant} · {new Date(x.startsAt).toLocaleDateString('pt-BR')}</Text><Text style={{color:p.muted,fontSize:12}}>{pastoralStatus[x.status]}</Text></View>)}</>}
  </>}
 </View>;
}
const s=StyleSheet.create({
 cover:{borderRadius:24,padding:22,overflow:'hidden',marginBottom:14},blob:{position:'absolute',width:220,height:220,borderRadius:110,right:-80,top:-90},blob2:{position:'absolute',width:130,height:130,borderRadius:65,left:-50,bottom:-60},
 coverOver:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},coverTitle:{fontSize:25,fontWeight:'900',marginTop:6},
 over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginTop:14,marginBottom:10},alert:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12,lineHeight:21},
 block:{borderWidth:1,borderRadius:22,padding:16,marginBottom:12},row:{flexDirection:'row',alignItems:'center',gap:12},
 date:{width:50,height:54,borderWidth:2,borderRadius:14,alignItems:'center',justifyContent:'center'},
 status:{alignSelf:'flex-start',borderWidth:1,borderRadius:14,paddingHorizontal:10,paddingVertical:4,marginTop:10},
 person:{width:140,borderWidth:1.5,borderRadius:22,padding:12,alignItems:'center'},avatar:{width:56,height:56,borderRadius:28,alignItems:'center',justifyContent:'center'},
 wrap:{flexDirection:'row',flexWrap:'wrap',gap:8},chip:{borderWidth:1,borderRadius:20,paddingHorizontal:14,paddingVertical:9},
 monthRow:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',marginBottom:12},nav:{width:40,height:40,borderRadius:20,borderWidth:1,alignItems:'center',justifyContent:'center'},
 week:{flexDirection:'row',justifyContent:'space-between',marginBottom:6},day:{borderRadius:14,alignItems:'center',justifyContent:'center'},
 input:{borderWidth:1,borderRadius:14,padding:12,fontSize:15,minHeight:70,textAlignVertical:'top',marginTop:12},
 primary:{borderRadius:16,minHeight:52,alignItems:'center',justifyContent:'center',marginTop:12},small:{paddingHorizontal:14,paddingVertical:10,borderRadius:20},
 histRow:{flexDirection:'row',alignItems:'center',gap:10,borderBottomWidth:1,paddingVertical:10},
});
