import {useCallback,useEffect,useState} from 'react';
import {Pressable,StyleSheet,Text,TextInput,View} from 'react-native';
import {supabase} from './supabase';
import {onBrand} from './experience-model';
import QrCode from './QrCode';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
type Guardian={id:string;name:string;relationship:string;temporary:boolean;validUntil:string|null;canPickup:boolean;me:boolean;removable?:boolean};
const br=(d:string)=>d.split('-').reverse().slice(0,2).join('/');
const dayOptions:[number,string][]=[[1,'Só hoje'],[3,'3 dias'],[7,'1 semana'],[30,'30 dias']];

/** QR Code da reserva: apresentado na entrada e na saída. Todos os responsáveis da criança veem o mesmo. */
export function ReservationPass({code,child,palette:p}:{code:string;child:string;palette:Palette}){
 const [open,setOpen]=useState(false);
 return <View style={{marginTop:8}}>
  <Pressable accessibilityRole="button" onPress={()=>setOpen(!open)} style={[s.btn,{backgroundColor:open?p.surface:p.brand,borderWidth:open?1:0,borderColor:p.line}]}><Text style={{color:open?p.text:onBrand(p.brand),fontWeight:'900'}}>{open?'Esconder QR Code':'Mostrar QR Code da reserva'}</Text></Pressable>
  {open&&<View style={{alignItems:'center',marginTop:10,gap:8}}><QrCode value={code} size={230}/>
   <Text style={{color:p.text,fontWeight:'800',textAlign:'center'}}>{child}</Text>
   <Text style={{color:p.muted,textAlign:'center',lineHeight:20}}>Mostre este QR Code na recepção para a entrada e de novo na saída. Não compartilhe com quem não pode buscar a criança.</Text></View>}
 </View>;
}

/** Responsáveis da criança: adicionar outro responsável fixo (pai, mãe, avó…) ou temporário, por e-mail ou celular. */
export function KidsGuardians({org,child,childName,palette:p}:{org:string;child:string;childName:string;palette:Palette}){
 const [items,setItems]=useState<Guardian[]|null>(null),[open,setOpen]=useState(false),[contact,setContact]=useState(''),[days,setDays]=useState(0),[busy,setBusy]=useState(false),[notice,setNotice]=useState('');
 const load=useCallback(async()=>{if(!supabase)return;const r=await supabase.rpc('member_kids_temporary',{p_org:org,p_action:'list',p_data:{profile:child}});setItems(r.error?[]:((r.data as {items?:Guardian[]})?.items||[]))},[org,child]);
 useEffect(()=>{void load()},[load]);
 async function grant(){
  if(!supabase||busy)return;setBusy(true);setNotice('');
  const r=await supabase.rpc('member_kids_temporary',{p_org:org,p_action:'grant',p_data:{profile:child,contact:contact.trim(),days}});
  setBusy(false);
  if(r.error){setNotice(/not_found/.test(r.error.message)?'Não achamos um membro com esse e-mail ou celular na igreja. Ele precisa ter conta no app.':/contact/.test(r.error.message)?'Digite o e-mail ou o celular com DDD.':'Não foi possível autorizar agora.');return}
  const d=r.data as {name?:string;until?:string|null;already?:boolean;fixed?:boolean};
  setNotice(d.already?(d.name+' já é responsável por '+childName.split(' ')[0]+'.'):d.fixed?(d.name+' agora é responsável por '+childName.split(' ')[0]+' e já pode buscar. A igreja vai conferir o vínculo.'):(d.name+' pode buscar '+childName.split(' ')[0]+' até '+br(String(d.until))+'. Ele recebe um aviso no app.'));
  setContact('');setOpen(false);void load();
 }
 async function revoke(g:Guardian){if(!supabase)return;setBusy(true);await supabase.rpc('member_kids_temporary',{p_org:org,p_action:'revoke',p_data:{profile:child,id:g.id}});setBusy(false);setNotice('Autorização de '+g.name.split(' ')[0]+' retirada.');void load()}
 if(!items)return null;
 return <View style={[s.box,{borderColor:p.line}]}>
  <Text style={[s.over,{color:p.accent}]}>RESPONSÁVEIS</Text>
  {items.map(g=><View key={g.id} style={s.row}><View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{g.name}{g.me?' (você)':''}</Text>
   <Text style={{color:p.muted,fontSize:12}}>{g.temporary?'Temporário até '+br(String(g.validUntil)):g.relationship}{!g.canPickup?' · não busca':''}</Text></View>
   {(g.removable??g.temporary)&&<Pressable accessibilityRole="button" disabled={busy} onPress={()=>void revoke(g)}><Text style={{color:p.muted,fontWeight:'800'}}>Retirar</Text></Pressable>}</View>)}
  {!!notice&&<Text accessibilityRole="alert" style={{color:p.text,marginTop:6,lineHeight:20}}>{notice}</Text>}
  {!open?<Pressable accessibilityRole="button" onPress={()=>{setOpen(true);setNotice('')}}><Text style={{color:p.accent,fontWeight:'800',marginTop:8}}>+ Adicionar responsável</Text></Pressable>
  :<View style={{marginTop:8,gap:8}}>
   <Text style={{color:p.muted,lineHeight:20}}>A pessoa precisa ser membro com conta no app. {days===0?'Responsável fixo: pode buscar '+childName.split(' ')[0]+' sempre (a igreja confere o vínculo).':'Temporário: pode buscar '+childName.split(' ')[0]+' só no período escolhido.'}</Text>
   <TextInput accessibilityLabel="E-mail ou celular do membro" value={contact} onChangeText={setContact} autoCapitalize="none" keyboardType="email-address" placeholder="E-mail ou celular" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
   <View style={{flexDirection:'row',flexWrap:'wrap',gap:6}}>{([[0,'Fixo'],...dayOptions] as [number,string][]).map(([d,l])=><Pressable key={d} accessibilityRole="radio" accessibilityState={{checked:days===d}} onPress={()=>setDays(d)} style={[s.chip,{borderColor:days===d?p.accent:p.line,backgroundColor:days===d?p.accent:p.surface}]}><Text style={{color:days===d?onBrand(p.accent):p.text,fontWeight:'700'}}>{l}</Text></Pressable>)}</View>
   <View style={{flexDirection:'row',gap:10}}><Pressable accessibilityRole="button" disabled={busy||contact.trim().length<5} onPress={()=>void grant()} style={[s.btn,{flex:1,backgroundColor:p.brand,opacity:busy||contact.trim().length<5?.5:1}]}><Text style={{color:onBrand(p.brand),fontWeight:'900'}}>{days===0?'Adicionar responsável':'Autorizar'}</Text></Pressable>
    <Pressable accessibilityRole="button" onPress={()=>setOpen(false)} style={[s.btn,{borderWidth:1,borderColor:p.line,paddingHorizontal:16}]}><Text style={{color:p.text,fontWeight:'800'}}>Cancelar</Text></Pressable></View>
  </View>}
 </View>;
}
const s=StyleSheet.create({box:{borderTopWidth:1,marginTop:12,paddingTop:10},over:{fontSize:11,fontWeight:'800',letterSpacing:1.6,marginBottom:6},row:{flexDirection:'row',alignItems:'center',gap:10,paddingVertical:5},
 btn:{minHeight:46,borderRadius:16,alignItems:'center',justifyContent:'center'},input:{borderWidth:1,borderRadius:14,padding:12,fontSize:16},chip:{borderWidth:1,borderRadius:18,paddingHorizontal:12,paddingVertical:7}});
