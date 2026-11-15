import {useCallback,useEffect,useState} from 'react';
import {ActivityIndicator,Pressable,StyleSheet,Text,TextInput,View} from 'react-native';
import type {ChurchRpc} from '../../shared/member-church';
import {availabilityLegend,availabilityState,monthGrid,monthTitle,rangesProblem,shiftMonth,timeMask,type AvailabilityDay,type AvailabilityRange,type AvailabilityState} from '../../shared/pastoral';
import {onBrand} from './experience-model';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
type Hour={weekday:number;starts:string;ends:string};
type Month={version:number;hours:Hour[];blocks:{id:string;from:string;to:string;reason:string}[];days:AvailabilityDay[]};
const week=['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'],short=['D','S','T','Q','Q','S','S'];
const thisMonth=()=>{const d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')};
const todayKey=()=>{const d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')};
const fmtDay=(k:string)=>{const t=new Date(k+'T12:00:00').toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long'});return t.charAt(0).toUpperCase()+t.slice(1)};

function RangesEditor({value,onChange,palette:p}:{value:AvailabilityRange[];onChange:(v:AvailabilityRange[])=>void;palette:Palette}){
 const input=(v:string,set:(x:string)=>void,label:string)=><TextInput accessibilityLabel={label} value={v} onChangeText={x=>set(timeMask(x))} keyboardType="number-pad" maxLength={5} placeholder="00:00" placeholderTextColor={p.muted} style={[s.time,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>;
 return <View>{value.map((r,i)=><View key={i} style={s.rangeRow}>
  {input(r.starts,x=>onChange(value.map((y,j)=>j===i?{...y,starts:x}:y)),'Início')}<Text style={{color:p.muted}}>até</Text>{input(r.ends,x=>onChange(value.map((y,j)=>j===i?{...y,ends:x}:y)),'Fim')}
  <Pressable accessibilityRole="button" accessibilityLabel="Remover faixa" onPress={()=>onChange(value.filter((_,j)=>j!==i))}><Text style={{color:p.muted,fontWeight:'900',fontSize:18,paddingHorizontal:8}}>×</Text></Pressable></View>)}
  {value.length<6&&<Pressable accessibilityRole="button" onPress={()=>onChange([...value,{starts:value.length?value[value.length-1]!.ends:'09:00',ends:value.length?'':'12:00'}])}><Text style={{color:p.accent,fontWeight:'800',marginTop:4}}>+ adicionar horário</Text></Pressable>}
 </View>;
}

/** Minha disponibilidade: semana padrão e calendário do mês para ajustar um dia, não atender ou bloquear. */
export default function PastoralAvailability({rpc,org,unit,attendant,palette:p,onChanged}:{rpc:ChurchRpc;org:string;unit:string;attendant:string;palette:Palette;onChanged:(m:string)=>void}){
 const ac=p.accent,[month,setMonth]=useState(thisMonth()),[data,setData]=useState<Month|null>(null),[rev,setRev]=useState(0),[day,setDay]=useState(''),[ranges,setRanges]=useState<AvailabilityRange[]>([]),[weekEdit,setWeekEdit]=useState<AvailabilityRange[][]|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let live=true;setData(null);void Promise.resolve(rpc.rpc('pastoral_availability',{p_org:org,p_unit:unit,p_action:'month',p_data:{attendant,month}})).then(r=>{if(live&&!r.error)setData(r.data as Month)});return()=>{live=false}},[rpc,org,unit,attendant,month,rev]);
 const reload=()=>setRev(n=>n+1);
 const call=useCallback(async(fn:string,action:string,payload:object,done:string)=>{setBusy(true);setError('');try{const r=await rpc.rpc(fn,{p_org:org,p_unit:unit,p_action:action,p_data:{attendant,...payload}});if(r.error)throw Error();onChanged(done);reload();return true}catch{setError('Não foi possível salvar. Confira os horários e tente de novo.');return false}finally{setBusy(false)}},[rpc,org,unit,attendant,onChanged]);
 const tone=(st:AvailabilityState)=>st==='open'?{bg:ac,fg:onBrand(ac),bd:ac}:st==='custom'?{bg:'#dbbb70',fg:'#2b2410',bd:'#dbbb70'}:st==='blocked'?{bg:'#f6dfd8',fg:'#8a3b2a',bd:'#e7b8aa'}:{bg:p.surface,fg:p.muted,bd:p.line};
 const sel=data?.days.find(d=>d.date===day),today=todayKey();
 function openDay(k:string){if(k<today)return;const d=data?.days.find(x=>x.date===k);setDay(k);setRanges(d?.ranges.map(r=>({...r}))||[]);setError('')}
 async function saveDay(){const pr=rangesProblem(ranges);if(pr){setError(pr);return}if(await call('pastoral_availability','day',{date:day,ranges},ranges.length?'Horários de '+fmtDay(day)+' salvos.':fmtDay(day)+': sem atendimento.'))setDay('')}
 async function saveWeek(){if(!weekEdit)return;const list=weekEdit.flatMap((r,w)=>r.map(x=>({weekday:w,...x})));for(const r of weekEdit){const pr=rangesProblem(r);if(pr){setError(pr);return}}if(await call('pastoral_staff','hours',{hours:list},'Semana padrão atualizada.'))setWeekEdit(null)}
 const block=sel&&data?.blocks.find(b=>sel.date>=b.from&&sel.date<=b.to);
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:p.line}]}>
  <Text style={[s.over,{color:ac}]}>MINHA DISPONIBILIDADE</Text>
  <Text style={{color:p.muted,lineHeight:20}}>Toque num dia para marcar os horários só daquele dia, não atender ou bloquear. Os membros veem apenas os horários livres.</Text>
  <View style={s.monthBar}><Pressable accessibilityRole="button" accessibilityLabel="Mês anterior" disabled={month<=thisMonth()} onPress={()=>setMonth(shiftMonth(month,-1))} style={{opacity:month<=thisMonth()?.3:1}}><Text style={[s.arrow,{color:p.text}]}>‹</Text></Pressable><Text style={{color:p.text,fontWeight:'900',fontSize:16}}>{monthTitle(month)}</Text><Pressable accessibilityRole="button" accessibilityLabel="Próximo mês" onPress={()=>setMonth(shiftMonth(month,1))}><Text style={[s.arrow,{color:p.text}]}>›</Text></Pressable></View>
  <View style={s.weekRow}>{short.map((d,i)=><Text key={i} style={[s.wd,{color:p.muted}]}>{d}</Text>)}</View>
  {!data?<ActivityIndicator color={ac} style={{marginVertical:24}}/>:monthGrid(month).map((w,i)=><View key={i} style={s.weekRow}>{w.map((k,j)=>{if(!k)return <View key={j} style={s.cell}/>;const d=data.days.find(x=>x.date===k),st=d?availabilityState(d):'off',t=tone(st),past=k<today,on=k===day;
   return <Pressable key={k} accessibilityRole="button" accessibilityLabel={fmtDay(k)} disabled={past} onPress={()=>openDay(k)} style={[s.cell,{backgroundColor:t.bg,borderColor:on?p.text:t.bd,borderWidth:on?2:1,opacity:past?.35:1}]}><Text style={{color:t.fg,fontWeight:'900'}}>{Number(k.slice(8))}</Text>{!!d?.booked&&<View style={[s.dot,{backgroundColor:t.fg}]}/>}</Pressable>})}</View>)}
  <View style={s.legend}>{availabilityLegend.map(([st,l])=>{const t=tone(st);return <View key={st} style={s.legendItem}><View style={[s.sw,{backgroundColor:t.bg,borderColor:t.bd}]}/><Text style={{color:p.muted,fontSize:12}}>{l}</Text></View>})}</View>
  {!!error&&<Text accessibilityRole="alert" style={{color:'#b8741a',fontWeight:'700',marginTop:8}}>{error}</Text>}
  {sel&&<View style={[s.panel,{borderColor:ac,backgroundColor:p.bg}]}>
   <Text style={{color:p.text,fontWeight:'900',fontSize:16}}>{fmtDay(sel.date)}</Text>
   {block?<><Text style={{color:p.muted,marginTop:4}}>Bloqueado{block.reason?': '+block.reason:''} ({block.from===block.to?'só este dia':'de '+block.from.split('-').reverse().join('/')+' a '+block.to.split('-').reverse().join('/')}).</Text>
    <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void call('pastoral_staff','unblock',{id:block.id},'Bloqueio removido.').then(ok=>ok&&setDay(''))} style={[s.btn,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>Desbloquear</Text></Pressable></>
   :<><Text style={{color:p.muted,marginTop:4,marginBottom:8}}>{sel.custom?'Horários só deste dia.':'Usando a semana padrão.'}{sel.booked?' · '+sel.booked+' atendimento(s) marcado(s)':''}</Text>
    <RangesEditor value={ranges} onChange={setRanges} palette={p}/>
    <View style={s.actions}>
     <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void saveDay()} style={[s.btn,{backgroundColor:p.brand,borderColor:p.brand}]}><Text style={{color:onBrand(p.brand),fontWeight:'900'}}>{ranges.length?'Salvar horários':'Não atender neste dia'}</Text></Pressable>
     {sel.custom&&<Pressable accessibilityRole="button" disabled={busy} onPress={()=>void call('pastoral_availability','reset',{date:sel.date},'Dia voltou à semana padrão.').then(ok=>ok&&setDay(''))} style={[s.btn,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>Usar semana padrão</Text></Pressable>}
     <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void call('pastoral_staff','block',{from:sel.date,to:sel.date,reason:''},'Dia bloqueado.').then(ok=>ok&&setDay(''))} style={[s.btn,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>Bloquear dia</Text></Pressable>
     <Pressable accessibilityRole="button" onPress={()=>setDay('')}><Text style={{color:p.muted,fontWeight:'700',padding:10}}>Fechar</Text></Pressable>
    </View></>}
  </View>}
  <Text style={{color:p.text,fontWeight:'900',marginTop:16}}>Semana padrão</Text>
  {!weekEdit?<>{data&&<Text style={{color:p.muted,marginTop:4,lineHeight:20}}>{data.hours.length?week.map((w,i)=>{const hs=data.hours.filter(h=>h.weekday===i);return hs.length?w.slice(0,3)+' '+hs.map(h=>h.starts+'–'+h.ends).join(', '):''}).filter(Boolean).join(' · '):'Nenhum horário cadastrado.'}</Text>}
   <Pressable accessibilityRole="button" disabled={!data} onPress={()=>data&&setWeekEdit(week.map((_,i)=>data.hours.filter(h=>h.weekday===i).map(h=>({starts:h.starts,ends:h.ends}))))} style={[s.btn,{borderColor:p.line,alignSelf:'flex-start',marginTop:8}]}><Text style={{color:p.text,fontWeight:'800'}}>Editar semana padrão</Text></Pressable></>
  :<View>{week.map((w,i)=><View key={w} style={[s.weekEdit,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800',width:72}}>{w}</Text><View style={{flex:1}}>{weekEdit[i]!.length?null:<Text style={{color:p.muted}}>Não atendo</Text>}<RangesEditor value={weekEdit[i]!} onChange={v=>setWeekEdit(weekEdit.map((x,j)=>j===i?v:x))} palette={p}/></View></View>)}
   <View style={s.actions}><Pressable accessibilityRole="button" disabled={busy} onPress={()=>void saveWeek()} style={[s.btn,{backgroundColor:p.brand,borderColor:p.brand}]}><Text style={{color:onBrand(p.brand),fontWeight:'900'}}>Salvar semana</Text></Pressable><Pressable accessibilityRole="button" onPress={()=>setWeekEdit(null)}><Text style={{color:p.muted,fontWeight:'700',padding:10}}>Cancelar</Text></Pressable></View></View>}
 </View>;
}
const s=StyleSheet.create({
 card:{borderWidth:1,borderRadius:22,padding:14,marginTop:18},over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginBottom:6},
 monthBar:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',marginVertical:12},arrow:{fontSize:28,fontWeight:'700',paddingHorizontal:12},
 weekRow:{flexDirection:'row',justifyContent:'space-between',marginBottom:6},wd:{width:40,textAlign:'center',fontWeight:'800',fontSize:12},
 cell:{width:40,height:40,borderRadius:12,alignItems:'center',justifyContent:'center'},dot:{width:5,height:5,borderRadius:3,marginTop:2},
 legend:{flexDirection:'row',flexWrap:'wrap',gap:12,marginTop:8},legendItem:{flexDirection:'row',alignItems:'center',gap:6},sw:{width:14,height:14,borderRadius:4,borderWidth:1},
 panel:{borderWidth:1.5,borderRadius:18,padding:12,marginTop:12},rangeRow:{flexDirection:'row',alignItems:'center',gap:8,marginBottom:6},
 time:{borderWidth:1,borderRadius:12,paddingHorizontal:10,paddingVertical:8,width:76,fontSize:16,textAlign:'center'},
 actions:{flexDirection:'row',flexWrap:'wrap',gap:8,marginTop:10,alignItems:'center'},btn:{borderWidth:1,borderRadius:16,paddingHorizontal:14,paddingVertical:10},
 weekEdit:{flexDirection:'row',gap:8,borderTopWidth:1,paddingVertical:10,alignItems:'flex-start'},
});
