# data analysis of the chinook DB
# https://github.com/lerocha/chinook-database
# Using MySQL

# Intially I want to see which customers spend the most money yearly
# Top 5 customers 

SELECT * FROM
(
SELECT sq1.business_year, sq1.CustomerId, sq1.average_customer_order,
		sq1.total_yearly_spend,
		ROUND((sq1.total_yearly_spend / sq2.total_income) * 100, 2) AS percent_of_sales,
        row_number() OVER (partition by sq1.business_year ORDER by sq1.total_yearly_spend DESC) as customer_ranking
FROM
( 
SELECT extract(YEAR from inv.invoiceDate) AS business_year, c.CustomerId AS CustomerId,
		sum(invline.UnitPrice * invline.Quantity) AS total_yearly_spend,
        ROUND(AVG(invline.unitprice), 2) AS average_customer_order
FROM invoiceline as invline
INNER JOIN invoice as inv
	ON invline.InvoiceId = inv.InvoiceId
INNER JOIN  customer AS c
	ON c.CustomerId = inv.CustomerId
group by extract(YEAR from inv.invoiceDate), c.CustomerId
) AS sq1
CROSS JOIN(
SELECT sum(invline.unitprice * invline.quantity) AS total_income
FROM invoiceline as invline
) AS sq2
) AS sq3
WHERE sq3.customer_ranking <= 5;

# Query breakdown:
# sq1 joins all the relevant data together, grouping by year and customer Id as the desired result is to see highest spending customers per year.
# I am using typical aggregates in sq1, doing a sum to see the total spending of the customer per year, and also doing an average in order to see the average spending of the same customer
# I cross join SQ2 so i will be able to create a percentage of total sales col in the future.
# The reason for the cross join is because I need the total sales amount in each row for the calculation, so the underused cross join is actually very useful here
# In sq3 i do a window function in order to rank the highest spending customers per year, arbitrarily assigning numbers to ties with row_number()
# Finally the entirety of query is wrapped as sq3 so i can easily filter the results to the top 5.


# Next ill check the total sales by genre

# Creating a view I am going to refrence multiple time in the next query
CREATE VIEW total_sales_genre_vw
(
genreName, sales
)
AS 
SELECT g.Name AS genreName, sum(invline.UnitPrice * invline.Quantity) AS sales
FROM track AS t
INNER JOIN genre AS g
	on t.GenreId = g.GenreId
INNER JOIN invoiceline AS invline
	on invline.TrackId = t.TrackId
INNER JOIN invoice AS inv
	on inv.InvoiceId = invline.InvoiceId
GROUP BY g.Name;


#total sales by genre
SELECT view1.genrename, view1.sales,
	row_number() OVER (ORDER BY view1.sales DESC) AS sales_ranking
FROM total_sales_genre_vw AS view1;

# I noticed we have some none music in this DB, stuff like tv shows.
# I'll do a case when to see the difference in sales between music and none music

#music vs tv/film
SELECT sq.subcategory, sum(sq.sales) AS total_sales
FROM
(
SELECT 
	CASE
		WHEN view1.genrename IN ('Rock', 'Latin', 'Metal', 'Alternative & Punk',
        'Jazz', 'Blues', 'R&B/Soul', 'Classical', 'Reggae', 'Pop',
        'Hip Hop/Rap', 'Bossa Nova', 'Alternative', 'World', 'Heavy Metal',
        'Electronica/Dance', 'Easy Listening', 'Rock And Roll')
		THEN 'Music'
		WHEN view1.genrename IN ('TV Shows', 'Drama', 'Sci Fi & Fantasy',
								'Soundtrack', 'Comedy', 'Science Fiction')
		THEN 'TV_Film'
		ELSE 'Other'
	END AS subcategory,
view1.sales AS sales
FROM total_sales_genre_vw AS view1
) AS sq
GROUP BY sq.subcategory;


# Query breakdown
# For the creation of "total_sales_genre_vw",
# used inner join here since I'm only interested in songs that have a genre assigned,
# and were actually involved in business activity.
# for the case when query, i did a SQ because of the SQL order of execution.
# I can't actually refer to the CASE WHEN end result and group on them because the select statement executes last.


# Yearly genre sales trend, using a CTE

WITH yearly_sales AS
(
SELECT EXTRACT(YEAR from inv.InvoiceDate) as business_year ,g.Name AS genreName, sum(invline.UnitPrice * invline.Quantity) AS sales
FROM track AS t
INNER JOIN genre AS g
	on t.GenreId = g.GenreId
INNER JOIN invoiceline AS invline
	on invline.TrackId = t.TrackId
INNER JOIN invoice AS inv
	on inv.InvoiceId = invline.InvoiceId
GROUP BY g.Name, EXTRACT(YEAR from inv.InvoiceDate)
)

SELECT current_year.business_year, current_year.genreName, current_year.sales,
		CASE
			WHEN current_year.business_year = '2021'
		THEN 'Intial year'
			WHEN 
			((current_year.sales - previous_year.sales) / previous_year.sales) * 100  IS NULL
		THEN '0%'
			ELSE
			CONCAT(ROUND(((current_year.sales - previous_year.sales) / previous_year.sales) * 100, 2), '%') END as yoy_change
