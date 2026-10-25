"""Convert the pinned, licensed eBible VPL archive. No generated theology or paraphrase."""
import hashlib,json,sys,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
root=Path(__file__).resolve().parent.parent
source=root/'output/bible-source/porbr2018_vpl.zip'
xml=zipfile.ZipFile(source).read('porbr2018_vpl.xml')
expected='5e2845e9d5551b86aaffef56d689a77946fdf8eabfb672b15d15fa8a23e627db'
if hashlib.sha256(xml).hexdigest()!=expected: raise SystemExit('Source changed: review provenance before updating.')
names='Gênesis|Êxodo|Levítico|Números|Deuteronômio|Josué|Juízes|Rute|1 Samuel|2 Samuel|1 Reis|2 Reis|1 Crônicas|2 Crônicas|Esdras|Neemias|Ester|Jó|Salmos|Provérbios|Eclesiastes|Cantares|Isaías|Jeremias|Lamentações|Ezequiel|Daniel|Oseias|Joel|Amós|Obadias|Jonas|Miqueias|Naum|Habacuque|Sofonias|Ageu|Zacarias|Malaquias|Mateus|Marcos|Lucas|João|Atos|Romanos|1 Coríntios|2 Coríntios|Gálatas|Efésios|Filipenses|Colossenses|1 Tessalonicenses|2 Tessalonicenses|1 Timóteo|2 Timóteo|Tito|Filemom|Hebreus|Tiago|1 Pedro|2 Pedro|1 João|2 João|3 João|Judas|Apocalipse'.split('|')
books={}
for row in ET.fromstring(xml):
    book=row.get('b');chapter=int(row.get('c'));verse=int(row.get('v'));text=''.join(row.itertext()).strip()
    assert text and '\ufffd' not in text and chapter>0 and verse>0
    chapters=books.setdefault(book,[])
    if chapter>len(chapters):
        assert chapter==len(chapters)+1
        chapters.append([])
    assert verse==len(chapters[chapter-1])+1
    chapters[chapter-1].append(text)
assert len(books)==66 and sum(len(c) for c in books.values())==1189 and sum(len(v) for c in books.values() for v in c)==31102
target=root/'shared/bible';target.mkdir(parents=True,exist_ok=True)
(target/'blivre.json').write_text(json.dumps(books,ensure_ascii=False,separators=(',',':')),encoding='utf8')
catalog=[{'id':key,'name':name,'verses':[len(v) for v in chapters]} for (key,chapters),name in zip(books.items(),names,strict=True)]
(target/'books.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')),encoding='utf8')
(target/'catalog.ts').write_text('// Generated from the pinned eBible source by scripts/prepare-bible.py.\nexport default '+json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+';\n',encoding='utf8')
manifest={'edition':'Bíblia Livre — fevereiro de 2018','abbreviation':'BLIVRE','copyright':'© 2018 Diego Santos, Mario Sérgio e Marco Teles','license':'CC BY 4.0','licenseUrl':'https://creativecommons.org/licenses/by/4.0/','source':'https://ebible.org/Scriptures/porbr2018_vpl.zip','sourceInfo':'https://ebible.org/porbr2018/copyright.htm','sourceXmlSha256':expected,'changes':'Conversão de XML para JSON, remoção de espaços externos de cada versículo. Sem alteração intencional do texto. O arquivo VPL de origem já omite notas e formatação.','books':66,'chapters':1189,'verses':31102}
(target/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
(target/'provenance.ts').write_text('// Generated provenance; see LICENSE.md.\nexport default '+json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+';\n',encoding='utf8')
print('Bíblia preparada: 66 livros, 1189 capítulos, 31102 versículos; licença e origem registradas.')
