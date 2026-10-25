import {useEffect,useState} from 'react';
import {Pressable,ScrollView,StyleSheet,Text,View} from 'react-native';

type Church={id:string;name:string};
type Props={churches:Church[];value:string;onChange:(id:string)=>void;disabled?:boolean;color:string;background:string;accent:string};

export default function ChurchSelect({churches,value,onChange,disabled=false,color,background,accent}:Props){
 const [open,setOpen]=useState(false);
 const selected=churches.find(church=>church.id===value);
 useEffect(()=>{if(disabled)setOpen(false)},[disabled]);
 return <View style={styles.wrapper}>
  <Text style={[styles.label,{color}]}>Igreja local</Text>
  <Pressable accessibilityRole="combobox" accessibilityLabel="Igreja local" accessibilityValue={{text:selected?.name||'Selecione sua igreja'}} accessibilityState={{expanded:open,disabled}} disabled={disabled} onPress={()=>setOpen(current=>!current)} style={[styles.field,{borderColor:open?accent:'#83978a',backgroundColor:background,opacity:disabled?0.7:1}]}>
   <Text style={[styles.value,{color}]}>{selected?.name||'Selecione sua igreja'}</Text>
   <Text accessibilityElementsHidden importantForAccessibility="no" style={{color,fontSize:18}}>{open?'▴':'▾'}</Text>
  </Pressable>
  {open&&<View style={[styles.menu,{backgroundColor:background,borderColor:accent}]}><ScrollView nestedScrollEnabled keyboardShouldPersistTaps="handled" style={styles.options}>
   {churches.length===0?<Text style={[styles.option,{color}]}>Nenhuma igreja disponível.</Text>:churches.map(church=><Pressable key={church.id} accessibilityRole="radio" accessibilityLabel={church.name} accessibilityState={{checked:church.id===value}} onPress={()=>{onChange(church.id);setOpen(false)}} style={[styles.option,church.id===value&&{borderLeftWidth:3,borderLeftColor:accent}]}><Text style={{color,fontWeight:church.id===value?'700':'400'}}>{church.name}</Text></Pressable>)}
  </ScrollView></View>}
  {disabled&&<Text style={[styles.hint,{color}]}>Seleção indisponível para cadastro vinculado ou em revisão.</Text>}
 </View>;
}

const styles=StyleSheet.create({wrapper:{marginBottom:20},label:{marginBottom:8},field:{minHeight:52,borderWidth:1,borderRadius:10,paddingHorizontal:14,paddingVertical:12,flexDirection:'row',alignItems:'center',gap:12},value:{fontSize:16,flex:1},menu:{borderWidth:1,borderRadius:10,marginTop:6,overflow:'hidden'},options:{maxHeight:240},option:{paddingHorizontal:14,paddingVertical:16,minHeight:48},hint:{fontSize:12,marginTop:8,lineHeight:18}});
