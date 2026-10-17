from pathlib import Path
import requests,zipfile,io,hashlib,json,datetime
root=Path(__file__).resolve().parents[1];folder=root/'bikeshare/source';folder.mkdir(parents=True,exist_ok=True)
items={'uci_metadata.json':'https://archive.ics.uci.edu/api/dataset?id=275','bike_sharing.zip':'https://archive.ics.uci.edu/static/public/275/bike+sharing+dataset.zip'}
manifest=json.loads((root/'download_manifest.json').read_text()) if (root/'download_manifest.json').exists() else []
for name,url in items.items():
    r=requests.get(url,timeout=60);r.raise_for_status();p=folder/name;p.write_bytes(r.content)
    manifest.append(dict(candidate='bikeshare',url=url,file=str(p.relative_to(root)),sha256=hashlib.sha256(r.content).hexdigest(),bytes=len(r.content),downloaded_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
z=zipfile.ZipFile(folder/'bike_sharing.zip')
for name in z.namelist():
    if name.lower().endswith(('.csv','.txt')):
        (folder/Path(name).name).write_bytes(z.read(name))
print(z.namelist())
print((folder/'Readme.txt').read_text())
(root/'download_manifest.json').write_text(json.dumps(manifest,indent=2))
