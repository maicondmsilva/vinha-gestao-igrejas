import {useState} from 'react';
import {Pressable,StyleSheet,Text,TextInput,View} from 'react-native';
import {composeCare,parseCare,type KidsCare} from '../../shared/kids-care';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};
type Need='food'|'allergy'|'special';
const needs:[Need,string,string][]=[['food','Alimentação','O que a criança não pode comer ou beber?'],['allergy','Alergia','A que a criança tem alergia?'],['special','Saúde e acessibilidade','Como a equipe pode ajudar melhor?']];

/** "Para cuidarmos bem" (identidade Vinha): etiquetas do que se aplica, campo só para o que foi marcado e uso de imagem em linguagem positiva. */
export default function KidsCareFields({value,onChange,palette:p}:{value:string;onChange:(v:string)=>void;palette:Palette}){
 const ac=p.accent||p.brand;
 const [care,setCare]=useState<KidsCare>(()=>parseCare(value)),[on,setOn]=useState<Record<Need,boolean>>(()=>{const c=parseCare(value);return{food:!!c.food,allergy:!!c.allergy,special:!!c.special}});
 const update=(next:KidsCare)=>{setCare(next);onChange(composeCare(next))};
 const toggle=(k:Need)=>{const v=!on[k];setOn({...on,[k]:v});if(!v)update({...care,[k]:''})};
 const option=(label:string,selected:boolean,press:()=>void)=><Pressable accessibilityRole="radio" accessibilityState={{selected}} onPress={press} style={[s.option,{borderColor:selected?ac:p.line,backgroundColor:selected?ac:p.surface}]}><Text style={{color:selected?'#fff':p.text,fontWeight:'800',textAlign:'center'}}>{label}</Text></Pressable>;
 return <View style={[s.box,{borderColor:p.line,backgroundColor:p.surface}]}>
  <Text style={[s.head,{color:p.text}]}>Para cuidarmos bem</Text>
  <Text style={{color:p.muted}}>Marque o que precisa de atenção. Se nada se aplica, é só seguir.</Text>
  <View style={s.tags}>{needs.map(([k,label])=><Pressable key={k} accessibilityRole="checkbox" accessibilityState={{checked:on[k]}} onPress={()=>toggle(k)} style={[s.tag,{borderColor:on[k]?ac:p.line,backgroundColor:on[k]?ac:'transparent'}]}><Text style={{color:on[k]?'#fff':p.text,fontWeight:'700'}}>{on[k]?'✓ ':'+ '}{label}</Text></Pressable>)}</View>
  {needs.filter(([k])=>on[k]).map(([k,label,question])=><View key={k} style={{marginTop:10}}>
   <Text style={{color:ac,fontWeight:'800',fontSize:12,letterSpacing:1}}>{label.toUpperCase()}</Text>
   <TextInput accessibilityLabel={question} value={care[k]} onChangeText={v=>update({...care,[k]:v})} placeholder={question} placeholderTextColor={p.muted} multiline maxLength={400} style={[s.input,{color:p.text,borderColor:p.line}]}/>
  </View>)}
  <Text style={[s.sub,{color:p.text}]}>Uso de imagem</Text>
  <View style={s.options}>{option('Pode aparecer em fotos',!care.noPhotos,()=>update({...care,noPhotos:false}))}{option('Prefiro sem fotos',care.noPhotos,()=>update({...care,noPhotos:true}))}</View>
  <Text style={[s.sub,{color:p.text}]}>Algo mais?</Text>
  <TextInput accessibilityLabel="Algo mais que a equipe deve saber" value={care.notes} onChangeText={v=>update({...care,notes:v})} placeholder="Ex.: chega com sono, usa chupeta, tem um irmão na mesma sala" placeholderTextColor={p.muted} multiline maxLength={600} style={[s.input,{color:p.text,borderColor:p.line}]}/>
 </View>;
}
const s=StyleSheet.create({box:{borderWidth:1,borderRadius:22,padding:16,marginTop:14},head:{fontSize:19,fontWeight:'900',marginBottom:4},sub:{fontSize:15,fontWeight:'800',marginTop:16},tags:{flexDirection:'row',flexWrap:'wrap',gap:8,marginTop:12},tag:{borderWidth:1,borderRadius:22,paddingHorizontal:14,paddingVertical:9},input:{borderWidth:1,borderRadius:14,padding:12,minHeight:60,fontSize:15,marginTop:6,textAlignVertical:'top'},options:{flexDirection:'row',gap:8,marginTop:8},option:{flex:1,borderWidth:1,borderRadius:14,paddingVertical:12,paddingHorizontal:8}});
