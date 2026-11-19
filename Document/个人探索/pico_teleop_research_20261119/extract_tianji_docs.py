from pathlib import Path
from html.parser import HTMLParser
import re,json,sys
class Extract(HTMLParser):
 def __init__(self):super().__init__();self.out=[];self.links=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if tag in ['p','div','h1','h2','h3','h4','tr','li','pre','br']:self.out.append('\n')
  if tag=='a' and a.get('href'):self.links.append(a['href'])
  if tag=='img':self.out.append('[图片 '+a.get('alt','')+']')
 def handle_data(self,d):self.out.append(d)
for f in sys.argv[1:]:
 s=Path(f).read_text()
 m=re.search(r'<script[^>]*id=[\"\']?ssr_frontend_data[\"\']?[^>]*>(.*?)</script>',s,re.S)
 if not m:print(f,'no ssr');continue
 o=json.loads(m.group(1));strings=[]
 def walk(v):
  if isinstance(v,dict):
   for k,x in v.items():
    if k=='html' and isinstance(x,str):strings.append(x)
    elif k!='styleTags':walk(x)
  elif isinstance(v,list):
   for x in v:walk(x)
 walk(o)
 p=Extract();p.feed('\n'.join(strings));body=re.sub(r'\n\s*\n+', '\n', ''.join(p.out))
 target=Path(f).with_suffix('.txt');target.write_text(body+'\n\nLINKS\n'+'\n'.join(dict.fromkeys(p.links)))
 print(target, len(body),o.keys())
