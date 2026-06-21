/*=====================================================
	03_eda.sql
	Análisis exploratorio e insights de negocio
======================================================*/

/*=====================================================
	BLOQUE DE VIEWs Y FUNCION
======================================================*/
/*=====================================================
	VIEW 1: vw_valoracion_por_genero
	La usaré para consultar rápidamente que géneros valora
	mejor la comunidad, sin repetir el cálculo cada vez
======================================================*/
DROP VIEW IF EXISTS vw_valoracion_por_genero;
CREATE VIEW vw_valoracion_por_genero AS
SELECT
	g.genre_name AS genero,
	SUM(f.positive_reviews) AS total_positivas,
	SUM(f.negative_reviews) AS total_negativas,
	ROUND(100.0 * SUM(f.positive_reviews) / NULLIF(SUM(f.positive_reviews) + SUM(f.negative_reviews), 0), 2) AS pct_positivas
FROM fact_games f
JOIN game_genre gg ON f.appid = gg.appid
JOIN dim_genre g ON gg.genre_id = g.genre_id
GROUP BY g.genre_name
HAVING SUM(f.positive_reviews) + SUM(f.negative_reviews) > 10000;

/*=====================================================
	VIEW 2: vw_resumen_publisher
	La usaré para calcular el número de juegos y el %
	de valoraciones positivas de cada publisher
======================================================*/
DROP VIEW IF EXISTS vw_resumen_publisher;
CREATE VIEW vw_resumen_publisher AS
WITH stats_publisher AS (
	SELECT
		p.publisher_name AS publisher,
		COUNT(*) AS total_juegos,
		SUM(f.positive_reviews) AS reviews_positivas,
		SUM(f.negative_reviews) AS reviews_negativas
	FROM fact_games f
	JOIN dim_publisher p ON f.publisher_id = p.publisher_id
	WHERE p.publisher_name <> 'Unknown'
	GROUP BY p.publisher_name
), valoracion AS (
	SELECT
		publisher,
		total_juegos,
		ROUND(100.0 * reviews_positivas / NULLIF(reviews_positivas + reviews_negativas, 0), 2) AS pct_positivas
	FROM stats_publisher
	WHERE total_juegos >= 10
)
SELECT * FROM valoracion;

/*=====================================================
	FUNCTION: fc_pct_positivas
	Dado un appid, devuelve su % de reseñas positivas,
	si el juego no tiene reseñas, devuelve NULL
======================================================*/
DROP FUNCTION IF EXISTS fn_pct_positivas(INT);
CREATE FUNCTION fn_pct_positivas(p_appid INT)
RETURNS NUMERIC AS $$
	SELECT ROUND(100.0 * positive_reviews / NULLIF(positive_reviews + negative_reviews, 0), 2)
	FROM fact_games WHERE appid = p_appid;
$$ LANGUAGE SQL;




/*=====================================================
	RESUMEN GENERAL: Tamaño del catálogo, precio medio
	y peso del free-to-play en Steam
======================================================*/
SELECT
	COUNT(*) AS total_juegos,
	ROUND(AVG(price), 2) AS precio_medio,
	COUNT(*) FILTER(WHERE price = 0) AS juegos_gratuitos,
	ROUND(100.0 * COUNT(*) FILTER(WHERE price = 0) / COUNT(*),2) || '%' AS pct_gratuitos,
	MIN(release_date) AS primer_lanzamiento,
	MAX(release_date) AS último_lanzamiento
FROM fact_games;

/*=====================================================
	ANÁLISIS 1: Distribución de los juegos por año de
	lanzamiento
	Objetivo: Ver la evolución del número de lanzamientos
	por año
	Insight: Medir el crecimiento de Steam
======================================================*/
SELECT
	c.year_num AS año,
	COUNT(*) AS total_juegos
FROM fact_games f
JOIN dim_calendar c ON f.release_date = c.date_id
GROUP BY c.year_num
ORDER BY c.year_num;

/*=====================================================
	ANÁLISIS 2: Top 10 géneros por número de juegos
	Objetivo: Ver que géneros dominan el catálogo de Steam
	Insight: Que tipo de juegos son más frecuentes
======================================================*/
SELECT
	g.genre_name AS genero,
	COUNT(*) AS total_juegos
FROM game_genre gg
JOIN dim_genre g ON gg.genre_id = g.genre_id
GROUP BY g.genre_name
ORDER BY total_juegos DESC
LIMIT 10;

