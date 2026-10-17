from pathlib import Path
import hashlib, json, datetime
import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
ROOT.mkdir(exist_ok=True)
items = {
    'rwm': {
        'data.csv': 'https://vincentarelbundock.github.io/Rdatasets/csv/COUNT/rwm.csv',
        'documentation.html': 'https://vincentarelbundock.github.io/Rdatasets/doc/COUNT/rwm.html',
        'Health.Rd': 'https://raw.githubusercontent.com/cran/Rchoice/master/man/Health.Rd',
        'COUNT_DESCRIPTION': 'https://raw.githubusercontent.com/cran/COUNT/master/DESCRIPTION',
    },
    'countymurders': {
        'data.csv': 'https://vincentarelbundock.github.io/Rdatasets/csv/wooldridge/countymurders.csv',
        'documentation.html': 'https://vincentarelbundock.github.io/Rdatasets/doc/wooldridge/countymurders.html',
    },
}
manifest = []
for candidate, files in items.items():
    folder = ROOT / candidate / 'source'
    folder.mkdir(parents=True, exist_ok=True)
    for name, url in files.items():
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        target = folder / name
        target.write_bytes(response.content)
        manifest.append(dict(candidate=candidate, file=str(target.relative_to(ROOT)), url=url,
            downloaded_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            sha256=hashlib.sha256(response.content).hexdigest(), bytes=len(response.content)))
        if name.endswith('.html'):
            text = BeautifulSoup(response.content, 'html.parser').get_text(' ', strip=True)
            (folder / 'documentation.txt').write_text(text, encoding='utf-8')
            print(candidate, text)
(ROOT / 'download_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
