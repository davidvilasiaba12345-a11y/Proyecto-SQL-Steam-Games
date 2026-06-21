/*==============================
	02_data.sql
	- Carga de datos y limpieza
================================*/

/*========================================================
	CARGA INICIAL DEL CSV EN UNA TABLA TEMPORAL
==========================================================*/
DROP TABLE IF EXISTS temp_games;
CREATE TABLE temp_games (
    appid                    TEXT,
    name                     TEXT,
    release_date             TEXT,
    required_age             TEXT,
    price                    TEXT,
    dlc_count                TEXT,
    detailed_description     TEXT,
    about_the_game           TEXT,
    short_description        TEXT,
    reviews                  TEXT,
    header_image             TEXT,
    website                  TEXT,
    support_url              TEXT,
    support_email            TEXT,
    windows                  TEXT,
    mac                      TEXT,
    linux                    TEXT,
    metacritic_score         TEXT,
    metacritic_url           TEXT,
    achievements             TEXT,
    recommendations          TEXT,
    notes                    TEXT,
    supported_languages      TEXT,
    full_audio_languages     TEXT,
    packages                 TEXT,
    developers               TEXT,
    publishers               TEXT,
    categories               TEXT,
    genres                   TEXT,
    screenshots              TEXT,
    movies                   TEXT,
    user_score               TEXT,
    score_rank               TEXT,
    positive                 TEXT,
    negative                 TEXT,
    estimated_owners         TEXT,
    average_playtime_forever TEXT,
    average_playtime_2weeks  TEXT,
    median_playtime_forever  TEXT,
    median_playtime_2weeks   TEXT,
    discount                 TEXT,
    peak_ccu                 TEXT,
    tags                     TEXT,
    pct_pos_total            TEXT,
    num_reviews_total        TEXT,
    pct_pos_recent           TEXT,
    num_reviews_recent       TEXT
);

-- IMPORTANTE: El CSV debe copiarse primero al contenedor Docker con:
-- docker cp ruta/local/games_march2025_full.csv steam_games_db:/var/lib/postgresql/data/games_march2025_full.csv
COPY temp_games FROM '/var/lib/postgresql/data/games_march2025_full.csv'
DELIMITER ','
CSV HEADER
ENCODING 'UTF8';

/*========================================================
	LIMPIEZA DE DATOS
==========================================================*/


/*========================================================
	1º- LIMPIEZA DE VALORES NULOS
==========================================================*/
-- Primero normalizo cadenas vacías y texto 'NULL' a NULLs reales (Pusto que las columas en temp_games son TEXT)
UPDATE temp_games
SET
    name = NULLIF(NULLIF(name, ''), 'NULL'),
    release_date = NULLIF(NULLIF(release_date, ''), 'NULL'),
    price = NULLIF(NULLIF(price, ''), 'NULL'),
    genres = NULLIF(NULLIF(genres, ''), 'NULL'),
    developers = NULLIF(NULLIF(developers, ''), 'NULL'),
    publishers = NULLIF(NULLIF(publishers, ''), 'NULL'),
    estimated_owners = NULLIF(NULLIF(estimated_owners, ''), 'NULL'),
    metacritic_score = NULLIF(NULLIF(metacritic_score, ''), 'NULL'),
    positive = NULLIF(NULLIF(positive, ''), 'NULL'),
    negative = NULLIF(NULLIF(negative, ''), 'NULL');

