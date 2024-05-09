import requests
import json
import duckdb

with open('api.key', 'r') as file:
    global api_key
    api_key = file.read().strip() 


def filename(response, cell):
    dt = response.json()['dt']
    return f"{cell}_{dt}.json"


def save(response, cell):
    filepath = f"data/{filename(response, cell)}"
    with open(filepath, 'w') as file:
        file.write(json.dumps(response.json(), indent=4))


def ow_current(lon, lat):
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&units=metric&appid={api_key}"
    response = requests.request("GET", url, headers={}, data={})
    return response


#getData(114.33689724047092,-28.417250558821546)
def getData(lat, lon, cell):
    response = ow_current(lat, lon)
    save(response, cell)


db = duckdb.connect()
db.load_extension('spatial')

db.sql("create view cover as from st_read('maps/3. Minimal cover.geojson')")

latlons = db.sql('select distinct st_x(st_centroid(geom)), st_y(st_centroid(geom)), celluid from cover')
for lat,lon,cell in latlons.fetchall():
    print(f'getData({lat},{lon},{cell})')
    getData(lat,lon,cell)


