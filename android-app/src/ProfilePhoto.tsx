import {useCallback,useEffect,useState} from 'react';
import {ActivityIndicator,Alert,Image,Pressable,StyleSheet,Text,View} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import {manipulateAsync,SaveFormat} from 'expo-image-manipulator';
import {File} from 'expo-file-system';
import {supabase} from './supabase';
import {initials} from '../../shared/cell-leader';

const bucket='member-photos';
const objectPath=(stored:string)=>stored.replace(/^member-photos\//,'');

/** Link temporário (1 hora) para uma foto guardada no espaço privado. */
export async function photoUrl(stored:string){
 if(!supabase||!stored)return '';
 const r=await supabase.storage.from(bucket).createSignedUrl(objectPath(stored),3600);
 return r.data?.signedUrl||'';
}

/** Escolhe (galeria ou câmera), recorta quadrada, reduz para 512 px e envia. Retorna o caminho gravado ou ''. */
export async function pickAndUpload(org:string,target:'profile'|{child:string}):Promise<string>{
 if(!supabase)return '';
 const choice=await new Promise<'camera'|'library'|null>(resolve=>Alert.alert('Foto','De onde vem a foto?',[{text:'Câmera',onPress:()=>resolve('camera')},{text:'Galeria',onPress:()=>resolve('library')},{text:'Cancelar',style:'cancel',onPress:()=>resolve(null)}],{cancelable:true,onDismiss:()=>resolve(null)}));
 if(!choice)return '';
 const perm=choice==='camera'?await ImagePicker.requestCameraPermissionsAsync():await ImagePicker.requestMediaLibraryPermissionsAsync();
 if(!perm.granted)throw Error(choice==='camera'?'Permita o uso da câmera nas configurações do celular.':'Permita o acesso às fotos nas configurações do celular.');
 const options:ImagePicker.ImagePickerOptions={mediaTypes:['images'],allowsEditing:true,aspect:[1,1],quality:.9};
 const picked=choice==='camera'?await ImagePicker.launchCameraAsync(options):await ImagePicker.launchImageLibraryAsync(options);
 if(picked.canceled||!picked.assets?.[0])return '';
 const small=await manipulateAsync(picked.assets[0].uri,[{resize:{width:512,height:512}}],{compress:.78,format:SaveFormat.JPEG});
 const user=(await supabase.auth.getUser()).data.user;if(!user)throw Error('Entre na sua conta.');
 const path=org+'/'+user.id+'/'+(target==='profile'?'profile':'kids/'+target.child)+'.jpg';
 const bytes=await new File(small.uri).arrayBuffer();
 const up=await supabase.storage.from(bucket).upload(path,bytes,{upsert:true,contentType:'image/jpeg'});
 if(up.error)throw Error('Não foi possível enviar a foto. Tente de novo.');
 const r=await supabase.rpc('member_photo',{p_org:org,p_action:target==='profile'?'set':'child_set',p_child:target==='profile'?null:target.child});
 if(r.error)throw Error('A foto foi enviada, mas não foi gravada no cadastro. Tente de novo.');
 return String((r.data as {path?:string})?.path||'');
}

/** Foto da própria conta (o caminho vem do cadastro de membros ou da conta, antes da aprovação). */
export function useMyPhoto(org:string,authenticated:boolean){
 const [url,setUrl]=useState(''),[rev,setRev]=useState(0);
 useEffect(()=>{let live=true;setUrl('');if(!authenticated||!supabase)return;
  void supabase.rpc('member_photo',{p_org:org,p_action:'get'}).then(async r=>{const p=String((r.data as {path?:string})?.path||'');const u=p?await photoUrl(p):'';if(live)setUrl(u?u+'&v='+rev:'')});
  return()=>{live=false}},[org,authenticated,rev]);
 return {url,refresh:useCallback(()=>setRev(n=>n+1),[])};
}

/** Círculo com a foto (ou as iniciais) e, se `onChange`, o toque troca a foto. */
export function Avatar({url,name,size=56,color,background,onChange,label='Trocar foto'}:{url:string;name:string;size?:number;color:string;background:string;onChange?:()=>Promise<void>;label?:string}){
 const [busy,setBusy]=useState(false);
 const inner=<View style={[s.circle,{width:size,height:size,borderRadius:size/2,backgroundColor:background}]}>{url?<Image source={{uri:url}} style={{width:size,height:size,borderRadius:size/2}}/>:<Text style={{color,fontWeight:'900',fontSize:size*.36}}>{initials(name)}</Text>}{busy&&<View style={[StyleSheet.absoluteFill,s.busy,{borderRadius:size/2}]}><ActivityIndicator color="#fff"/></View>}</View>;
 if(!onChange)return inner;
 return <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={busy} onPress={()=>{setBusy(true);void onChange().finally(()=>setBusy(false))}}>{inner}<View style={[s.badge,{backgroundColor:color}]}><Text style={{color:background,fontWeight:'900',fontSize:12}}>✎</Text></View></Pressable>;
}
const s=StyleSheet.create({circle:{alignItems:'center',justifyContent:'center',overflow:'hidden'},busy:{backgroundColor:'#0006',alignItems:'center',justifyContent:'center'},badge:{position:'absolute',right:-2,bottom:-2,width:22,height:22,borderRadius:11,alignItems:'center',justifyContent:'center'}});

/** Foto da criança no Kids: o responsável que pode editar o cadastro toca para trocar. */
export function ChildPhoto({org,child,name,stored,canEdit,color,background,onSaved,onError}:{org:string;child:string;name:string;stored?:string;canEdit:boolean;color:string;background:string;onSaved:()=>void;onError:(m:string)=>void}){
 const [url,setUrl]=useState('');
 useEffect(()=>{let live=true;setUrl('');if(stored)void photoUrl(stored).then(u=>{if(live)setUrl(u)});return()=>{live=false}},[stored]);
 return <Avatar url={url} name={name} size={64} color={color} background={background} label={'Trocar a foto de '+name} onChange={canEdit?async()=>{try{const p=await pickAndUpload(org,{child});if(p){setUrl((await photoUrl(p))+'&v='+Date.now());onSaved()}}catch(e){onError(e instanceof Error?e.message:'Não foi possível trocar a foto.')}}:undefined}/>;
}
