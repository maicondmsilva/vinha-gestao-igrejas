export function unitWriteError(message:unknown,fallback:string){
 switch(message){
  case 'unit_headquarters_exists':return 'A sede já está cadastrada. Escolha campus, congregação, regional ou afiliada.';
  case 'unit_headquarters_classification_immutable':return 'A classificação da sede não pode ser alterada por esta tela. Solicite uma revisão administrativa.';
  case 'unit_headquarters_parent_denied':return 'A sede não pode ficar subordinada a outra unidade.';
  case 'unit_organization_unavailable':return 'O ministério está indisponível para alterações. Verifique a situação com a Central.';
  case 'unit_original_date_denied':
  case 'unit_identity_fields_immutable':return 'Os identificadores e as datas originais da unidade não podem ser alterados.';
  default:return fallback;
 }
}