-- Una vez normalizado, compruebo cuántos nulos hay en cada columna clave (las que utilizaré para el análisis)
SELECT
	SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS nulls_name,
	SUM(CASE WHEN release_date IS NULL THEN 1 ELSE 0 END) AS nulls_release_date,
	SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS nulls_price,
	SUM(CASE WHEN genres IS NULL THEN 1 ELSE 0 END) AS nulls_genres,
	SUM(CASE WHEN developers IS NULL THEN 1 ELSE 0 END) AS nulls_developers,
	SUM(CASE WHEN publishers IS NULL THEN 1 ELSE 0 END) AS nulls_publishers,
	SUM(CASE WHEN estimated_owners IS NULL THEN 1 ELSE 0 END) AS nulls_estimated_owners,
	SUM(CASE WHEN metacritic_score IS NULL THEN 1 ELSE 0 END) AS nulls_metacritic_score,
	SUM(CASE WHEN positive IS NULL THEN 1 ELSE 0 END) AS nulls_positive_reviews,
	SUM(CASE WHEN negative IS NULL THEN 1 ELSE 0 END) AS nulls_negative_reviews
FROM temp_games;

-- Corrijo los 2 nulos en name asignando un valor por defecto:
UPDATE temp_games SET name = 'Unknown' WHERE name IS NULL;

--Compruebo que se solucionó
SELECT
	SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS nulls_name
FROM temp_games;

/*========================================================
	2º- LIMPIEZA DE DUPLICADOS
==========================================================*/
-- Detecto duplicados utilizando el appid --> RESULTADO: 0 Duplicados
SELECT
	appid,
	COUNT(*) AS total
FROM
	temp_games
GROUP BY
	appid
HAVING COUNT(*) > 1
ORDER BY total DESC;

/*========================================================
	3º- LIMPIEZA DE FECHAS Y TIPOS INCORRECTOS
==========================================================*/
-- Primero compruebo si hay fechas que no se pueden convertir a DATE --> RESULTADO: 0 fechas con formato incorrecto
SELECT
	appid,
	name,
	release_date
FROM temp_games
WHERE release_date !~ '^\d{4}-\d{2}-\d{2}$';	-- '^\d{4}-\d{2}-\d{2}$': Indica que el formato esperado es 'YYYY-MM-DD'

-- Segundo: Compruebo si hay valores que no se pueden convertir a número en columnas numéricas --> RESULTADO: 0 valores que no se puedan convertir a números
SELECT
	appid,
	name,
	price,
	metacritic_score,
	positive,
	negative,
	discount,
	peak_ccu
FROM temp_games
WHERE price !~ '^\d+(\.\d+)?$'	-- ^\d+(\.\d+)?$: Verifica que sea un número válido (entero o decimal)
	OR metacritic_score !~ '^\d+$'	-- '^\d+$': Verifica que sea un número entero válido
	OR positive !~ '^\d+$'
	OR negative !~ '^\d+$'
	OR discount !~ '^\d+$'
	OR peak_ccu !~ '^\d+$';

-- Tercero: Compruebo si hay valores en columnas booleanas --> RESULTADO: 0 valores con formato incorrecto
SELECT appid, name, windows, mac, linux
FROM temp_games
WHERE windows NOT IN ('true', 'false', 'True', 'False', 'TRUE', 'FALSE')
	OR mac NOT IN ('true', 'false', 'True', 'False', 'TRUE', 'FALSE')
	OR linux NOT IN ('true', 'false', 'True', 'False', 'TRUE', 'FALSE');

/*========================================================
	4º- LIMPIEZA DE VALORES FUERA DE RANGO
==========================================================*/
-- Primero, detecto si hay valores númericos fuera del rango esperado (Necesito hacer CAST porque, tal y como se crea la tabla temporal en donde se vuelcan los datos del CSV, todos las columnas son TEXT)
SELECT
	SUM(CASE WHEN CAST(price AS NUMERIC) < 0 THEN 1 ELSE 0 END) AS out_range_price,
	SUM(CASE WHEN CAST(metacritic_score AS INT) NOT BETWEEN 0 AND 100 THEN 1 ELSE 0 END) AS out_range_metacritic,
	SUM(CASE WHEN CAST(required_age AS INT) NOT BETWEEN 0 AND 21 THEN 1 ELSE 0 END) AS out_range_age,
	SUM(CASE WHEN CAST(discount AS INT) NOT BETWEEN 0 AND 100 THEN 1 ELSE 0 END) AS out_range_discount,
	SUM(CASE WHEN CAST(pct_pos_total AS INT) NOT BETWEEN 0 AND 100 THEN 1 ELSE 0 END) AS out_range_pct
