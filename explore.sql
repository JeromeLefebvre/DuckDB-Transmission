load spatial;
load h3ext;

-- Load the transmission data into memory
create table td as from st_read('Transmission_Overhead_Powerlines_WP_032_WA_GDA2020_Public_Secure_Shapefile/Transmission_Overhead_Powerlines_WP_032.shp');

-- create a square that cover everything plus a little extra
create or replace view square as select st_buffer(st_envelope_agg(geom),0.7) as geom from td;

-- visualize the square
copy square to 'maps/1. cover.geojson' with (format GDAL, Driver 'GeoJson');

-- Replace the square with a cover of Hex
-- We picked a depth 3 to give us a around 30 Hex to cover the entire grid
create or replace view cover as
select cast(h3_cell_to_boundary_wkt(celluid) as geometry) as cell, cast(celluid as varchar) as celluid
from (select (unnest(h3_polygon_wkt_to_cells(geom,3))) as celluid from square);

-- Visualize (also load the transmission data)
copy cover to 'maps/2. Cover all Hexs.geojson' with (format GDAL, driver 'geojson');

-- find all the cells that actually contain part of the transmisison line
create or replace view minimalCover as
select DISTINCT cell as cell, celluid from cover,td where ST_Intersects(cover.cell, td.geom);

-- visualize the minimal cover (also load the TD data)
copy minimalCover to 'maps/3. Minimal cover.geojson' with (format GDAL, driver 'Geojson');

-- We will use this query to pull the geo data into Python to get weather data
select st_x(st_centroid(cell)), st_y(st_centroid(cell)), celluid from minimalCover;

-- Run python to download data...

-- Grab the data
create or replace view currentWeather as
select split_part(split_part(filename,'/',-1),'_',1) as celluid, last(main.temp order by dt asc) as temp, last(wind.deg order by dt asc) as winddir from read_json('data/*.json', filename=true) group by celluid;

-- Join the minialcover with the weather data
create or replace view weatherForCell as
select cell, temp, windDir from currentWeather cw join minimalCover mc on cw.celluid = mc.celluid;

-- visualize
copy weatherForCell to 'maps/4. Weather for minimal cover.geojson' with (format gdal, driver 'geojson');

-- The TD set is made up of multilinestring, visualize a single line
copy (
select ST_CollectionExtract(geom) from td limit 1
) to 'maps/5. what is multilinering.geojson' with (format gdal, driver 'geojson');

-- Methods to extra infor from multilinestring
select ST_NGeometries(geom) from td limit 1;
select ST_CollectionExtract(geom,2) from td limit 1;
select unnest(ST_DUMP(geom)).geom from (from td limit 1);

-- How to unnest multilinestring
select line_name, kv, instln_yr, unnest(ST_DUMP(geom)).geom subline from (from td limit 1);

-- Convert everything into multiline
create or replace view lines as
(select line_name, kv, instln_yr, unnest(ST_DUMP(geom)).geom as geom from (from td where ST_GeometryType(geom) = 'MULTILINESTRING'))
union
(select line_name, kv, instln_yr, geom as geom from (from td where ST_GeometryType(geom) = 'LINESTRING'));

-- I will need to look at the direction of each line segment
CREATE or replace MACRO degreesVect(a, b) AS ((DEGREES(atan2(ST_Y(b) - ST_Y(a), ST_X(b) - ST_X(a))) + 360) % 360);

-- Test of function
select degreesVect(st_point(1,0), st_point(0,1)); -- 180 - 45 == 135

-- Find the direction in degrees of each vector
create or replace view lineDirection as
select st_pointN(geom, cast(range as integer)) as a, st_pointN(geom, cast(range as integer) + 1) as b, degreesVect(a,b) as dir, line_name, kv from lines, range(1,400,1) where b is not null;

-- Add the weather to the line base on where the start point is
-- Todo: the angle of attach calculation seems wrong
    select st_makeline(a,b) as lineSeg, case when ((abs(winddir - dir) % 180) < 90) then (abs(winddir - dir) % 180) else (180 - abs(winddir - dir)) end from lineDirection, weatherForCell where st_contains(cell, a);

-- Visualize the result
copy (
    select st_makeline(a,b) as lineSeg, case when ((abs(winddir - dir) % 180) < 90) then (abs(winddir - dir) % 180) else (180 - abs(winddir - dir)) end from lineDirection, weatherForCell where st_contains(cell, a)
) to 'maps/6. final.geojson' with (format gdal, driver 'geojson');

-- Todo: recreate this visualization https://www.windfinder.com/#8/-32.0430/116.8011

-- Todo: use a time range for the weather and apply a circular mean
https://en.wikipedia.org/wiki/Circular_mean

-- Todo: use some UDFs in python to actually compute this impact
https://www.electrical4u.com/sag-in-overhead-conductor/
https://github.com/tommz9/pylinerating