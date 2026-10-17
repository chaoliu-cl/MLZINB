import requests,json
from pathlib import Path
from bs4 import BeautifulSoup
root=Path(__file__).resolve().parents[1]
queries=['"caries" "dataset" "R"','"bike sharing" "casual" "workingday"','"zero inflated" "bike sharing"']
records=[]
for query in queries:
    r=requests.get('https://www.bing.com/search',params={'q':query},timeout=40)
    soup=BeautifulSoup(r.text,'html.parser')
    record=dict(query=query,status=r.status_code,url=r.url,text=soup.get_text(' ',strip=True)[:20000])
    records.append(record)
    print(json.dumps(record,ensure_ascii=True))
(root/'web_search_record.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