FROM temp_games;

-- Al ejecutar la query anterior, descubrí que pct_pos_total tiene casi la mitad del dataset con valores fuera de rango, asique voy a ver cuales son los valores
SELECT
	pct_pos_total,
	COUNT(*) AS total
FROM temp_games
WHERE CAST(pct_pos_total AS INT) NOT BETWEEN 0 AND 100
GROUP BY pct_pos_total
ORDER BY total DESC;

-- Tras comprobarlo vi que el único valor que hay fuera de rango es el -1, el cual, tras consultárselo a claude, llegamos a la conclusión de que es un valor especial para indicar que no hay suficientes reseñas para ese juego
-- Asique, antes de actualizar el campo, voy a comprobar si las demás columnas relacionadas con las reseñas tienes el mismo valor y a cuantas filas afecta
SELECT
	SUM(CASE WHEN pct_pos_recent = '-1' THEN 1 ELSE 0 END) AS neg_pct_pos_recent,
	SUM(CASE WHEN num_reviews_total = '-1' THEN 1 ELSE 0 END) AS neg_num_reviews_total,
	SUM(CASE WHEN num_reviews_recent = '-1' THEN 1 ELSE 0 END) AS neg_num_reviews_recent
FROM temp_games;

-- Tras hacer estas querys, descubrí que hay demasiadas filas con este valor -1, por lo tanto decidí no emplear estas columas y, en el EDA, calcularlas a partir de las columna positive y negative
-- Una vez decidido lo anterior, compruebo los valores de required_age que se salen del rango de 0-21
SELECT
	appid,
	name,
	required_age
FROM temp_games
WHERE CAST(required_age AS INT) NOT BETWEEN 0 AND 21
ORDER BY CAST(required_age AS INT) DESC;

-- Voy a modificar el valor -1 presente en required age
BEGIN;
UPDATE temp_games SET required_age = '0' WHERE required_age = '-1';

-- Verifico que el cambio se aplicó correctamente
SELECT COUNT(*) AS fuera_de_rango FROM temp_games WHERE CAST(required_age AS INT) NOT BETWEEN 0 AND 21;
COMMIT;

/*===================================================================
	PASAR LOS DATOS TRATADOS A LAS TABLAS DEFINITIVAS
=====================================================================*/


/*===================================================================
	CARGA DE dim_publisher
=====================================================================*/
-- Primero voy a pasar los datos de la columna publishers de temp_games a la tabla dim_publisher, por lo tanto primero compruebo como vienen los datos de dicha columna --> RESULTADO: Vienen así ['Nombre']
SELECT DISTINCT publishers FROM temp_games LIMIT 10;

-- También compruebo si hay juegos con varios publisher separados con comas --> RESULTADO: Si que hay
SELECT publishers FROM temp_games WHERE publishers LIKE '%'', ''%' LIMIT 10;

-- Mi decisión fue emplear el primero que aparezca, puesto que, normalmente, es el más importante
-- Antes de volcar los datos, voy a intentar extraer el primer publisher
SELECT
	publishers,
	TRIM(SPLIT_PART(publishers, ''',''', 1), '[]''') AS clean_publisher
FROM temp_games LIMIT 20;

-- Tras esto vi que hay publishers vacios, los cuales voy a tratar
-- Primero veo cuantos juegos no tienen publisher --> RESULTADO: 5786 filas afectadas
SELECT
	COUNT(*) AS not_publisher
FROM temp_games
WHERE TRIM(SPLIT_PART(publishers, ''',''', 1), '[]''') = '';

