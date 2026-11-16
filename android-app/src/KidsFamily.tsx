import {useState} from 'react';
import {Pressable,StyleSheet,Text,TextInput,View} from 'react-native';
import KidsCareFields from './KidsCareFields';
import {ChildPhoto} from './ProfilePhoto';
import {ConsentBlock} from './ConsentScreens';
import {KidsGuardians,ReservationPass} from './KidsGuardians';
import {familyDate,familyStatus,type FamilyBooking,type FamilyChild,type FamilyPage,type FamilySession} from '../../shared/member-family';
import {childAge,childNextBooking} from '../../shared/kids-family';
import {guardianRelations,isKinship} from '../../shared/kids-relations';
import {onBrand} from './experience-model';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
type Family={page:FamilyPage|null;sessions:FamilySession[];busy:boolean;command:(a:string,id?:string|null,v?:number|null,d?:Record<string,unknown>)=>Promise<boolean>;refresh:()=>void};
type Consents=Parameters<typeof ConsentBlock>[0]['data'];

/** Área Kids da família: um cartão por criança com a ação principal (reservar ou mostrar o QR) e os detalhes recolhidos. */
export default function KidsFamily({m,org,unit,palette:p,consents,refreshConsents,selected,select,onError}:{m:Family;org:string;unit:string;palette:Palette;consents:Consents;refreshConsents:()=>void;selected:string;select:(id:string)=>void;onError:(t:string)=>void}){
 const [details,setDetails]=useState(''),[history,setHistory]=useState(false),[form,setForm]=useState<{id:string;name:string;birth:string;care:string;relation:string}|null>(null),[problem,setProblem]=useState('');
 const children=m.page?.children||[],bookings=m.page?.reservations||[];
 const primary=(t:string,fn:()=>void,disabled=false)=><Pressable accessibilityRole="button" disabled={disabled} onPress={fn} style={[s.primary,{backgroundColor:p.brand,opacity:disabled?.5:1}]}><Text style={{color:onBrand(p.brand),fontWeight:'900',fontSize:16}}>{t}</Text></Pressable>;
 const link=(t:string,fn:()=>void)=><Pressable accessibilityRole="button" onPress={fn} hitSlop={8}><Text style={{color:p.accent,fontWeight:'800'}}>{t}</Text></Pressable>;
 async function submit(){if(!form)return;const [dd,mm,yyyy]=form.birth.split('/'),date=yyyy+'-'+mm+'-'+dd;if(form.name.trim().length<2||!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date+'T12:00:00Z').toISOString().slice(0,10)!==date){setProblem('Informe o nome e a data no formato dia/mês/ano.');return}if(!form.id&&!form.relation){setProblem('Escolha o que você é da criança.');return}if(await m.command(form.id?'kids.edit':'kids.create',form.id||null,null,{name:form.name,birth:date,care:form.care,...(form.id?{}:{relation:form.relation})}))setForm(null)}
 const status=(b:FamilyBooking)=>b.attendance==='present'?{label:'Na sala agora'+(b.room?' · '+b.room:''),color:'#2f7a4f'}:b.attendance==='out'?{label:'Já saiu',color:p.muted}:{label:'Vaga reservada',color:p.accent};
 return <View style={{gap:12}}>
  {!children.length&&!m.page?.requests?.length&&<View style={[s.card,{backgroundColor:p.surface,borderColor:p.line}]}><Text style={[s.name,{color:p.text}]}>Nenhuma criança ainda</Text><Text style={{color:p.muted,lineHeight:21}}>Cadastre sua criança e já reserve a vaga. A igreja confere o cadastro depois.</Text></View>}
  {children.map((c:FamilyChild)=>{const b=childNextBooking(bookings,c.id),st=b&&status(b),open=details===c.id,choosing=selected===c.id;
   return <View key={c.id} style={[s.card,{backgroundColor:p.surface,borderColor:b?.attendance==='present'?'#2f7a4f':p.line}]}>
    <View style={s.head}>
     <ChildPhoto org={org} child={c.id} name={c.name} stored={c.photo} canEdit={!!c.can_edit} color={p.brand} background={p.bg} onSaved={m.refresh} onError={onError}/>
     <View style={{flex:1}}><Text style={[s.name,{color:p.text}]}>{c.name}</Text><Text style={{color:p.muted}}>{childAge(c.birth)}{!c.photo&&c.can_edit?' · toque na foto para adicionar':''}</Text></View>
    </View>
    {b&&<View style={[s.next,{backgroundColor:p.bg}]}><Text style={{color:st!.color,fontWeight:'900'}}>{st!.label}</Text><Text style={{color:p.text}}>{b.session} · {familyDate(b.starts_at)}</Text></View>}
    {b?.pass?<ReservationPass code={b.pass} child={c.name} palette={p}/>:c.can_pickup&&!choosing&&primary('Reservar vaga',()=>select(c.id),m.busy)}
    {choosing&&<View style={{gap:8}}>
     <Text style={{color:p.text,fontWeight:'800'}}>Escolha a sessão</Text>
     {!m.sessions.length&&<Text style={{color:p.muted}}>Nenhuma sessão com vaga para a idade agora. As sessões aparecem com antecedência.</Text>}
     {m.sessions.map(t=><Pressable key={t.id} accessibilityRole="button" disabled={m.busy||t.available<1} onPress={()=>void m.command('kids.reserve',t.id,null,{profile:c.id}).then(ok=>ok&&select(''))} style={[s.session,{borderColor:p.line,opacity:t.available<1?.5:1}]}>
      <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{t.name}</Text><Text style={{color:p.muted}}>{familyDate(t.starts_at)} · {t.room}</Text></View>
      <Text style={{color:t.available<1?p.muted:p.accent,fontWeight:'900'}}>{t.available<1?'Lotado':'Reservar ›'}</Text></Pressable>)}
     {link('Cancelar',()=>select(''))}
    </View>}
    <View style={s.links}>
     {b&&b.status==='reserved'&&!b.attendance&&b.can_pickup&&link('Cancelar reserva',()=>void m.command('kids.cancel',b.id,b.version))}
     {b&&b.attendance==='present'&&!b.pickup_requested_at&&b.can_pickup&&link('Avisar que vou buscar',()=>void m.command('kids.pickup',b.id,b.version))}
     {b?.pickup_requested_at&&b.attendance==='present'&&<Text style={{color:p.muted}}>Retirada avisada à recepção.</Text>}
     {link(open?'Fechar detalhes':'Detalhes',()=>setDetails(open?'':c.id))}
    </View>
    {open&&<View style={[s.details,{borderColor:p.line}]}>
     <Text style={{color:p.muted}}>Nascimento: {c.birth.split('-').reverse().join('/')}</Text>
     <KidsGuardians org={org} child={c.id} childName={c.name} palette={p}/>
     <ConsentBlock org={org} unit={unit} kinds={['kids_guardian','kids_image']} child={c.id} childName={c.name} data={consents} palette={p} defaultName='' onChanged={refreshConsents}/>
     {c.can_edit&&link('Atualizar dados e cuidados',()=>{setProblem('');setForm({id:c.id,name:c.name,birth:c.birth.split('-').reverse().join('/'),care:c.care||'',relation:''})})}
    </View>}
   </View>})}

  {form?<View style={[s.card,{backgroundColor:p.surface,borderColor:p.accent}]}>
   <Text style={[s.name,{color:p.text}]}>{form.id?'Atualizar dados':'Cadastrar criança'}</Text>
   <TextInput accessibilityLabel="Nome da criança" value={form.name} onChangeText={v=>setForm({...form,name:v})} maxLength={160} placeholder="Nome completo" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
   <TextInput accessibilityLabel="Nascimento" value={form.birth} keyboardType="number-pad" onChangeText={v=>setForm({...form,birth:v.replace(/\D/g,'').slice(0,8).replace(/^(\d{2})(\d)/,'$1/$2').replace(/^(\d{2}\/\d{2})(\d)/,'$1/$2')})} maxLength={10} placeholder="Nascimento (dd/mm/aaaa)" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
   {!form.id&&<View style={{gap:8}}>
    <Text style={{color:p.text,fontWeight:'800'}}>Você é da criança</Text>
    <View style={{flexDirection:'row',flexWrap:'wrap',gap:8}}>{guardianRelations.map(([k,l])=>{const on=form.relation===k;return <Pressable key={k} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={()=>{setProblem('');setForm({...form,relation:k})}} style={[s.chip,{borderColor:on?p.brand:p.line,backgroundColor:on?p.brand:p.bg}]}><Text style={{color:on?onBrand(p.brand):p.text,fontWeight:'700'}}>{l}</Text></Pressable>})}</View>
    {!!form.relation&&<Text style={{color:p.muted,fontSize:12,lineHeight:18}}>{isKinship(form.relation)?'A criança entra na sua família no cadastro da igreja.':'Você poderá buscar a criança, mas ela não entra na sua família.'}</Text>}
   </View>}
   <KidsCareFields key={form.id||'new'} value={form.care} onChange={v=>setForm(f=>f?{...f,care:v}:null)} palette={p}/>
   {!!problem&&<Text accessibilityRole="alert" style={{color:'#b8741a',fontWeight:'700'}}>{problem}</Text>}
   {primary(form.id?'Enviar alteração para a igreja':'Cadastrar criança',()=>void submit(),m.busy)}
   {!form.id&&<Text style={{color:p.muted,lineHeight:20}}>O cadastro fica ativo na hora. A secretaria confere os dados e o vínculo depois.</Text>}
   {link('Cancelar',()=>setForm(null))}
  </View>:<Pressable accessibilityRole="button" onPress={()=>{setProblem('');setForm({id:'',name:'',birth:'',care:'',relation:''})}} style={[s.add,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'800'}}>+ Cadastrar criança</Text></Pressable>}

  {(!!m.page?.presence?.length||!!m.page?.requests?.length||bookings.length>0)&&<View>
   <Pressable accessibilityRole="button" onPress={()=>setHistory(!history)} style={s.histHead}><Text style={{color:p.text,fontWeight:'800'}}>Histórico</Text><Text style={{color:p.muted}}>{history?'Fechar':'Ver'}</Text></Pressable>
   {history&&<View style={{gap:6}}>
    {m.page?.presence?.map(a=><Text key={a.id} style={{color:p.muted}}>{a.name} · {a.session} · {familyStatus[a.status]} · {familyDate(a.checked_in_at)}</Text>)}
    {bookings.filter(r=>r.status!=='reserved').map(r=><Text key={r.id} style={{color:p.muted}}>{r.name} · {r.session} · {familyStatus[r.status]||r.status}</Text>)}
    {m.page?.requests?.map(r=><View key={r.id} style={{flexDirection:'row',gap:8,alignItems:'center'}}><Text style={{color:p.muted,flex:1}}>{r.kind==='kids.create'?'Cadastro':'Alteração'}: {r.data?.name||'criança'} · {r.kind==='kids.create'&&r.status==='pending'?'Ativo · a igreja vai conferir':r.kind==='kids.create'&&r.status==='approved'?'Conferido pela igreja':familyStatus[r.status]||r.status}{r.reason?' · '+r.reason:''}</Text>{r.status==='pending'&&r.kind!=='kids.create'&&link('Cancelar',()=>void m.command('request.cancel',r.id,r.version))}</View>)}
   </View>}
  </View>}
 </View>;
}
const s=StyleSheet.create({card:{borderWidth:1.5,borderRadius:22,padding:16,gap:12},head:{flexDirection:'row',alignItems:'center',gap:14},name:{fontSize:19,fontWeight:'900'},
 next:{borderRadius:14,padding:12,gap:2},primary:{minHeight:52,borderRadius:16,alignItems:'center',justifyContent:'center'},session:{flexDirection:'row',alignItems:'center',gap:10,borderWidth:1,borderRadius:14,padding:12},
 links:{flexDirection:'row',flexWrap:'wrap',gap:18,alignItems:'center'},details:{borderTopWidth:1,paddingTop:12,gap:8},input:{borderWidth:1,borderRadius:14,padding:12,fontSize:16,minHeight:48},
 add:{borderWidth:1.5,borderStyle:'dashed',borderRadius:18,padding:16,alignItems:'center'},chip:{borderWidth:1.5,borderRadius:18,paddingHorizontal:12,paddingVertical:8},histHead:{flexDirection:'row',justifyContent:'space-between',paddingVertical:10}});
