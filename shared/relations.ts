// Parentescos usados no painel e no app (família, Kids e pedidos pelo app).
export const relations=['conjuge','pai_mae','filho','irmao','avo','neto','tio','sobrinho','padrasto_madrasta','enteado','responsavel_legal','tutelado','outro'] as const;
export type Relation=typeof relations[number];
export const relationLabels:Record<Relation,string>={conjuge:'Cônjuge',pai_mae:'Pai/Mãe',filho:'Filho(a)',irmao:'Irmão(ã)',avo:'Avô/Avó',neto:'Neto(a)',tio:'Tio(a)',sobrinho:'Sobrinho(a)',padrasto_madrasta:'Padrasto/Madrasta',enteado:'Enteado(a)',responsavel_legal:'Responsável legal',tutelado:'Tutelado(a)',outro:'Outro'};