/*=====================================================
	ANÁLISIS 3: Top géneros mejor valorados
	Objetivo: Qué género tiene el mejor % de reseñas
	positivas. Para esto utilizo la VIEW vw_valoracion_por_genero
	Insight: El género más abundante no tiene por que
	ser el mejor valorado
======================================================*/
SELECT * FROM vw_valoracion_por_genero ORDER BY pct_positivas DESC;

/*=====================================================
	ANÁLISIS 4: Free-to-play vs pago: popularidad
	Objetivo: Comparar el pico de jugadores entre juegos
	gratuitos y de pago
	Insight: ¿Los juegos gratuitos atraen a más jugadores?
======================================================*/
SELECT
	CASE WHEN price = 0 THEN 'Gratuito' ELSE 'Pago' END AS tipo,
	COUNT(*) AS totalo_juegos,
	ROUND(AVG(peak_ccu), 2) AS media_pico_jugadores,
	MAX(peak_ccu) AS max_pico_jugadores
FROM fact_games
GROUP BY tipo;

/*=====================================================
	ANÁLISIS 5: Relación entre precio y valoración
	Objetivo: Ver si los juegos ás caros se valoran mejor.
	Para ello agrupo los juegos en tramos de precio y
	calculo el % medio de reseñas positivas en cada tramo.
	Insight: ¿Pagar más significa que es un mejor juego?
======================================================*/
SELECT
	CASE
		WHEN price = 0 THEN '1. Gratuíto'
		WHEN price < 5 THEN '2. Menos de 5$'
		WHEN price < 15 THEN '3. De 5$ a 15$'
		WHEN price < 30 THEN '4. De 15$ a 30$'
		ELSE '5. Más de 30$'
	END AS tramo_precio,
	COUNT(*) AS total_juegos,
	ROUND(100.0 * SUM(positive_reviews) / NULLIF(SUM(positive_reviews) + SUM(negative_reviews), 0), 2) AS pct_positivas
FROM fact_games
GROUP BY tramo_precio
ORDER BY tramo_precio;

/*=====================================================
	ANÁLISIS 6: Distribución de juegos por plataforma
	Objetivo: Ver en que plataformas están disponibles
	los juegos. Calculo el % sobre el total de juegos del
	catálogo
	Insight: Peso real de Mac y Linux frente a Windows
======================================================*/
SELECT
	p.platform_name AS plataforma,
	COUNT(*) AS total_juegos,
	ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_games), 2) AS pct_catálogo
FROM game_platform gp
JOIN dim_platform p ON gp.platform_id = p.platform_id
GROUP BY p.platform_name
ORDER BY total_juegos DESC;

/*=====================================================
	ANÁLISIS 7: Top 3 juegos por propietarios dentro de
	cada género
	Objetivo: Saber cuales son los juegos más populares
	por genero. Para ello hago un CTE para rankear
	los juegos dentro de cada género por separado
	Insight: ¿Cúales son los "buques insignia" de cada género?
======================================================*/
WITH ranking AS (
	SELECT
		g.genre_name AS genero,
		f.name AS juego,
		f.owners_max AS propietarios_max,
		f.peak_ccu AS pico_jugadores,
		fn_pct_positivas(f.appid) AS pct_positivas,
		RANK() OVER (PARTITION BY g.genre_name ORDER BY f.owners_max DESC, f.peak_ccu DESC) AS posicion
	FROM fact_games f
	JOIN game_genre gg ON f.appid = gg.appid
	JOIN dim_genre g ON gg.genre_id = g.genre_id
)
SELECT genero, juego, propietarios_max, pico_jugadores, pct_positivas, posicion
FROM ranking
WHERE posicion <= 3
ORDER BY genero, posicion;

/*=====================================================
	ANÁLISIS 8: Publishers más prolíficos y su valoración
	media
	Objetivo: Qué publishers publican más y cómo se valoran
	Para ello utilizo la VIEW vw_resumen_publisher
	Insight: El volumen no siempre va de la mano de calidad
======================================================*/
SELECT * FROM vw_resumen_publisher ORDER BY total_juegos DESC LIMIT 15;

/*=====================================================
	ANÁLISIS 9: Estacionalidad de lanzamientos por trimestre
   Objetivo: ver si hay trimestres con más lanzamientos.
   Uso dim_calendar para agrupar por trimestre
   Insight: ¿Existe un patrón estacional en los lanzamientos?
======================================================*/
SELECT
	c.quarter_num AS trimestre,
	COUNT(*) AS total_lanzamientos,
	ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_games), 2) AS pct_total
FROM fact_games f
JOIN dim_calendar c ON f.release_date = c.date_id
GROUP BY c.quarter_num
ORDER BY c.quarter_num;