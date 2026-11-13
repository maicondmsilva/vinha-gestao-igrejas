import {useEffect,useState} from 'react';
import {Pressable,ScrollView,StyleSheet,Switch,Text,TextInput,View} from 'react-native';
import * as Crypto from 'expo-crypto';
import type {ChurchRpc} from '../../shared/member-church';
import {relationLabels,relations,type Relation} from '../../shared/relations';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};
type Relative={name:string;relation:Relation};
type Req={id:string;name:string;relation:Relation;status:string;reason:string|null};
const statusLabel:Record<string,string>={pending:'Em análise',approved:'Aprovado',rejected:'Não aprovado',cancelled:'Cancelado'};
const message=(e:{code?:string}|null)=>e?.code==='42501'?'Envie primeiro o seu cadastro para a igreja.':e?.code==='22023'?'Confira o nome, a data e o parentesco.':e?.code==='54000'?'Você já tem muitos pedidos em análise. Aguarde a igreja.':'Não foi possível concluir agora. Tente de novo.';

/** Minha família: familiares ligados ao cadastro e pedido de inclusão para a igreja analisar. */
export default function MemberRelatives({rpc,org,palette:p}:{rpc:ChurchRpc;org:string;palette:Palette}){
 const ac=p.accent||p.brand;
 const [items,setItems]=useState<Relative[]>([]),[requests,setRequests]=useState<Req[]>([]),[form,setForm]=useState<{name:string;birth:string;relation:Relation|'';home:boolean;nonce:string}|null>(null),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[reload,setReload]=useState(0);
 useEffect(()=>{let live=true;
  void Promise.all([rpc.rpc('member_relatives',{p_org:org,p_action:'list',p_data:{}}),rpc.rpc('member_relatives',{p_org:org,p_action:'requests',p_data:{}})]).then(([a,b])=>{if(!live)return;
   if(!a.error)setItems(((a.data as {items?:Relative[]})?.items)||[]);if(!b.error)setRequests(((b.data as {items?:Req[]})?.items)||[])}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,reload]);
 async function send(){if(!form||!form.relation||form.name.trim().length<2){setNotice('Informe o nome e o parentesco.');return}
  let birth:string|null=null;if(form.birth){const [d,m,y]=form.birth.split('/');birth=`${y}-${m}-${d}`;if(!/^\d{4}-\d{2}-\d{2}$/.test(birth)||!Number.isFinite(Date.parse(birth))){setNotice('Data de nascimento no formato dia/mês/ano.');return}}
  setBusy(true);setNotice('');
  const r=await rpc.rpc('member_relatives',{p_org:org,p_action:'request',p_data:{nonce:form.nonce,name:form.name.trim(),birth_date:birth,relation:form.relation,same_household:form.home}});
  setBusy(false);if(r.error){setNotice(message(r.error));return}setForm(null);setNotice('Pedido enviado. A igreja vai conferir e avisar você.');setReload(x=>x+1)}
 const pending=requests.filter(r=>r.status!=='approved');
 return <View>
  <Text accessibilityRole="header" style={[s.h1,{color:p.text}]}>Minha família</Text>
  {items.length?items.map(i=><View key={i.name+i.relation} style={[s.person,{backgroundColor:p.surface,borderColor:p.line}]}><View style={[s.avatar,{backgroundColor:ac}]}><Text style={{color:'#fff',fontWeight:'800'}}>{i.name.slice(0,1).toUpperCase()}</Text></View><View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{i.name}</Text><Text style={{color:p.muted}}>{relationLabels[i.relation]||i.relation}</Text></View></View>):<Text style={{color:p.muted}}>Nenhum familiar ligado ao seu cadastro ainda.</Text>}
  {notice!==''&&<Text accessibilityRole="alert" style={{color:p.text,marginTop:10}}>{notice}</Text>}
  {!form?<Pressable accessibilityRole="button" onPress={()=>{setNotice('');setForm({name:'',birth:'',relation:'',home:false,nonce:Crypto.randomUUID()})}} style={[s.primary,{backgroundColor:ac}]}><Text style={{color:'#fff',fontWeight:'800'}}>Pedir inclusão de familiar</Text></Pressable>:
   <View style={[s.form,{backgroundColor:p.surface,borderColor:p.line}]}>
    <Text style={[s.label,{color:p.text}]}>Nome do familiar</Text><TextInput accessibilityLabel="Nome do familiar" value={form.name} onChangeText={v=>setForm({...form,name:v})} maxLength={160} style={[s.input,{color:p.text,borderColor:p.line}]}/>
    <Text style={[s.label,{color:p.text}]}>Nascimento (opcional)</Text><TextInput accessibilityLabel="Nascimento" placeholder="DD/MM/AAAA" placeholderTextColor={p.muted} keyboardType="number-pad" value={form.birth} onChangeText={v=>setForm({...form,birth:v.replace(/\D/g,'').slice(0,8).replace(/^(\d{2})(\d)/,'$1/$2').replace(/^(\d{2}\/\d{2})(\d)/,'$1/$2')})} style={[s.input,{color:p.text,borderColor:p.line}]}/>
    <Text style={[s.label,{color:p.text}]}>Essa pessoa é meu/minha…</Text>
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8,paddingVertical:6}}>{relations.map(r=><Pressable key={r} accessibilityRole="button" accessibilityState={{selected:form.relation===r}} onPress={()=>setForm({...form,relation:r})} style={[s.chip,{borderColor:form.relation===r?ac:p.line,backgroundColor:form.relation===r?ac:p.surface}]}><Text style={{color:form.relation===r?'#fff':p.text,fontWeight:'700'}}>{relationLabels[r]}</Text></Pressable>)}</ScrollView>
    <View style={s.row}><Text style={{color:p.text,fontWeight:'700',flex:1}}>Mora comigo</Text><Switch value={form.home} onValueChange={v=>setForm({...form,home:v})} trackColor={{true:ac,false:p.line}}/></View>
    <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void send()} style={[s.primary,{backgroundColor:ac,opacity:busy?.6:1}]}><Text style={{color:'#fff',fontWeight:'800'}}>{busy?'Enviando…':'Enviar para a igreja'}</Text></Pressable>
    <Pressable accessibilityRole="button" disabled={busy} onPress={()=>setForm(null)} style={s.secondary}><Text style={{color:p.text,fontWeight:'700'}}>Cancelar</Text></Pressable>
   </View>}
  {pending.length>0&&<><Text style={[s.h2,{color:p.text}]}>Pedidos enviados</Text>{pending.map(r=><View key={r.id} style={[s.person,{backgroundColor:p.surface,borderColor:p.line}]}><View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{r.name} · {relationLabels[r.relation]||r.relation}</Text><Text style={{color:p.muted}}>{statusLabel[r.status]||r.status}{r.reason?' — '+r.reason:''}</Text></View></View>)}</>}
 </View>;
}
const s=StyleSheet.create({h1:{fontSize:28,fontWeight:'900',marginBottom:10},h2:{fontSize:19,fontWeight:'800',marginTop:20,marginBottom:6},person:{flexDirection:'row',alignItems:'center',gap:12,borderWidth:1,borderRadius:18,padding:12,marginVertical:5},avatar:{width:40,height:40,borderRadius:20,alignItems:'center',justifyContent:'center'},primary:{borderRadius:14,padding:14,alignItems:'center',marginTop:14},secondary:{padding:12,alignItems:'center'},form:{borderWidth:1,borderRadius:20,padding:14,marginTop:14},label:{fontWeight:'700',marginTop:10},input:{borderWidth:1,borderRadius:12,padding:12,marginTop:6,fontSize:15},chip:{borderWidth:1,borderRadius:20,paddingHorizontal:12,paddingVertical:8},row:{flexDirection:'row',alignItems:'center',marginTop:12}});
