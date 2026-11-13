import {useCallback,useEffect,useRef,useState} from 'react';
import {ActivityIndicator,Linking,Pressable,ScrollView,StyleSheet,Text,TextInput,View,useWindowDimensions} from 'react-native';
import {randomUUID} from 'expo-crypto';
import type {ChurchRpc} from '../../shared/member-church';
import {attendanceRate,initials,leaderError,monthShort,needsCare,pendingMeetings,phoneDigits,shortDate,upcomingBirthdays,weekDays,whatsappLink,type LeaderMeeting,type LeaderOverview} from '../../shared/cell-leader';
import {onBrand} from './experience-model';
import Icon from './Icon';
type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
export type LeaderCell={id:string;name:string;leader:boolean};

/** Células em que a pessoa logada é líder (ou tem permissão de relatório). Lista vazia esconde a entrada no app. */
export function useLeaderCells(rpc:ChurchRpc,org:string,unit:string,authenticated:boolean){
 const [cells,setCells]=useState<LeaderCell[]>([]);
 useEffect(()=>{let live=true;setCells([]);if(!authenticated||!unit)return;
  void Promise.resolve(rpc.rpc('member_cell_leader',{p_org:org,p_unit:unit,p_cell:null,p_action:'mine',p_data:{}})).then(r=>{if(live&&!r.error)setCells(((r.data as {items?:LeaderCell[]})?.items)||[])}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,unit,authenticated]);
 return cells;
}

type Report={meeting:LeaderMeeting;present:string[];visitors:{name:string;phone:string}[];notes:string;visitorName:string;visitorPhone:string};
const prompts=['Teve testemunho','Pedido de oração','Alguém aceitou Jesus','Precisamos de visita','Clima de família'];
const today=()=>{const d=new Date(),z=(n:number)=>String(n).padStart(2,'0');return d.getFullYear()+'-'+z(d.getMonth()+1)+'-'+z(d.getDate())};
const shift=(iso:string,days:number)=>{const [y,m,d]=iso.split('-').map(Number);const t=new Date(Date.UTC(y!,m!-1,d!+days));return t.toISOString().slice(0,10)};

/** "Minha célula": o líder acompanha o grupo, registra o encontro e cuida das pessoas pelo celular. */
export default function CellLeaderScreen({rpc,org,unit,cells,palette:p}:{rpc:ChurchRpc;org:string;unit:string;cells:LeaderCell[];palette:Palette}){
 const {width}=useWindowDimensions(),wide=width>=700;
 const [cell,setCell]=useState(cells[0]?.id||''),[data,setData]=useState<LeaderOverview|null>(null),[loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[reload,setReload]=useState(0);
 const [report,setReport]=useState<Report|null>(null),[plan,setPlan]=useState<{id:string;topic:string;date:string;time:string}|null>(null),[openMeeting,setOpenMeeting]=useState('');
 const lock=useRef(false);
 useEffect(()=>{if(!cells.some(c=>c.id===cell))setCell(cells[0]?.id||'')},[cells,cell]);
 useEffect(()=>{let live=true;if(!cell)return;setLoading(true);setError('');
  void Promise.resolve(rpc.rpc('member_cell_leader',{p_org:org,p_unit:unit,p_cell:cell,p_action:'overview',p_data:{}})).then(r=>{if(!live)return;if(r.error){setError(leaderError(r.error.message));return}setData(r.data as LeaderOverview)}).catch(()=>{if(live)setError('Sem conexão. Puxe para atualizar.')}).finally(()=>{if(live)setLoading(false)});
  return()=>{live=false}},[rpc,org,unit,cell,reload]);
 const call=useCallback(async(action:string,payload:object,done:string)=>{if(lock.current)return false;lock.current=true;setBusy(true);setError('');setNotice('');
  try{const r=await rpc.rpc('member_cell_leader',{p_org:org,p_unit:unit,p_cell:cell,p_action:action,p_data:payload});if(r.error){setError(leaderError(r.error.message));return false}setNotice(done);setReload(n=>n+1);return true}
  catch{setError('Sem conexão. Tente de novo.');return false}finally{lock.current=false;setBusy(false)}},[rpc,org,unit,cell]);

 const ac=p.accent,onB=onBrand(p.brand),now=data?.today||today();
 const pill=(label:string,on:boolean,press:()=>void,key?:string)=><Pressable key={key||label} accessibilityRole="button" accessibilityState={{selected:on}} onPress={press} style={[s.pill,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{label}</Text></Pressable>;
 const primary=(label:string,press:()=>void,disabled=false)=><Pressable accessibilityRole="button" accessibilityState={{disabled}} disabled={disabled||busy} onPress={press} style={[s.primary,{backgroundColor:p.brand,opacity:disabled||busy?.55:1}]}><Text style={{color:onB,fontWeight:'800',fontSize:16}}>{busy?'Enviando…':label}</Text></Pressable>;
 const ghost=(label:string,press:()=>void)=><Pressable accessibilityRole="button" onPress={press} style={[s.ghost,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>{label}</Text></Pressable>;
 const over=(t:string)=><Text style={[s.over,{color:ac}]}>{t}</Text>;
 const avatar=(name:string,size=42)=><View style={{width:size,height:size,borderRadius:size/2,backgroundColor:ac+'22',alignItems:'center',justifyContent:'center'}}><Text style={{color:ac,fontWeight:'900',fontSize:size*.36}}>{initials(name)}</Text></View>;
 const whats=(phone:string,text:string,label:string)=>{const url=whatsappLink(phone,text);return url?<Pressable accessibilityRole="link" accessibilityLabel={label} onPress={()=>void Linking.openURL(url)} style={[s.round,{borderColor:p.line}]}><Icon name="chat" color={ac} size={20}/></Pressable>:null};

 if(!cells.length)return <Text style={{color:p.muted}}>Você não lidera nenhuma célula nesta igreja.</Text>;

 // ——— Relato do encontro: três blocos numa página só, com resumo fixo no fim ———
 if(report){
  const r=report,set=(x:Partial<Report>)=>setReport({...r,...x}),roster=r.meeting.roster;
  const addVisitor=()=>{const name=r.visitorName.trim(),phone=phoneDigits(r.visitorPhone);if(name.length<2){setError('Digite o nome do visitante.');return}if(r.visitorPhone.trim()&&!phone){setError('Telefone com DDD, só números.');return}setError('');set({visitors:[...r.visitors,{name,phone}],visitorName:'',visitorPhone:''})};
  return <View>
   <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/>
    <Text style={[s.coverOver,{color:onB}]}>RELATO DO ENCONTRO</Text><Text style={[s.coverTitle,{color:onB}]}>{r.meeting.topic}</Text><Text style={{color:onB,opacity:.85,marginTop:4}}>{shortDate(r.meeting.date)} · {r.meeting.time}</Text></View>
   {!!error&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:ac}]}>{error}</Text>}
   <View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
    <View style={s.blockHead}><Text style={[s.num,{backgroundColor:ac,color:onBrand(ac)}]}>1</Text><Text style={[s.h2,{color:p.text,flex:1}]}>Quem esteve</Text>
     <Pressable accessibilityRole="button" onPress={()=>set({present:r.present.length===roster.length?[]:roster.map(x=>x.participantId)})}><Text style={{color:ac,fontWeight:'800'}}>{r.present.length===roster.length?'Limpar':'Todos'}</Text></Pressable></View>
    <View style={s.grid}>{roster.map(x=>{const on=r.present.includes(x.participantId);return <Pressable key={x.participantId} accessibilityRole="checkbox" accessibilityState={{checked:on}} onPress={()=>set({present:on?r.present.filter(i=>i!==x.participantId):[...r.present,x.participantId]})} style={[s.tile,{width:wide?'31.5%':'48%',borderColor:on?ac:p.line,backgroundColor:on?ac+'1f':p.bg}]}>
     {avatar(x.name,34)}<Text numberOfLines={2} style={{color:p.text,fontWeight:on?'800':'600',flex:1}}>{x.name}</Text><Text style={{color:on?ac:p.muted,fontSize:18,fontWeight:'900'}}>{on?'✓':'○'}</Text></Pressable>})}</View>
    {!roster.length&&<Text style={{color:p.muted}}>Ninguém na lista deste encontro. Os visitantes podem ser registrados abaixo.</Text>}
   </View>
   <View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
    <View style={s.blockHead}><Text style={[s.num,{backgroundColor:ac,color:onBrand(ac)}]}>2</Text><Text style={[s.h2,{color:p.text,flex:1}]}>Quem visitou</Text></View>
    {r.visitors.map((v,i)=><View key={i} style={[s.visitor,{borderColor:p.line}]}>{avatar(v.name,34)}<View style={{flex:1}}><Text style={{color:p.text,fontWeight:'700'}}>{v.name}</Text><Text style={{color:p.muted}}>{v.phone||'Sem telefone'}</Text></View><Pressable accessibilityRole="button" accessibilityLabel={'Remover '+v.name} onPress={()=>set({visitors:r.visitors.filter((_,j)=>j!==i)})}><Text style={{color:p.muted,fontSize:20,padding:6}}>×</Text></Pressable></View>)}
    <TextInput accessibilityLabel="Nome do visitante" value={r.visitorName} onChangeText={v=>set({visitorName:v})} placeholder="Nome do visitante" placeholderTextColor={p.muted} maxLength={120} style={[s.input,{color:p.text,borderColor:p.line}]}/>
    <View style={{flexDirection:'row',gap:8,alignItems:'center'}}><TextInput accessibilityLabel="WhatsApp do visitante" value={r.visitorPhone} onChangeText={v=>set({visitorPhone:v})} placeholder="WhatsApp com DDD (opcional)" keyboardType="phone-pad" placeholderTextColor={p.muted} maxLength={20} style={[s.input,{color:p.text,borderColor:p.line,flex:1}]}/>
     <Pressable accessibilityRole="button" accessibilityLabel="Adicionar visitante" onPress={addVisitor} style={[s.add,{backgroundColor:ac}]}><Icon name="plus" color={onBrand(ac)} size={22}/></Pressable></View>
   </View>
   <View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
    <View style={s.blockHead}><Text style={[s.num,{backgroundColor:ac,color:onBrand(ac)}]}>3</Text><Text style={[s.h2,{color:p.text,flex:1}]}>Como foi</Text></View>
    <View style={s.wrap}>{prompts.map(t=>pill(t,r.notes.includes(t),()=>set({notes:r.notes.includes(t)?r.notes.replace(t,'').replace(/^[\s·]+|[\s·]+$/g,'').replace(/ · · /g,' · '):(r.notes?r.notes+' · ':'')+t})))}</View>
    <TextInput accessibilityLabel="Observações do encontro" value={r.notes} onChangeText={v=>set({notes:v})} multiline maxLength={1000} placeholder="Algo que a supervisão deve saber? (opcional)" placeholderTextColor={p.muted} style={[s.input,s.area,{color:p.text,borderColor:p.line}]}/>
   </View>
   <View style={[s.summary,{backgroundColor:p.surface,borderColor:ac}]}>
    <View style={{flexDirection:'row',gap:18,justifyContent:'center'}}><Text style={{color:p.text}}><Text style={{fontWeight:'900',fontSize:20}}>{r.present.length}</Text> presentes</Text><Text style={{color:p.text}}><Text style={{fontWeight:'900',fontSize:20}}>{r.visitors.length}</Text> visitantes</Text></View>
    {primary('Enviar relato',()=>void call('report',{meeting:r.meeting.id,version:r.meeting.version,present:r.present,visitors:r.visitors,notes:r.notes.trim()},'Relato enviado. Obrigado por cuidar do seu grupo!').then(ok=>{if(ok)setReport(null)}))}
    {ghost('Voltar sem enviar',()=>{setError('');setReport(null)})}
   </View>
  </View>;
 }

 if(!data)return <View style={{padding:24,alignItems:'center'}}>{loading?<ActivityIndicator color={ac}/>:<Text style={{color:p.muted}}>{error||'Carregando…'}</Text>}</View>;
 const pend=pendingMeetings(data.meetings,now),births=upcomingBirthdays(data.people,now,30),rate=attendanceRate(data.meetings),care=data.people.filter(needsCare);
 const startReport=(m:LeaderMeeting)=>{setError('');setNotice('');setReport({meeting:m,present:m.roster.filter(x=>x.present).map(x=>x.participantId),visitors:[],notes:m.notes,visitorName:'',visitorPhone:''})};
 const next=data.meetings.filter(m=>m.status==='scheduled'&&m.date>now).sort((a,b)=>a.date.localeCompare(b.date))[0];

 return <View>
  {cells.length>1&&<ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8,paddingBottom:12}}>{cells.map(c=>pill(c.name,c.id===cell,()=>{setData(null);setCell(c.id)},c.id))}</ScrollView>}
  <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/><View style={[s.blob2,{backgroundColor:onB,opacity:.06}]}/>
   <Text style={[s.coverOver,{color:onB}]}>MINHA CÉLULA</Text><Text style={[s.coverTitle,{color:onB}]}>{data.cell.name}</Text>
   <Text style={{color:onB,opacity:.88,marginTop:6}}>Toda {weekDays[data.cell.day]||'semana'} · {data.cell.time}{data.cell.location?' · '+data.cell.location:''}</Text>
   <View style={s.stats}>{[[String(data.people.length),'pessoas'],[rate===null?'—':rate+'%','frequência'],[String(data.visitors.length),'visitantes em 90 dias']].map(([n,l])=><View key={l} style={[s.stat,{backgroundColor:onB+'1a'}]}><Text style={{color:onB,fontSize:22,fontWeight:'900'}}>{n}</Text><Text style={{color:onB,opacity:.85,fontSize:12}}>{l}</Text></View>)}</View>
  </View>
  {!!error&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:ac}]}>{error}</Text>}
  {!!notice&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:p.line}]}>{notice}</Text>}

  {data.canReport&&<View style={[s.block,{backgroundColor:p.surface,borderColor:pend.length?ac:p.line}]}>
   {over('PRÓXIMO PASSO')}
   {pend.length?<>{pend.map(m=><View key={m.id} style={s.row}><View style={[s.date,{borderColor:ac}]}><Text style={{color:ac,fontWeight:'900',fontSize:18}}>{m.date.slice(8)}</Text><Text style={{color:ac,fontSize:10,fontWeight:'800'}}>{monthShort[+m.date.slice(5,7)-1]}</Text></View>
     <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{m.topic}</Text><Text style={{color:p.muted}}>Esperando o seu relato</Text></View>
     <Pressable accessibilityRole="button" onPress={()=>startReport(m)} style={[s.small,{backgroundColor:p.brand}]}><Text style={{color:onB,fontWeight:'800'}}>Relatar</Text></Pressable></View>)}</>
   :plan?<View>
     <Text style={[s.h2,{color:p.text}]}>Novo encontro</Text>
     <TextInput accessibilityLabel="Tema do encontro" value={plan.topic} onChangeText={v=>setPlan({...plan,topic:v})} maxLength={120} placeholder="Tema ou estudo" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line}]}/>
     <View style={[s.wrap,{marginTop:10}]}>{[[now,'Hoje'],[shift(now,-1),'Ontem'],[shift(now,7),'Daqui a 7 dias']].map(([d,l])=>pill(l!,plan.date===d,()=>setPlan({...plan,date:d!}),l))}</View>
     <TextInput accessibilityLabel="Horário" value={plan.time} onChangeText={v=>setPlan({...plan,time:v})} maxLength={5} placeholder="20:00" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,width:110}]}/>
     {primary(plan.date>now?'Agendar encontro':'Criar e relatar agora',()=>void call('meeting',plan,plan.date>now?'Encontro agendado.':'Encontro criado. Agora é só marcar quem esteve.').then(ok=>{if(ok)setPlan(null)}),plan.topic.trim().length<2||!/^([01]\d|2[0-3]):[0-5]\d$/.test(plan.time))}
     {ghost('Cancelar',()=>setPlan(null))}
    </View>
   :<View><Text style={{color:p.text,fontWeight:'800',fontSize:17}}>{next?'Próximo encontro: '+shortDate(next.date)+' · '+next.topic:'Tudo em dia por aqui.'}</Text>
     <Text style={{color:p.muted,marginTop:4}}>Registre o encontro quando ele acontecer para a supervisão acompanhar o grupo.</Text>
     {primary('Registrar um encontro',()=>setPlan({id:randomUUID(),topic:'Encontro da célula',date:now,time:data.cell.time||'20:00'}))}</View>}
  </View>}

  {births.length>0&&<>{over('ANIVERSARIANTES · PRÓXIMOS 30 DIAS')}
   <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:10,paddingBottom:6}}>{births.map(b=><View key={b.participantId} style={[s.birth,{backgroundColor:p.surface,borderColor:b.inDays===0?ac:p.line}]}>
    <Icon name="cake" color={ac} size={22}/><Text numberOfLines={1} style={{color:p.text,fontWeight:'800',marginTop:6}}>{b.name.split(' ')[0]}</Text>
    <Text style={{color:b.inDays===0?ac:p.muted,fontWeight:b.inDays===0?'800':'500'}}>{b.inDays===0?'Hoje!':b.inDays===1?'Amanhã':b.birthday.slice(3)+'/'+b.birthday.slice(0,2)}</Text>
    {whats(b.phone,'Feliz aniversário, '+b.name.split(' ')[0]+'! Que Deus abençoe seu novo ano de vida.','Parabenizar '+b.name)}</View>)}</ScrollView></>}

  {care.length>0&&<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>{over('SENTIMOS FALTA')}
   <Text style={{color:p.muted,marginBottom:6}}>Não vieram aos dois últimos encontros. Uma mensagem faz diferença.</Text>
   {care.map(x=><View key={x.participantId} style={s.row}>{avatar(x.name)}<Text style={{color:p.text,fontWeight:'700',flex:1}}>{x.name}</Text>{whats(x.phone,'Oi, '+x.name.split(' ')[0]+'! Sentimos sua falta na célula. Está tudo bem?','Mandar mensagem para '+x.name)}</View>)}</View>}

  {data.referrals.length>0&&<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>{over('CHEGANDO NO GRUPO')}
   <Text style={{color:p.muted,marginBottom:6}}>A igreja indicou estas pessoas para a sua célula.</Text>
   {data.referrals.map(r=><View key={r.id} style={s.row}>{avatar(r.name)}<View style={{flex:1}}><Text style={{color:p.text,fontWeight:'700'}}>{r.name}</Text>{!r.linked&&<Text style={{color:p.muted,fontSize:12}}>Aguardando cadastro na secretaria</Text>}</View>
    {data.canReport&&<><Pressable accessibilityRole="button" disabled={busy||!r.linked} onPress={()=>void call('referral',{id:r.id,version:r.version,answer:'accept'},r.name+' agora faz parte da célula.')} style={[s.small,{backgroundColor:p.brand,opacity:r.linked?1:.45}]}><Text style={{color:onB,fontWeight:'800'}}>Receber</Text></Pressable>
     <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void call('referral',{id:r.id,version:r.version,answer:'decline'},'Indicação devolvida para a igreja.')} style={[s.small,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>Agora não</Text></Pressable></>}</View>)}</View>}

  {over('PESSOAS DO GRUPO')}
  <View style={[s.block,{backgroundColor:p.surface,borderColor:p.line,paddingVertical:6}]}>{data.people.map((x,i)=><View key={x.participantId} style={[s.row,i>0&&{borderTopWidth:1,borderTopColor:p.line}]}>{avatar(x.name)}
   <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'700'}}>{x.name}</Text><View style={{flexDirection:'row',gap:4,marginTop:5}}>{x.recent.map((v,j)=><View key={j} style={{width:10,height:10,borderRadius:5,backgroundColor:v?ac:'transparent',borderWidth:1.5,borderColor:v?ac:p.muted}}/>)}{!x.recent.length&&<Text style={{color:p.muted,fontSize:12}}>Sem encontros registrados</Text>}</View></View>
   {whats(x.phone,'Oi, '+x.name.split(' ')[0]+'!','Conversar com '+x.name)}</View>)}
   {!data.people.length&&<Text style={{color:p.muted,padding:12}}>Ninguém no grupo ainda.</Text>}</View>
  <Text style={{color:p.muted,fontSize:12,marginTop:-6,marginBottom:14}}>Bolinhas: presença nos últimos encontros, do mais recente para o mais antigo.</Text>

  {data.visitors.length>0&&<>{over('VISITARAM RECENTEMENTE')}<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line,paddingVertical:6}]}>{data.visitors.map((v,i)=><View key={v.id} style={[s.row,i>0&&{borderTopWidth:1,borderTopColor:p.line}]}>{avatar(v.name)}<View style={{flex:1}}><Text style={{color:p.text,fontWeight:'700'}}>{v.name}</Text><Text style={{color:p.muted}}>Visitou em {shortDate(v.date)}</Text></View>{whats(v.phone,'Oi, '+v.name.split(' ')[0]+'! Foi muito bom ter você na nossa célula. Volte sempre!','Agradecer visita de '+v.name)}</View>)}</View></>}

  {over('ENCONTROS')}
  {data.meetings.map(m=>{const open=openMeeting===m.id,pct=m.expected?m.present/m.expected:0;return <Pressable key={m.id} accessibilityRole="button" accessibilityState={{expanded:open}} onPress={()=>setOpenMeeting(open?'':m.id)} style={[s.meeting,{backgroundColor:p.surface,borderColor:p.line}]}>
   <View style={s.row}><View style={[s.date,{borderColor:m.status==='completed'?ac:p.line}]}><Text style={{color:m.status==='completed'?ac:p.muted,fontWeight:'900',fontSize:18}}>{m.date.slice(8)}</Text><Text style={{color:m.status==='completed'?ac:p.muted,fontSize:10,fontWeight:'800'}}>{monthShort[+m.date.slice(5,7)-1]}</Text></View>
    <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{m.topic}</Text><Text style={{color:p.muted}}>{m.status==='completed'?m.present+' de '+m.expected+' presentes'+(m.visitors?' · '+m.visitors+' visitante'+(m.visitors>1?'s':''):''):m.date>now?'Agendado · '+m.time:'Aguardando relato'}</Text>
     {m.status==='completed'&&<View style={[s.bar,{backgroundColor:p.line}]}><View style={{width:`${Math.round(pct*100)}%`,height:'100%',borderRadius:3,backgroundColor:ac}}/></View>}</View></View>
   {open&&<View style={{marginTop:10}}>{m.roster.length>0&&<Text style={{color:p.text,lineHeight:22}}>{m.roster.filter(x=>x.present).map(x=>x.name).join(', ')||'Ninguém marcado como presente.'}</Text>}{!!m.notes&&<Text style={{color:p.muted,marginTop:6,fontStyle:'italic'}}>“{m.notes}”</Text>}
    {data.canReport&&m.date<=now&&ghost(m.status==='completed'?'Corrigir relato':'Fazer relato',()=>startReport(m))}</View>}
  </Pressable>})}
  {!data.meetings.length&&<Text style={{color:p.muted,marginBottom:14}}>Nenhum encontro registrado nos últimos meses.</Text>}

  {data.materials.length>0&&<>{over('PARA PREPARAR O ENCONTRO')}{data.materials.map(m=><View key={m.id} style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}><Text style={[s.h2,{color:p.text}]}>{m.title}</Text>{!!m.body&&<Text style={{color:p.muted,lineHeight:22,marginTop:4}}>{m.body}</Text>}{/^https:\/\//.test(m.url)&&ghost('Abrir material',()=>void Linking.openURL(m.url))}</View>)}</>}
  {ghost(loading?'Atualizando…':'Atualizar',()=>setReload(n=>n+1))}
 </View>;
}

const s=StyleSheet.create({
 cover:{borderRadius:24,padding:22,overflow:'hidden',marginBottom:14},blob:{position:'absolute',width:220,height:220,borderRadius:110,right:-70,top:-90},blob2:{position:'absolute',width:140,height:140,borderRadius:70,left:-50,bottom:-60},
 coverOver:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},coverTitle:{fontSize:26,fontWeight:'900',marginTop:6},
 stats:{flexDirection:'row',gap:8,marginTop:18},stat:{flex:1,borderRadius:16,padding:10},
 over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginTop:8,marginBottom:8},
 block:{borderWidth:1,borderRadius:22,padding:16,marginBottom:14},blockHead:{flexDirection:'row',alignItems:'center',gap:10,marginBottom:12},
 num:{width:28,height:28,borderRadius:14,textAlign:'center',textAlignVertical:'center',lineHeight:28,fontWeight:'900',overflow:'hidden'},
 h2:{fontSize:17,fontWeight:'800'},row:{flexDirection:'row',alignItems:'center',gap:12,paddingVertical:10},
 date:{width:48,height:52,borderWidth:2,borderRadius:14,alignItems:'center',justifyContent:'center'},
 small:{paddingHorizontal:14,paddingVertical:10,borderRadius:22,minHeight:40,justifyContent:'center'},
 round:{width:42,height:42,borderRadius:21,borderWidth:1,alignItems:'center',justifyContent:'center'},
 grid:{flexDirection:'row',flexWrap:'wrap',gap:8},tile:{flexDirection:'row',alignItems:'center',gap:8,borderWidth:1.5,borderRadius:18,padding:10,minHeight:58},
 visitor:{flexDirection:'row',alignItems:'center',gap:10,borderBottomWidth:1,paddingVertical:8},
 input:{borderWidth:1,borderRadius:14,padding:12,fontSize:15,marginTop:8,minHeight:48},area:{minHeight:90,textAlignVertical:'top'},
 add:{width:48,height:48,borderRadius:24,alignItems:'center',justifyContent:'center',marginTop:8},
 wrap:{flexDirection:'row',flexWrap:'wrap',gap:8},pill:{borderWidth:1,borderRadius:22,paddingHorizontal:14,paddingVertical:9},
 summary:{borderWidth:2,borderRadius:22,padding:16,marginBottom:20},
 primary:{borderRadius:16,paddingVertical:15,alignItems:'center',marginTop:14,minHeight:52,justifyContent:'center'},
 ghost:{borderWidth:1,borderRadius:16,paddingVertical:13,alignItems:'center',marginTop:10,minHeight:48,justifyContent:'center'},
 alert:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12,lineHeight:21},
 birth:{width:118,borderWidth:1,borderRadius:20,padding:12,alignItems:'flex-start',gap:2},
 meeting:{borderWidth:1,borderRadius:20,paddingHorizontal:14,paddingVertical:4,marginBottom:10},bar:{height:6,borderRadius:3,marginTop:8,overflow:'hidden'},
});
