import {useCallback,useEffect,useState} from 'react';
import {ActivityIndicator,Pressable,ScrollView,StyleSheet,Text,View} from 'react-native';
import type {ChurchRpc} from '../../shared/member-church';
import {kidsTeamRoles} from '../../shared/kids-setup';
import {onBrand} from './experience-model';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
type Team={id:string;unit:string;role:string;className:string;unavailable:string[]};
type Upcoming={id:string;session:string;startsAt:string;endsAt:string;role:string;room:string;unit:string;confirmed:boolean;declined:boolean};
type Data={team:Team[];upcoming:Upcoming[]};
const iso=(d:Date)=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
const when=(s:string)=>{const t=new Date(s).toLocaleString('pt-BR',{weekday:'long',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});return t.charAt(0).toUpperCase()+t.slice(1)};

/** Diz se a pessoa está na equipe fixa do Kids; sem isso o cartão nem aparece no menu. */
export function useKidsVolunteer(rpc:ChurchRpc,org:string,authenticated:boolean){
 const [data,setData]=useState<Data|null>(null),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;setData(null);if(!authenticated)return;void Promise.resolve(rpc.rpc('kids_volunteer',{p_org:org,p_action:'mine',p_data:{}})).then(r=>{if(live&&!r.error)setData(r.data as Data)}).catch(()=>undefined);return()=>{live=false}},[rpc,org,authenticated,rev]);
 return {data,refresh:useCallback(()=>setRev(n=>n+1),[])};
}

/** Minha escala no Kids: confirmar presença, avisar que não pode e marcar os dias em que não pode servir. */
export default function KidsVolunteerScreen({rpc,org,volunteer,palette:p}:{rpc:ChurchRpc;org:string;volunteer:{data:Data|null;refresh:()=>void};palette:Palette}){
 const [busy,setBusy]=useState(''),[notice,setNotice]=useState(''),ac=p.accent,data=volunteer.data;
 async function act(action:string,payload:object,done:string,key:string){setBusy(key);setNotice('');const r=await Promise.resolve(rpc.rpc('kids_volunteer',{p_org:org,p_action:action,p_data:payload})).catch(()=>({error:{message:'x'}}));setBusy('');if(r.error){setNotice('Não foi possível agora. Tente de novo.');return}setNotice(done);volunteer.refresh()}
 if(!data)return <ActivityIndicator color={ac} style={{marginTop:30}}/>;
 const days=Array.from({length:42},(_,i)=>{const d=new Date();d.setDate(d.getDate()+i);return d});
 return <View>
  <View style={[s.cover,{backgroundColor:p.brand}]}><Text style={[s.coverOver,{color:onBrand(p.brand)}]}>KIDS · MINHA ESCALA</Text>
   <Text style={[s.coverTitle,{color:onBrand(p.brand)}]}>{data.upcoming.filter(u=>!u.declined).length?data.upcoming.filter(u=>!u.declined).length+' escala(s) nos próximos 30 dias':'Nenhuma escala por enquanto'}</Text></View>
  {!!notice&&<Text accessibilityRole="alert" style={[s.notice,{color:p.text,borderColor:p.line,backgroundColor:p.surface}]}>{notice}</Text>}
  <Text style={[s.over,{color:ac}]}>PRÓXIMAS ESCALAS</Text>
  {!data.upcoming.length&&<Text style={{color:p.muted,marginBottom:10}}>Quando você for escalado, aparece aqui. Na véspera chega um aviso na caixa de notificações.</Text>}
  {data.upcoming.map(u=><View key={u.id} style={[s.card,{backgroundColor:p.surface,borderColor:u.confirmed?ac:u.declined?p.line:'#f2a33a',opacity:u.declined?.6:1}]}>
   <Text style={{color:p.text,fontWeight:'900',fontSize:16}}>{u.session}</Text>
   <Text style={{color:p.muted,marginTop:2}}>{when(u.startsAt)} · {kidsTeamRoles.find(([k])=>k===u.role)?.[1]||u.role}{u.room?' · '+u.room:''}</Text>
   <Text style={{color:u.confirmed?ac:p.muted,fontWeight:'700',marginTop:6}}>{u.confirmed?'✓ Presença confirmada':u.declined?'Você avisou que não pode':'Aguardando sua confirmação'}</Text>
   <View style={s.row}>
    {!u.confirmed&&<Pressable accessibilityRole="button" disabled={!!busy} onPress={()=>void act('confirm',{id:u.id},'Obrigado! Presença confirmada.',u.id+'c')} style={[s.btn,{backgroundColor:p.brand}]}><Text style={{color:onBrand(p.brand),fontWeight:'900'}}>{busy===u.id+'c'?'…':'Confirmo'}</Text></Pressable>}
    {!u.declined&&<Pressable accessibilityRole="button" disabled={!!busy} onPress={()=>void act('decline',{id:u.id},'Avisamos a coordenação que você não pode.',u.id+'d')} style={[s.btn,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>{busy===u.id+'d'?'…':'Não posso'}</Text></Pressable>}
   </View>
  </View>)}
  {data.team.map(t=><View key={t.id} style={[s.card,{backgroundColor:p.surface,borderColor:p.line}]}>
   <Text style={[s.over,{color:ac,marginTop:0}]}>DIAS EM QUE NÃO POSSO · {t.unit.toUpperCase()}</Text>
   <Text style={{color:p.muted,marginBottom:10,lineHeight:20}}>{kidsTeamRoles.find(([k])=>k===t.role)?.[1]||t.role}{t.className?' · '+t.className:''}. Toque nos dias em que você não pode servir; a escala automática não coloca você nesses dias.</Text>
   <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:6}}>{days.map(d=>{const k=iso(d),off=t.unavailable.includes(k);return <Pressable key={k} accessibilityRole="checkbox" accessibilityState={{checked:off}} accessibilityLabel={d.toLocaleDateString('pt-BR',{weekday:'long',day:'2-digit',month:'long'})} disabled={!!busy}
    onPress={()=>void act(off?'available':'unavailable',{team:t.id,date:k},off?'Dia liberado.':'Anotado: você não serve neste dia.',k)} style={[s.day,{borderColor:off?'#c25b45':p.line,backgroundColor:off?'#f6dfd8':p.bg}]}>
    <Text style={{color:off?'#8a3b2a':p.muted,fontSize:11,fontWeight:'800'}}>{d.toLocaleDateString('pt-BR',{weekday:'short'}).replace('.','').toUpperCase()}</Text>
    <Text style={{color:off?'#8a3b2a':p.text,fontWeight:'900',fontSize:17}}>{d.getDate()}</Text>
    <Text style={{color:off?'#8a3b2a':p.muted,fontSize:10}}>{off?'não posso':String(d.getMonth()+1).padStart(2,'0')}</Text></Pressable>})}</ScrollView>
  </View>)}
 </View>;
}
const s=StyleSheet.create({cover:{borderRadius:24,padding:22,marginBottom:14},coverOver:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},coverTitle:{fontSize:22,fontWeight:'900',marginTop:6},
 notice:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12},over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginTop:12,marginBottom:10},
 card:{borderWidth:1.5,borderRadius:20,padding:14,marginBottom:10},row:{flexDirection:'row',gap:10,marginTop:10},btn:{flex:1,minHeight:46,borderRadius:16,alignItems:'center',justifyContent:'center'},
 day:{width:58,borderWidth:1.5,borderRadius:14,paddingVertical:8,alignItems:'center'}});
