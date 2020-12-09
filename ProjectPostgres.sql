--Restore to stockmarket2.backup
-------------------------------------------------------------------------
-- We have stock quotes but we could also use daily index data ----------
-------------------------------------------------------------------------

-- Let's download 2012-2018 of SP500TR from Yahoo https://finance.yahoo.com/quote/%5ESP500TR/history?p=^SP500TR

-- An analysis of the CSV indicated that a "symbol" column must be added with the value SP500TR

-- Import the (modified) CSV to a (new) data table eod_indices which reflects the original file's structure

/*
LIFELINE:

-- DROP TABLE public.eod_indices;

CREATE TABLE public.eod_indices
(
    symbol character varying(16) COLLATE pg_catalog."default" NOT NULL,
    date date NOT NULL,
    open real,
    high real,
    low real,
    close real,
    adj_close real,
    volume double precision,
    CONSTRAINT eod_indices_pkey PRIMARY KEY (symbol, date)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.eod_indices
    OWNER to postgres;

*/
-- Check
SELECT * FROM eod_indices LIMIT 10;

-------------------------------------------------------------------------
-- Next, let's prepare a custom calendar (using a spreadsheet) --------
-------------------------------------------------------------------------

-- We need a stock market calendar to check our data for completeness

-- Because it is faster, we will use Excel (we need market holidays to do that)

-- We will use NETWORKDAYS.INTL function

-- date, y,m,d,dow,trading (format date and dow!)

-- Save as custom_calendar.csv and import to a new table

/*
LIFELINE:
-- DROP TABLE public.custom_calendar;

CREATE TABLE public.custom_calendar
(
    date date NOT NULL,
    y bigint,
    m bigint,
    d bigint,
    dow character varying(3) COLLATE pg_catalog."default",
    trading smallint,
    CONSTRAINT custom_calendar_pkey PRIMARY KEY (date)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.custom_calendar
    OWNER to postgres;

*/

-- CHECK:
SELECT * FROM custom_calendar LIMIT 10;

-- Let's add some columns to be used later: eom (end-of-month) and prev_trading_day

/*
-- LIFELINE
ALTER TABLE public.custom_calendar
    ADD COLUMN eom smallint;

ALTER TABLE public.custom_calendar
    ADD COLUMN prev_trading_day date;
*/

-- CHECK:
SELECT * FROM custom_calendar LIMIT 10;

-- Now let's populate these columns

-- Identify trading days
SELECT * FROM custom_calendar WHERE trading=1;
-- Identify previous trading days via a nested query
SELECT date, (SELECT MAX(CC.date) FROM custom_calendar CC WHERE CC.trading=1 AND CC.date<custom_calendar.date) ptd 
FROM custom_calendar;
-- Update the table with new data (this will take some time)
UPDATE custom_calendar
SET prev_trading_day = PTD.ptd
FROM (SELECT date, (SELECT MAX(CC.date) FROM custom_calendar CC WHERE CC.trading=1 AND CC.date<custom_calendar.date) ptd FROM custom_calendar) PTD
WHERE custom_calendar.date = PTD.date;
-- CHECK
SELECT * FROM custom_calendar ORDER BY date;
-- We could really use the last trading day of 2011 (as the end of the month)
INSERT INTO custom_calendar VALUES('2011-12-30',2011,12,30,'Fri',1,1,NULL);
-- Re-run the update
-- CHECK again
SELECT * FROM custom_calendar ORDER BY date;

-- Identify the end of the month
SELECT CC.date,CASE WHEN EOM.y IS NULL THEN 0 ELSE 1 END endofm FROM custom_calendar CC LEFT JOIN
(SELECT y,m,MAX(d) lastd FROM custom_calendar WHERE trading=1 GROUP by y,m) EOM
ON CC.y=EOM.y AND CC.m=EOM.m AND CC.d=EOM.lastd;
-- Update the table with new data (this will take some time)
UPDATE custom_calendar
SET eom = EOMI.endofm
FROM (SELECT CC.date,CASE WHEN EOM.y IS NULL THEN 0 ELSE 1 END endofm FROM custom_calendar CC LEFT JOIN
(SELECT y,m,MAX(d) lastd FROM custom_calendar WHERE trading=1 GROUP by y,m) EOM
ON CC.y=EOM.y AND CC.m=EOM.m AND CC.d=EOM.lastd) EOMI
WHERE custom_calendar.date = EOMI.date;
-- CHECK
SELECT * FROM custom_calendar ORDER BY date;
SELECT * FROM custom_calendar WHERE eom=1 ORDER BY date;

-------------------------------------------
-- Create a role for the database  --------
-------------------------------------------
-- rolename: stockmarketreader
-- password: read123

/*
-- LIFELINE:
-- REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM stockmarketreader;
-- DROP USER stockmarketreader;

CREATE USER stockmarketreader WITH
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	PASSWORD 'read123';
*/

-- Grant read rights (on existing tables and views)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO stockmarketreader;

-- Grant read rights (for future tables and views)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
   GRANT SELECT ON TABLES TO stockmarketreader;
   
