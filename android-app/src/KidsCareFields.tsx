import {useState} from 'react';
import {Pressable,StyleSheet,Switch,Text,TextInput,View} from 'react-native';
import {composeCare,parseCare,type KidsCare} from '../../shared/kids-care';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};

/** Cuidados da criança em perguntas simples: cada "sim" abre o campo para detalhar. */
export default function KidsCareFields({value,onChange,palette:p}:{value:string;onChange:(v:string)=>void;palette:Palette}){
 const [care,setCare]=useState<KidsCare>(()=>parseCare(value)),[open,setOpen]=useState(()=>{const c=parseCare(value);return{food:!!c.food,allergy:!!c.allergy,special:!!c.special}});
 const update=(next:KidsCare)=>{setCare(next);onChange(composeCare(next))};
 const ask=(key:'food'|'allergy'|'special',question:string,placeholder:string)=><View style={[s.item,{borderColor:p.line,backgroundColor:p.surface}]}>
  <Pressable accessibilityRole="switch" accessibilityState={{checked:open[key]}} onPress={()=>{const on=!open[key];setOpen({...open,[key]:on});if(!on)update({...care,[key]:''})}} style={s.row}>
   <Text style={[s.q,{color:p.text}]}>{question}</Text><Switch value={open[key]} onValueChange={on=>{setOpen({...open,[key]:on});if(!on)update({...care,[key]:''})}} trackColor={{true:p.accent||p.brand,false:p.line}}/>
  </Pressable>
  {open[key]&&<TextInput accessibilityLabel={question} value={care[key]} onChangeText={v=>update({...care,[key]:v})} placeholder={placeholder} placeholderTextColor={p.muted} multiline maxLength={400} style={[s.input,{color:p.text,borderColor:p.line}]}/>}
 </View>;
 return <View>
  <Text style={[s.head,{color:p.text}]}>Cuidados e restrições</Text>
  <Text style={{color:p.muted,marginBottom:8}}>Responda sim só no que se aplica. A equipe Kids usa estas informações na recepção.</Text>
  {ask('food','Tem restrição alimentar?','Ex.: sem lactose, não pode açúcar')}
  {ask('allergy','Tem alguma alergia?','Ex.: amendoim, picada de inseto, dipirona')}
  {ask('special','Tem alguma necessidade especial?','Conte o que ajuda a equipe a cuidar bem')}
  <View style={[s.item,{borderColor:p.line,backgroundColor:p.surface}]}><Pressable accessibilityRole="switch" accessibilityState={{checked:care.noPhotos}} onPress={()=>update({...care,noPhotos:!care.noPhotos})} style={s.row}><Text style={[s.q,{color:p.text}]}>Não autorizo fotos da criança</Text><Switch value={care.noPhotos} onValueChange={v=>update({...care,noPhotos:v})} trackColor={{true:p.accent||p.brand,false:p.line}}/></Pressable></View>
  <Text style={[s.q,{color:p.text,marginTop:10}]}>Outras observações</Text>
  <TextInput accessibilityLabel="Outras observações" value={care.notes} onChangeText={v=>update({...care,notes:v})} placeholder="Algo mais que a equipe deve saber" placeholderTextColor={p.muted} multiline maxLength={600} style={[s.input,{color:p.text,borderColor:p.line}]}/>
 </View>;
}
const s=StyleSheet.create({head:{fontSize:18,fontWeight:'800',marginTop:16,marginBottom:4},item:{borderWidth:1,borderRadius:16,padding:12,marginVertical:5},row:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',gap:10,minHeight:40},q:{fontSize:15,fontWeight:'700',flex:1},input:{borderWidth:1,borderRadius:12,padding:12,minHeight:64,fontSize:15,marginTop:8,textAlignVertical:'top'}});
