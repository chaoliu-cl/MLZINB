from pathlib import Path
root=Path(__file__).resolve().parent
s=(root/'bike_components.R').read_text()
s=s.replace("'09_MODERATION_DATASET_SEARCH/bikeshare'","'09_MODERATION_DATASET_SEARCH/bikeshare_profile'")
s=s.replace("sp$bc['x_w']","sp$bc['sin1']").replace("sm$bc['x_w']","sm$bc['sin1']").replace("match('x_w',names(s$bc))","match('sin1',names(s$bc))")
s=s.replace("sp$bz['x_w']","sp$bz['sin1']").replace("sm$bz['x_w']","sm$bz['sin1']").replace("match('x_w',names(s$bz))","match('sin1',names(s$bz))")
(root/'profile_components.R').write_text(s,encoding='utf-8')
