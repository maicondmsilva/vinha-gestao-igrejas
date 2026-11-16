import {useState} from 'react';
import {Image,Pressable,ScrollView,StyleSheet,Text,TextInput,View} from 'react-native';
import {givingInk,givingMoney,type GivingCard} from '../../shared/giving';
import {memberAmount} from '../../shared/member-services';

type Palette={surface:string;text:string;muted:string;line:string;brand:string;bg?:string};

/** Cartão com a cor e a imagem que a igreja escolheu; o nome fica sempre legível sobre a imagem. */
function Card({c,width,onPress}:{c:GivingCard;width:number;onPress:()=>void}){
 const ink=c.image?'#ffffff':givingInk(c.color);
 return <Pressable accessibilityRole="button" accessibilityLabel={'Contribuir: '+c.title} onPress={onPress} style={[s.card,{width,backgroundColor:c.color}]}>
  {!!c.image&&<Image source={{uri:c.image}} resizeMode="cover" style={StyleSheet.absoluteFill}/>}
  <View style={[StyleSheet.absoluteFill,{backgroundColor:c.image?'rgba(0,0,0,.28)':'transparent'}]}/>
  <View style={s.cardText}><Text numberOfLines={2} style={[s.cardTitle,{color:ink}]}>{c.title}</Text>{!!c.subtitle&&<Text numberOfLines={2} style={{color:ink,opacity:.9,fontSize:12,lineHeight:16}}>{c.subtitle}</Text>}</View>
  <View style={[s.arrow,{borderColor:ink}]}><Text style={{color:ink,fontWeight:'900'}}>›</Text></View>
 </Pressable>;
}

/** Contribua: cartões em destaque; ao tocar, escolhe o valor e segue para o pagamento seguro da conta principal. */
export default function GivingCards({cards,palette:p,busy,give}:{cards:GivingCard[];palette:Palette;busy:boolean;give:(c:GivingCard,cents:string)=>Promise<void>}){
 const [open,setOpen]=useState<GivingCard|null>(null),[amount,setAmount]=useState(''),[problem,setProblem]=useState('');
 if(open){
  const ink=open.image?'#ffffff':givingInk(open.color);
  return <View style={{gap:14}}>
   <View style={[s.hero,{backgroundColor:open.color}]}>
    {!!open.image&&<Image source={{uri:open.image}} resizeMode="cover" style={StyleSheet.absoluteFill}/>}
    <View style={[StyleSheet.absoluteFill,{backgroundColor:open.image?'rgba(0,0,0,.32)':'transparent'}]}/>
    <View style={s.cardText}><Text style={[s.cardTitle,{color:ink,fontSize:28}]}>{open.title}</Text>{!!open.subtitle&&<Text style={{color:ink,opacity:.92,lineHeight:20}}>{open.subtitle}</Text>}</View>
   </View>
   {!!open.amounts.length&&<View style={s.chips}>{open.amounts.map(a=>{const on=memberAmount(amount)===String(a);return <Pressable key={a} accessibilityRole="button" accessibilityState={{selected:on}} onPress={()=>{setAmount((a/100).toFixed(2).replace('.',','));setProblem('')}} style={[s.chip,{borderColor:on?p.brand:p.line,backgroundColor:on?p.brand:p.surface}]}><Text style={{color:on?'#fff':p.text,fontWeight:'800'}}>{givingMoney(a)}</Text></Pressable>})}</View>}
   <TextInput accessibilityLabel="Valor em reais" value={amount} onChangeText={v=>{setAmount(v);setProblem('')}} keyboardType="decimal-pad" placeholder="Outro valor (R$)" placeholderTextColor={p.muted} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.surface}]}/>
   {!!problem&&<Text accessibilityRole="alert" style={{color:'#b8741a',fontWeight:'700'}}>{problem}</Text>}
   <Pressable accessibilityRole="button" disabled={busy} onPress={()=>{const cents=memberAmount(amount);if(!cents){setProblem('Informe um valor a partir de R$ 1,00.');return}void give(open,cents).then(()=>{setAmount('');setOpen(null)})}} style={[s.primary,{backgroundColor:p.brand,opacity:busy?.6:1}]}><Text style={{color:'#fff',fontWeight:'900',fontSize:16}}>{busy?'Abrindo pagamento…':'Contribuir'}</Text></Pressable>
   <Text style={{color:p.muted,fontSize:12,lineHeight:18}}>O pagamento abre no ambiente seguro do provedor da igreja (Pix, cartão ou boleto). A confirmação aparece em “Minhas contribuições”.</Text>
   <Pressable accessibilityRole="button" onPress={()=>{setOpen(null);setProblem('')}} hitSlop={8}><Text style={{color:p.muted,fontWeight:'800'}}>‹ Voltar</Text></Pressable>
  </View>;
 }
 return <View style={{gap:10}}>
  <Text accessibilityRole="header" style={{color:p.text,fontSize:20,fontWeight:'900'}}>Destaques</Text>
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:12,paddingRight:8}}>
   {cards.map(c=><Card key={c.id} c={c} width={150} onPress={()=>{setOpen(c);setAmount('');setProblem('')}}/>)}
  </ScrollView>
 </View>;
}
const s=StyleSheet.create({card:{height:200,borderRadius:20,overflow:'hidden',justifyContent:'flex-end'},cardText:{padding:14,gap:4},cardTitle:{fontSize:22,fontWeight:'900',lineHeight:26},
 arrow:{position:'absolute',top:12,right:12,width:26,height:26,borderRadius:13,borderWidth:1.5,alignItems:'center',justifyContent:'center'},
 hero:{height:190,borderRadius:22,overflow:'hidden',justifyContent:'flex-end'},chips:{flexDirection:'row',flexWrap:'wrap',gap:8},chip:{borderWidth:1.5,borderRadius:16,paddingHorizontal:16,paddingVertical:10},
 input:{borderWidth:1,borderRadius:14,padding:14,fontSize:18,minHeight:52},primary:{minHeight:54,borderRadius:16,alignItems:'center',justifyContent:'center'}});