-- Una vez hecho esto, procedo con la carga de dato a dim_publisher (voy a añadir un publisher especial, 'Unknown', para que despues lo juegos que no tienen publisher apunten a este)
INSERT INTO dim_publisher(publisher_name)
SELECT DISTINCT LEFT(TRIM('[]''' FROM SPLIT_PART(publishers, ''',''', 1)), 150 ) AS publisher_name
FROM temp_games
WHERE TRIM('[]''' FROM SPLIT_PART(publishers, ''',''', 1)) <> ''	-- Excluyo los vacíos
UNION
SELECT 'Unknown';

/*===================================================================
	CARGA DE dim_genre
=====================================================================*/
-- Hago como con dim_publisher, compruebo como vienen los datos
SELECT DISTINCT genres FROM temp_games WHERE genres <> '[]' LIMIT 10;

-- Como queriero todos los géneros, no puedo hacer como hice antes de quedarme solo con el primero, asique voy a separar cada género en una fila independiente
SELECT
	DISTINCT TRIM(UNNEST(STRING_TO_ARRAY(genres, ',')), '[]'' ') AS genre_name
FROM temp_games
WHERE genres <> '[]'
ORDER BY genre_name
LIMIT 10;

-- Ahora si, procedo con la carga
INSERT INTO dim_genre(genre_name)
SELECT DISTINCT TRIM(UNNEST(STRING_TO_ARRAY(genres, ',')), '[]'' ') AS genre_name
FROM temp_games
WHERE genres <> '[]';

/*===================================================================
	CARGA DE dim_developer
=====================================================================*/
-- Compruebo como vienen los datos y, compruebo su longitud máxima por si tengo que modificar el tamaño del varchar en el momento de crear la tabla dim_developer
SELECT
    TRIM(UNNEST(STRING_TO_ARRAY(developers, ',')), '[]'' ') AS developer_name,
    LENGTH(TRIM(UNNEST(STRING_TO_ARRAY(developers, ',')), '[]'' ')) AS longitud
FROM temp_games
WHERE developers <> '[]'
ORDER BY longitud DESC
LIMIT 10;

-- Procedo con la carga
INSERT INTO dim_developer(developer_name)
SELECT DISTINCT LEFT(TRIM('[]'' ' FROM UNNEST(STRING_TO_ARRAY(developers, ','))), 150 ) AS developer_name
FROM temp_games
WHERE developers <> '[]';

/*===================================================================
	CARGA DE dim_platform
=====================================================================*/
-- En este caso, inserto los datos de forma manual puesto que solo son 3
INSERT INTO dim_platform(platform_name) VALUES 
    ('Windows'),
    ('Mac'),
    ('Linux');

/*===================================================================
	CARGA DE dim_calendar
=====================================================================*/
INSERT INTO dim_calendar(date_id, day_of_month, month_num, month_name, quarter_num, year_num, is_weekend)
SELECT DISTINCT
	CAST(release_date AS DATE) AS date_id,
	CAST(EXTRACT(DAY FROM CAST(release_date AS DATE)) AS SMALLINT) AS day_of_month,
	CAST(EXTRACT(MONTH FROM CAST(release_date AS DATE)) AS SMALLINT) AS month_num,
	TRIM(TO_CHAR(CAST(release_date AS DATE), 'Month')) AS month_name,
	CAST(EXTRACT(QUARTER FROM CAST(release_date AS DATE)) AS SMALLINT) AS quarter_num,
	CAST(EXTRACT(YEAR FROM CAST(release_date AS DATE)) AS SMALLINT) AS year_num,
	CASE WHEN EXTRACT(DOW FROM CAST(release_date AS DATE)) IN (0,6) THEN TRUE ELSE FALSE END AS is_weekend
FROM temp_games
WHERE release_date IS NOT NULL;

