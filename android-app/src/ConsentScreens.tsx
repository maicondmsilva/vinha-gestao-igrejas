import {useCallback,useEffect,useState} from 'react';
import {ActivityIndicator,Linking,Platform,Pressable,ScrollView,StyleSheet,Text,TextInput,View} from 'react-native';
import {randomUUID} from 'expo-crypto';
import {supabase} from './supabase';
import {onBrand} from './experience-model';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent:string};
export type ConsentKind=string;
type Template={version:number;title:string;body:string};
export type ConsentItem={id:string;code:string;kind:ConsentKind;version:number;title:string;choices:Record<string,boolean>;signerName:string;subjectName:string;kidsProfile:string|null;acceptedAt:string;sha256:string};
type Data={templates:Record<ConsentKind,Template>;items:ConsentItem[];custom?:{kind:string;title:string;audience:'adult'|'kids'}[]};
const choiceLabels:[string,string][]=[['photos','Fotos'],['videos','Vídeos'],['social','Redes sociais da igreja'],['live','Transmissões ao vivo']];
const fixedShort:Record<string,string>={adult_data:'Dados pessoais',adult_image:'Uso de imagem e voz',kids_guardian:'Responsável pela criança',kids_image:'Imagem da criança'};
const device=()=>(Platform.OS==='android'?'Android ':Platform.OS==='ios'?'iOS ':'')+String(Platform.Version||'')+' · aplicativo da igreja';

/** Termos da conta: textos vigentes da igreja e aceites válidos. */
export function useConsents(org:string,unit:string,authenticated:boolean){
 const [data,setData]=useState<Data|null>(null),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;setData(null);if(!authenticated||!supabase||!unit)return;
  void supabase.rpc('member_consent',{p_org:org,p_unit:unit,p_action:'list',p_data:{}}).then(r=>{if(live&&!r.error)setData(r.data as Data)});
  return()=>{live=false}},[org,unit,authenticated,rev]);
 return {data,refresh:useCallback(()=>setRev(n=>n+1),[])};
}

async function openPdf(org:string,unit:string,id:string){
 const r=await supabase!.rpc('member_consent',{p_org:org,p_unit:unit,p_action:'link',p_data:{id}});
 const token=(r.data as {token?:string})?.token;if(r.error||!token)throw Error('Não foi possível abrir o documento agora.');
 await Linking.openURL('https://app.vinhaigrejas.com.br/api/consent/pdf?t='+token);
}

/** Leitura e assinatura eletrônica de um termo: texto completo, escolhas de imagem, nome digitado e "Li e concordo". */
function SignForm({org,unit,kind,child,childName,template,palette:p,defaultName,onDone,onCancel}:{org:string;unit:string;kind:ConsentKind;child?:string;childName?:string;template:Template;palette:Palette;defaultName:string;onDone:(i:ConsentItem)=>void;onCancel:()=>void}){
 const image=kind==='adult_image'||kind==='kids_image',ac=p.accent;
 const [choices,setChoices]=useState<Record<string,boolean>>({photos:true,videos:true,social:true,live:true}),[name,setName]=useState(defaultName),[agree,setAgree]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[id]=useState(randomUUID());
 async function sign(){
  if(name.trim().split(/\s+/).length<2){setError('Digite seu nome e sobrenome como assinatura.');return}
  if(!agree){setError('Marque "Li e concordo" para assinar.');return}
  setBusy(true);setError('');
  const r=await supabase!.rpc('member_consent',{p_org:org,p_unit:unit,p_action:'sign',p_data:{id,kind,signerName:name.trim(),device:device(),...(image?{choices}:{}),...(child?{child}:{})}});
  setBusy(false);
  if(r.error){setError(/denied/.test(r.error.message)?'Só o responsável aprovado pode assinar pela criança.':'Não foi possível assinar agora. Tente de novo.');return}
  onDone((r.data as {item:ConsentItem}).item);
 }
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:ac}]}>
  <Text style={[s.over,{color:ac}]}>{(fixedShort[kind]||template.title).toUpperCase()}{childName?' · '+childName.toUpperCase():''}</Text>
  <Text style={{color:p.text,fontWeight:'900',fontSize:17}}>{template.title}</Text>
  <ScrollView nestedScrollEnabled style={[s.body,{borderColor:p.line,backgroundColor:p.bg}]}><Text style={{color:p.text,lineHeight:22}}>{template.body}</Text></ScrollView>
  {image&&<><Text style={{color:p.text,fontWeight:'800',marginTop:10}}>{kind==='kids_image'?'O que você autoriza para a criança':'O que você autoriza'}</Text>
   <View style={s.wrap}>{choiceLabels.map(([k,l])=>{const on=choices[k];return <Pressable key={k} accessibilityRole="checkbox" accessibilityState={{checked:on}} onPress={()=>setChoices({...choices,[k]:!on})} style={[s.chip,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{on?'✓ ':''}{l}</Text></Pressable>})}</View>
   <Text style={{color:p.muted,fontSize:12,marginTop:4}}>Desmarque o que não autoriza. Pode mudar depois assinando de novo.</Text></>}
  <Text style={{color:p.text,fontWeight:'800',marginTop:12}}>Assinatura (nome completo)</Text>
  <TextInput accessibilityLabel="Nome completo como assinatura" value={name} onChangeText={setName} autoCapitalize="words" maxLength={160} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg}]}/>
  <Pressable accessibilityRole="checkbox" accessibilityState={{checked:agree}} onPress={()=>setAgree(!agree)} style={s.row}><View style={[s.box,{borderColor:agree?ac:p.muted,backgroundColor:agree?ac:'transparent'}]}>{agree&&<Text style={{color:onBrand(ac),fontWeight:'900',fontSize:12}}>✓</Text>}</View><Text style={{color:p.text,flex:1,lineHeight:20}}>Li e concordo com este termo{child?' como responsável pela criança':''}.</Text></Pressable>
  {!!error&&<Text accessibilityRole="alert" style={{color:'#b8741a',fontWeight:'700',marginTop:6}}>{error}</Text>}
  <Pressable accessibilityRole="button" disabled={busy} onPress={()=>void sign()} style={[s.primary,{backgroundColor:p.brand,opacity:busy?.6:1}]}>{busy?<ActivityIndicator color={onBrand(p.brand)}/>:<Text style={{color:onBrand(p.brand),fontWeight:'900'}}>Assinar eletronicamente</Text>}</Pressable>
  <Pressable accessibilityRole="button" onPress={onCancel}><Text style={{color:p.muted,fontWeight:'700',textAlign:'center',marginTop:10}}>Agora não</Text></Pressable>
  <Text style={{color:p.muted,fontSize:11,marginTop:8,lineHeight:16}}>Ao assinar, registramos seu nome, data e hora, aparelho e conta. O documento recebe um código e uma impressão digital para conferência.</Text>
 </View>;
}