FROM 
  yearly_sales AS current_year
LEFT OUTER JOIN yearly_sales AS previous_year 
  ON current_year.genreName = previous_year.genreName
	AND current_year.business_year = previous_year.business_year + 1;
    
# Query breakdown
# Decided to use a CTE this time,
# The expression is a query that is very similar to the one I used for the view earlier, this time grouping by year as well
# Using the CTE allowed me to easily do the yoy change calculation by joining the CTE to itself
# another benefit is that the results are not aggregated, so I can do further filtering without having to wrap in a SQ
# Like seeing only a specific year, genre, or to only see changes that are above/below a certain percentage
# I did a case statement to avoid having any mislabeled NULLs, also made sure to correctly label initial year, since giving it a label of 0% could be misleading.

#RFM analysis of customers
	
SELECT sqr.CustomerId, sqr.Recency, sqf.Frequency, sqm.Monetary_value,
	(sqr.Recency + sqf.Frequency + sqm.Monetary_value) AS RFM_score
FROM
(
SELECT c.CustomerId AS CustomerId,
	CASE
		WHEN datediff('2025-12-22', max(inv.invoiceDate)) <= 30 THEN 10
        	WHEN datediff('2025-12-22', max(inv.invoiceDate)) <= 180 THEN 5
        ELSE 1
        END as Recency
FROM invoice AS inv
INNER JOIN customer AS c
	ON c.CustomerId = inv.CustomerId
GROUP BY c.CustomerId
) AS sqr
INNER JOIN
(
SELECT c.CustomerId AS CustomerId,
	CASE
		WHEN count(inv.InvoiceId) >= 10 THEN 10
		WHEN count(inv.InvoiceId) >= 3 THEN 5
        ELSE 1
        END AS Frequency
FROM invoice AS inv
INNER JOIN customer AS c
	ON c.CustomerId = inv.CustomerId
WHERE inv.InvoiceDate BETWEEN '2024-12-22' AND '2025-12-22'
GROUP BY c.CustomerId
) AS sqf
ON sqr.CustomerId = sqf.CustomerId
INNER JOIN
(
SELECT c.CustomerId AS CustomerId,
	CASE
		WHEN SUM(inv.Total) >= 20 THEN 10
		WHEN SUM(inv.Total) >= 10 THEN 5
        ELSE 1
        END AS Monetary_value
FROM invoice AS inv
INNER JOIN customer AS c
	ON c.CustomerId = inv.CustomerId
WHERE inv.InvoiceDate BETWEEN '2024-12-22' AND '2025-12-22'
GROUP BY c.CustomerId) AS sqm
on sqr.CustomerId = sqm.CustomerId
ORDER BY sqr.customerId;

#Query breakdown
#The purpose of this query is to assign score based on the RFM metrics: recency, frequency, and monetary value.
#Customers were given a score for each metric using a case statement, and all the subqueries were joined.
#It's possible to further segment this query, for example filtering for high RFM scores to identify loyal customers,
#Or to filter for customers with a high monetary value but low recency to identify people who are leaving the platform.
#The dates inside the various SQs can be easily adjusted with business needs, making this a very flexible query.


#top 5 yearly number of tracks sold by artist with ranking and yoy change

WITH yearly_artist_num_tracks AS
(
SELECT EXTRACT(YEAR from inv.InvoiceDate) AS year, artst.name AS Artist, SUM(invline.Quantity) AS num_tracks_sold
FROM invoiceline AS invline
	INNER JOIN track AS t
		ON invline.TrackId = t.TrackId
	INNER JOIN album AS albm 
		ON t.AlbumId = albm.AlbumId
	INNER JOIN artist AS artst
		ON albm.ArtistId = artst.ArtistId
	INNER JOIN invoice AS inv
		ON invline.InvoiceId = inv.InvoiceId
GROUP BY artst.Name, EXTRACT(YEAR from inv.InvoiceDate)
),
ranked_artists AS
(
SELECT current_year.year, current_year.Artist, current_year.num_tracks_sold,
		CASE
			WHEN current_year.year = '2021'
		THEN 'Intial year'
			WHEN 
			((current_year.num_tracks_sold - previous_year.num_tracks_sold) / previous_year.num_tracks_sold) * 100  IS NULL
		THEN '0%'
			ELSE
			CONCAT(ROUND(((current_year.num_tracks_sold - previous_year.num_tracks_sold) / previous_year.num_tracks_sold) * 100, 2), '%') END as yoy_change,
            row_number() over (partition by current_year.year ORDER BY current_year.num_tracks_sold DESC) AS yearly_ranking
FROM 
  yearly_artist_num_tracks AS current_year
LEFT OUTER JOIN yearly_artist_num_tracks AS previous_year 
  ON current_year.Artist = previous_year.Artist
	AND current_year.year = previous_year.year + 1
)
SELECT *
FROM ranked_artists
WHERE yearly_ranking <=5;

#query breakdown
#This query uses two CTEs. the first one is essentially identical to the one in the yearly genre sales trend
#The second CTE contains a similar yoy calculation that I used earlier in additional to a row_number window function.
#the second CTE was wrapped as a CTE purely to allow it to be filtered.
