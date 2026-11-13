import {useEffect,useState} from 'react';
import {ActivityIndicator,Image,Linking,Pressable,ScrollView,Share,StyleSheet,Text,View} from 'react-native';
import type {ChurchRpc,PublicPost} from '../../shared/member-church';
import {appImage} from '../../shared/app-images';
import RichText from './RichText';
import Icon from './Icon';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};
const chip=(p:Palette,label:string,on:boolean,press:()=>void)=><Pressable key={label} accessibilityRole="button" accessibilityState={{selected:on}} onPress={press} style={[s.chip,{borderColor:on?(p.accent||p.brand):p.line,backgroundColor:on?(p.accent||p.brand):p.surface}]}><Text style={{color:on?'#fff':p.text,fontWeight:'700'}}>{label}</Text></Pressable>;

/** Arquivos e estudos publicados pela igreja (Comunicação › Arquivos), por categoria. */
export function NativeFiles({posts,palette:p}:{posts:PublicPost[];palette:Palette}){
 const files=posts.filter(f=>f.kind==='file'),cats=[...new Set(files.map(f=>(f as PublicPost&{category?:string}).category||'').filter(Boolean))].sort((a,b)=>a.localeCompare(b,'pt-BR'));
 const [cat,setCat]=useState('');const list=files.filter(f=>!cat||(f as PublicPost&{category?:string}).category===cat);
 return <View>
  <Text accessibilityRole="header" style={[s.h1,{color:p.text}]}>Arquivos e estudos</Text>
  <Text style={{color:p.muted,marginBottom:10}}>Materiais publicados pela igreja para baixar ou compartilhar.</Text>
  {cats.length>0&&<ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8,paddingVertical:6}}>{chip(p,'Todos',!cat,()=>setCat(''))}{cats.map(c=>chip(p,c,cat===c,()=>setCat(c)))}</ScrollView>}
  {list.map(f=>{const img=appImage(f.image),category=(f as PublicPost&{category?:string}).category;return <View key={f.id} style={[s.file,{backgroundColor:p.surface,borderColor:p.line}]}>
   {img?<Image source={{uri:img}} resizeMode="cover" style={s.thumb}/>:<View style={[s.thumb,{backgroundColor:p.line,alignItems:'center',justifyContent:'center'}]}><Icon name="bible" color={p.accent||p.brand} size={28}/></View>}
   <View style={{flex:1}}>
    <Text numberOfLines={2} style={{color:p.text,fontWeight:'800',fontSize:16}}>{f.title}</Text>
    {!!category&&<Text style={{color:p.accent||p.brand,fontWeight:'700',marginTop:2}}>{category}</Text>}
    <View style={{flexDirection:'row',gap:8,marginTop:10}}>
     <Pressable accessibilityRole="button" accessibilityLabel={'Abrir '+f.title} onPress={()=>void Linking.openURL(f.url).catch(()=>undefined)} style={[s.btn,{backgroundColor:p.accent||p.brand}]}><Text style={{color:'#fff',fontWeight:'800'}}>Abrir</Text></Pressable>
     {f.share!==false&&<Pressable accessibilityRole="button" accessibilityLabel={'Compartilhar '+f.title} onPress={()=>void Share.share({message:f.title+'\n'+f.url})} style={[s.btn,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>Compartilhar</Text></Pressable>}
    </View>
   </View>
  </View>})}
  {!list.length&&<Text style={{color:p.muted,marginTop:12}}>Nenhum arquivo publicado pela igreja.</Text>}
 </View>;
}

type Page={id:string;title:string;body:string;image:string};
/** Conheça a igreja (Comunicação › Páginas da igreja): grade de cartões com capa; ao tocar, a página abre inteira. */
export function NativePages({rpc,org,unit,palette:p,dark}:{rpc:ChurchRpc;org:string;unit:string;palette:Palette;dark:boolean}){
 const ac=p.accent||p.brand,[pages,setPages]=useState<Page[]|null>(null),[error,setError]=useState(''),[sel,setSel]=useState('');
 useEffect(()=>{let live=true;if(!unit)return;void Promise.resolve(rpc.rpc('member_church_pages',{p_org:org,p_unit:unit})).then(r=>{if(!live)return;if(r.error)throw Error();setPages(((r.data as {items?:Page[]})?.items)||[])}).catch(()=>{if(live)setError('Não foi possível carregar as páginas da igreja.')});return()=>{live=false}},[rpc,org,unit]);
 const page=pages?.find(x=>x.id===sel);
 if(page){const img=appImage(page.image);return <View>
  <Pressable accessibilityRole="button" onPress={()=>setSel('')} style={{paddingVertical:8}}><Text style={{color:ac,fontWeight:'800'}}>← Conheça a igreja</Text></Pressable>
  {img&&<Image source={{uri:img}} resizeMode="cover" style={s.cover}/>}
  <Text accessibilityRole="header" style={[s.h2,{color:p.text}]}>{page.title}</Text>
  <RichText body={page.body} color={p.text} muted={p.muted} accent={dark?p.text:ac}/>
 </View>}
 return <View>
  <Text accessibilityRole="header" style={[s.h1,{color:p.text}]}>Conheça a igreja</Text>
  <Text style={{color:p.muted,marginBottom:12}}>Nossa história, nossas células e o jeito de ser desta igreja.</Text>
  {error?<Text accessibilityRole="alert" style={{color:p.text}}>{error}</Text>:!pages?<ActivityIndicator color={ac}/>:!pages.length?<Text style={{color:p.muted}}>A igreja ainda não publicou páginas de apresentação.</Text>:
   <View style={s.grid}>{pages.map(x=>{const img=appImage(x.image);return <Pressable key={x.id} accessibilityRole="button" accessibilityLabel={'Abrir '+x.title} onPress={()=>setSel(x.id)} style={[s.card,{borderColor:p.line,backgroundColor:p.surface}]}>
    {img?<Image source={{uri:img}} resizeMode="cover" style={s.cardImg}/>:<View style={[s.cardImg,{backgroundColor:p.line,alignItems:'center',justifyContent:'center'}]}><Icon name="cells" color={ac} size={30}/></View>}
    <Text numberOfLines={2} style={{color:p.text,fontWeight:'800',padding:10}}>{x.title}</Text>
   </Pressable>})}</View>}
 </View>;
}
const s=StyleSheet.create({h1:{fontSize:28,fontWeight:'900',marginBottom:6},h2:{fontSize:22,fontWeight:'800',marginVertical:12},chip:{borderWidth:1,borderRadius:20,paddingHorizontal:14,paddingVertical:8},file:{flexDirection:'row',gap:12,borderWidth:1,borderRadius:20,padding:12,marginTop:10},thumb:{width:72,height:92,borderRadius:12},btn:{borderRadius:12,paddingHorizontal:14,paddingVertical:9},cover:{height:200,borderRadius:20,width:'100%'},grid:{flexDirection:'row',flexWrap:'wrap',gap:10},card:{flexBasis:'47%',flexGrow:1,borderWidth:1,borderRadius:20,overflow:'hidden'},cardImg:{height:110,width:'100%'}});