/** Bloco de termos: mostra o que está assinado (com PDF e código) e permite assinar o que falta. */
export function ConsentBlock({org,unit,kinds,child,childName,data,palette:p,defaultName,onChanged}:{org:string;unit:string;kinds:ConsentKind[];child?:string;childName?:string;data:Data|null;palette:Palette;defaultName:string;onChanged:()=>void}){
 const [signing,setSigning]=useState<ConsentKind|null>(null),[notice,setNotice]=useState(''),ac=p.accent;
 if(!data)return null;
 // Termos criados pela igreja entram junto: os de adulto no perfil, os de criança no Kids.
 const kids=kinds.some(k=>k.startsWith('kids_')),all=[...kinds,...(data.custom||[]).filter(c=>(c.audience==='kids')===kids&&data.templates[c.kind]).map(c=>c.kind)];
 const short=(k:string)=>fixedShort[k]||data.templates[k]?.title||'Termo';
 const mine=(k:ConsentKind)=>data.items.find(i=>i.kind===k&&(child?i.kidsProfile===child:!i.kidsProfile));
 return <View>
  {!!notice&&<Text accessibilityRole="alert" style={{color:p.text,marginBottom:6}}>{notice}</Text>}
  {all.map(k=>{const it=mine(k);if(signing===k)return <SignForm key={k} org={org} unit={unit} kind={k} child={child} childName={childName} template={data.templates[k]} palette={p} defaultName={defaultName} onCancel={()=>setSigning(null)} onDone={i=>{setSigning(null);setNotice('Termo assinado. Código '+i.code+'.');onChanged()}}/>;
   return <View key={k} style={[s.line,{borderColor:p.line}]}>
    <View style={[s.dot,{backgroundColor:it?ac:'transparent',borderColor:it?ac:p.muted}]}>{it&&<Text style={{color:onBrand(ac),fontSize:11,fontWeight:'900'}}>✓</Text>}</View>
    <View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{short(k)}</Text>
     <Text style={{color:p.muted,fontSize:12}}>{it?`Assinado em ${new Date(it.acceptedAt).toLocaleDateString('pt-BR')} · ${it.code}`+(Object.keys(it.choices||{}).length?' · '+choiceLabels.filter(([c])=>it.choices[c]).map(([,l])=>l).join(', ')||' · nenhuma autorização':''):'Ainda não assinado'}</Text></View>
    {it?<Pressable accessibilityRole="link" onPress={()=>void openPdf(org,unit,it.id).catch(e=>setNotice(e.message))}><Text style={{color:ac,fontWeight:'800'}}>PDF</Text></Pressable>:null}
    <Pressable accessibilityRole="button" onPress={()=>{setNotice('');setSigning(k)}} style={[s.small,{backgroundColor:it?'transparent':p.brand,borderWidth:it?1:0,borderColor:p.line}]}><Text style={{color:it?p.text:onBrand(p.brand),fontWeight:'800',fontSize:13}}>{it?'Atualizar':'Assinar'}</Text></Pressable>
   </View>})}
 </View>;
}
const s=StyleSheet.create({
 card:{borderWidth:1.5,borderRadius:20,padding:14,marginVertical:8},over:{fontSize:11,fontWeight:'800',letterSpacing:1.6,marginBottom:4},
 body:{maxHeight:220,borderWidth:1,borderRadius:14,padding:12,marginTop:10},wrap:{flexDirection:'row',flexWrap:'wrap',gap:8,marginTop:8},chip:{borderWidth:1,borderRadius:18,paddingHorizontal:12,paddingVertical:8},
 input:{borderWidth:1,borderRadius:14,padding:12,fontSize:16,marginTop:6,minHeight:48},row:{flexDirection:'row',gap:10,alignItems:'center',marginTop:12},
 box:{width:22,height:22,borderRadius:7,borderWidth:2,alignItems:'center',justifyContent:'center'},primary:{borderRadius:16,minHeight:50,alignItems:'center',justifyContent:'center',marginTop:12},
 line:{flexDirection:'row',alignItems:'center',gap:10,borderTopWidth:1,paddingVertical:10},dot:{width:22,height:22,borderRadius:11,borderWidth:2,alignItems:'center',justifyContent:'center'},small:{paddingHorizontal:12,paddingVertical:8,borderRadius:16},
});