/*===================================================================
	CARGA DE fact_games
=====================================================================*/
-- Primero, verifico el formato que presenta estimated_owners en la tabla temp_games
SELECT DISTINCT estimated_owners FROM temp_games ORDER BY estimated_owners LIMIT 20;

-- Una vez verificado el formato, ya paso ha ejecutar el INSERT (el COALESCE() lo uso para enlazar los juegos con la fila Unknown, si estos no presentan publisher)
INSERT INTO fact_games (
	appid, name, release_date, required_age, price, dlc_count, metacritic_score, achievements, recommendations,
	positive_reviews, negative_reviews, average_playtime_forever, peak_ccu, discount, owners_min, owners_max, publisher_id
)
SELECT
	CAST(t.appid AS INT),
	LEFT(t.name, 200),
	CAST(t.release_date AS DATE),
	CAST(t.required_age AS SMALLINT),
	CAST(t.price AS NUMERIC(6,2)),
	CAST(t.dlc_count AS SMALLINT),
	CAST(t.metacritic_score AS SMALLINT),
	CAST(t.achievements AS INT),
	CAST(t.recommendations AS INT),
	CAST(t.positive AS INT),
	CAST(t.negative AS INT),
	CAST(t.average_playtime_forever AS INT),
	CAST(t.peak_ccu AS INT),
	CAST(t.discount AS SMALLINT),
	CAST(TRIM(SPLIT_PART(t.estimated_owners, '-', 1)) AS INT),
	CAST(TRIM(SPLIT_PART(t.estimated_owners, '-', 2)) AS INT),
	p.publisher_id
FROM temp_games t
LEFT JOIN dim_publisher p ON p.publisher_name = COALESCE (
	NULLIF(LEFT(TRIM('[]''' FROM SPLIT_PART(t.publishers, ''',''', 1)), 150), ''),
	'Unknown'
);


/*===================================================================
	CARGA DE game_genre
=====================================================================*/
INSERT INTO game_genre (appid, genre_id)
WITH juegos_generos AS (
    SELECT
        CAST(appid AS INT) AS appid,
        TRIM('[]'' ' FROM UNNEST(STRING_TO_ARRAY(genres, ','))) AS genre_name
    FROM temp_games
    WHERE genres <> '[]'
)
SELECT DISTINCT
    jg.appid,
    g.genre_id
FROM juegos_generos jg
JOIN dim_genre g ON g.genre_name = jg.genre_name;

/*===================================================================
	CARGA DE game_developer
=====================================================================*/
INSERT INTO game_developer (appid, developer_id)
WITH juegos_developers AS (
    SELECT
        CAST(appid AS INT) AS appid,
        LEFT(TRIM('[]'' ' FROM UNNEST(STRING_TO_ARRAY(developers, ','))), 150) AS developer_name
    FROM temp_games
    WHERE developers <> '[]'
)
SELECT DISTINCT
    jd.appid,
    d.developer_id
FROM juegos_developers jd
JOIN dim_developer d ON d.developer_name = jd.developer_name;

/*===================================================================
	CARGA DE game_platform
=====================================================================*/
INSERT INTO game_platform (appid, platform_id)
-- Juegos disponibles en Windows
SELECT CAST(t.appid AS INT), p.platform_id
FROM temp_games t
JOIN dim_platform p ON p.platform_name = 'Windows'
WHERE t.windows = 'True'

UNION ALL

-- Juegos disponibles en Mac
SELECT CAST(t.appid AS INT), p.platform_id
FROM temp_games t
JOIN dim_platform p ON p.platform_name = 'Mac'
WHERE t.mac = 'True'

UNION ALL

-- Juegos disponibles en Linux
SELECT CAST(t.appid AS INT), p.platform_id
FROM temp_games t
JOIN dim_platform p ON p.platform_name = 'Linux'
WHERE t.linux = 'True';

/*===================================================================
	ELIMINACION DEL CONTENIDO DE temp_games
=====================================================================*/
DELETE FROM temp_games;