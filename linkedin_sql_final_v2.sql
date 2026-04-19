-- ============================================================
-- PROJET LINKEDIN — SQL COMPLET FINAL
-- Jointure clé : TRY_TO_NUMBER(jp.company_name) = TRY_TO_NUMBER(c.company_id)
-- car company_name dans JOB_POSTINGS contient en réalité le company_id
-- ============================================================

-- ============================================================
-- 0. INITIALISATION
-- ============================================================
CREATE DATABASE IF NOT EXISTS LINKEDIN;
USE DATABASE LINKEDIN;

CREATE OR REPLACE SCHEMA LINKEDIN.BRONZE;
CREATE OR REPLACE SCHEMA LINKEDIN.SILVER;
CREATE OR REPLACE SCHEMA LINKEDIN.GOLD;

CREATE OR REPLACE STAGE LINKEDIN_STAGE
    URL = 's3://snowflake-lab-bucket/';

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE                         = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER                  = 1
    NULL_IF                      = ('NULL', 'null', '', 'N/A')
    EMPTY_FIELD_AS_NULL          = TRUE;


-- ============================================================
-- 1. BRONZE — Ingestion brute
-- ============================================================

-- ---- 1.1 JOB_POSTINGS (CSV) --------------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.JOB_POSTINGS (
    job_id                      STRING,
    company_name                STRING,
    title                       STRING,
    description                 STRING,
    max_salary                  STRING,
    med_salary                  STRING,
    min_salary                  STRING,
    pay_period                  STRING,
    formatted_work_type         STRING,
    location                    STRING,
    applies                     STRING,
    original_listed_time        STRING,
    remote_allowed              STRING,
    views                       STRING,
    job_posting_url             STRING,
    application_url             STRING,
    application_type            STRING,
    expiry                      STRING,
    closed_time                 STRING,
    formatted_experience_level  STRING,
    skills_desc                 STRING,
    listed_time                 STRING,
    posting_domain              STRING,
    sponsored                   STRING,
    work_type                   STRING,
    currency                    STRING,
    compensation_type           STRING
);

COPY INTO LINKEDIN.BRONZE.JOB_POSTINGS
FROM @LINKEDIN_STAGE/job_postings.csv
FILE_FORMAT = CSV_FORMAT;

SELECT COUNT(*) AS nb_bronze_job_postings FROM LINKEDIN.BRONZE.JOB_POSTINGS;


-- ---- 1.2 COMPANIES (JSON) ----------------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.COMPANIES (DATA VARIANT);

COPY INTO LINKEDIN.BRONZE.COMPANIES
FROM @LINKEDIN_STAGE/companies.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;

SELECT COUNT(*) AS nb_bronze_companies FROM LINKEDIN.BRONZE.COMPANIES;


-- ---- 1.3 JOB_SKILLS (CSV) ----------------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.JOB_SKILLS (
    job_id    STRING,
    skill_abr STRING
);

COPY INTO LINKEDIN.BRONZE.JOB_SKILLS
FROM @LINKEDIN_STAGE/job_skills.csv
FILE_FORMAT = CSV_FORMAT;

SELECT COUNT(*) AS nb_bronze_job_skills FROM LINKEDIN.BRONZE.JOB_SKILLS;


-- ---- 1.4 BENEFITS (CSV) ------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.BENEFITS (
    job_id   STRING,
    inferred STRING,
    type     STRING
);

COPY INTO LINKEDIN.BRONZE.BENEFITS
FROM @LINKEDIN_STAGE/benefits.csv
FILE_FORMAT = CSV_FORMAT;

SELECT COUNT(*) AS nb_bronze_benefits FROM LINKEDIN.BRONZE.BENEFITS;


-- ---- 1.5 EMPLOYEE_COUNTS (CSV) -----------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.EMPLOYEE_COUNTS (
    company_id     STRING,
    employee_count STRING,
    follower_count STRING,
    time_recorded  STRING
);

COPY INTO LINKEDIN.BRONZE.EMPLOYEE_COUNTS
FROM @LINKEDIN_STAGE/employee_counts.csv
FILE_FORMAT = CSV_FORMAT;

SELECT COUNT(*) AS nb_bronze_employee_counts FROM LINKEDIN.BRONZE.EMPLOYEE_COUNTS;


-- ---- 1.6 JOB_INDUSTRIES (JSON) -----------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.JOB_INDUSTRIES (DATA VARIANT);

COPY INTO LINKEDIN.BRONZE.JOB_INDUSTRIES
FROM @LINKEDIN_STAGE/job_industries.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;

SELECT COUNT(*) AS nb_bronze_job_industries FROM LINKEDIN.BRONZE.JOB_INDUSTRIES;


-- ---- 1.7 COMPANY_SPECIALITIES (JSON) -----------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.COMPANY_SPECIALITIES (DATA VARIANT);

COPY INTO LINKEDIN.BRONZE.COMPANY_SPECIALITIES
FROM @LINKEDIN_STAGE/company_specialities.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;

SELECT COUNT(*) AS nb_bronze_company_specialities FROM LINKEDIN.BRONZE.COMPANY_SPECIALITIES;


-- ---- 1.8 COMPANY_INDUSTRIES (JSON) -------------------------
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.COMPANY_INDUSTRIES (DATA VARIANT);

COPY INTO LINKEDIN.BRONZE.COMPANY_INDUSTRIES
FROM @LINKEDIN_STAGE/company_industries.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;

SELECT COUNT(*) AS nb_bronze_company_industries FROM LINKEDIN.BRONZE.COMPANY_INDUSTRIES;


-- ============================================================
-- 2. SILVER — Nettoyage et typage
-- ============================================================

-- ---- 2.1 JOB_POSTINGS --------------------------------------
-- NOTE : la colonne company_name contient en réalité un company_id
-- numérique (ex: 54844.0). On la garde telle quelle et on jointure
-- via TRY_TO_NUMBER() dans les analyses.
CREATE OR REPLACE TABLE LINKEDIN.SILVER.JOB_POSTINGS AS
SELECT
    TRIM(job_id)                                                AS job_id,
    TRIM(company_name)                                          AS company_id_raw,
    TRY_TO_NUMBER(TRIM(company_name))                           AS company_id,
    TRIM(title)                                                 AS title,
    description,
    TRY_CAST(max_salary AS FLOAT)                               AS max_salary,
    TRY_CAST(med_salary AS FLOAT)                               AS med_salary,
    TRY_CAST(min_salary AS FLOAT)                               AS min_salary,
    pay_period,
    formatted_work_type,
    location,
    TRY_CAST(applies AS INT)                                    AS applies,
    TO_TIMESTAMP(TRY_CAST(original_listed_time AS NUMBER) / 1000)
                                                                AS original_listed_time,
    IFF(UPPER(TRIM(remote_allowed)) = 'TRUE', TRUE, FALSE)      AS remote_allowed,
    TRY_CAST(views AS INT)                                      AS views,
    job_posting_url,
    application_url,
    application_type,
    TO_TIMESTAMP(TRY_CAST(expiry AS NUMBER) / 1000)             AS expiry,
    TO_TIMESTAMP(TRY_CAST(closed_time AS NUMBER) / 1000)        AS closed_time,
    formatted_experience_level,
    skills_desc,
    TO_TIMESTAMP(TRY_CAST(listed_time AS NUMBER) / 1000)        AS listed_time,
    posting_domain,
    IFF(UPPER(TRIM(sponsored)) = 'TRUE', TRUE, FALSE)           AS sponsored,
    work_type,
    currency,
    compensation_type,
    CASE
        WHEN skills_desc IS NULL OR TRIM(skills_desc) = '' THEN 0
        ELSE ARRAY_SIZE(SPLIT(skills_desc, ','))
    END                                                         AS num_skills,
    CASE
        WHEN TRY_CAST(max_salary AS FLOAT) IS NULL  THEN 'unknown'
        WHEN TRY_CAST(max_salary AS FLOAT) < 40000  THEN 'low'
        WHEN TRY_CAST(max_salary AS FLOAT) <= 90000 THEN 'medium'
        ELSE                                              'high'
    END                                                         AS salary_range
FROM LINKEDIN.BRONZE.JOB_POSTINGS
WHERE TRIM(job_id) IS NOT NULL
  AND TRIM(job_id) != '';

SELECT COUNT(*) AS nb_silver_job_postings FROM LINKEDIN.SILVER.JOB_POSTINGS;


-- ---- 2.2 COMPANIES -----------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANIES AS
SELECT
    DATA:company_id::STRING     AS company_id,
    DATA:name::STRING           AS company_name,
    DATA:description::STRING    AS description,
    DATA:company_size::STRING   AS company_size,
    DATA:state::STRING          AS state,
    DATA:country::STRING        AS country,
    DATA:city::STRING           AS city,
    DATA:zip_code::STRING       AS zip_code,
    DATA:address::STRING        AS address,
    DATA:url::STRING            AS url
FROM LINKEDIN.BRONZE.COMPANIES
WHERE IS_OBJECT(DATA)
  AND DATA:company_id IS NOT NULL;

SELECT COUNT(*) AS nb_silver_companies FROM LINKEDIN.SILVER.COMPANIES;


-- ---- 2.3 JOB_SKILLS ----------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.JOB_SKILLS AS
SELECT
    TRIM(job_id)    AS job_id,
    TRIM(skill_abr) AS skill_abr
FROM LINKEDIN.BRONZE.JOB_SKILLS
WHERE TRIM(job_id) IS NOT NULL
  AND TRIM(job_id) != '';

SELECT COUNT(*) AS nb_silver_job_skills FROM LINKEDIN.SILVER.JOB_SKILLS;


-- ---- 2.4 BENEFITS ------------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.BENEFITS AS
SELECT
    TRIM(job_id) AS job_id,
    inferred,
    type
FROM LINKEDIN.BRONZE.BENEFITS
WHERE TRIM(job_id) IS NOT NULL
  AND TRIM(job_id) != '';

SELECT COUNT(*) AS nb_silver_benefits FROM LINKEDIN.SILVER.BENEFITS;


-- ---- 2.5 EMPLOYEE_COUNTS -----------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.EMPLOYEE_COUNTS AS
SELECT
    TRIM(company_id)                                        AS company_id,
    TRY_CAST(employee_count AS INT)                         AS employee_count,
    TRY_CAST(follower_count AS INT)                         AS follower_count,
    TO_TIMESTAMP(TRY_CAST(time_recorded AS NUMBER) / 1000)  AS time_recorded
FROM LINKEDIN.BRONZE.EMPLOYEE_COUNTS
WHERE TRIM(company_id) IS NOT NULL
  AND TRIM(company_id) != '';

SELECT COUNT(*) AS nb_silver_employee_counts FROM LINKEDIN.SILVER.EMPLOYEE_COUNTS;


-- ---- 2.6 JOB_INDUSTRIES ------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.JOB_INDUSTRIES AS
SELECT
    DATA:job_id::STRING         AS job_id,
    DATA:industry_id::STRING    AS industry_id
FROM LINKEDIN.BRONZE.JOB_INDUSTRIES
WHERE IS_OBJECT(DATA)
  AND DATA:job_id IS NOT NULL;

SELECT COUNT(*) AS nb_silver_job_industries FROM LINKEDIN.SILVER.JOB_INDUSTRIES;


-- ---- 2.7 COMPANY_SPECIALITIES ------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANY_SPECIALITIES AS
SELECT
    DATA:company_id::STRING  AS company_id,
    DATA:speciality::STRING  AS speciality
FROM LINKEDIN.BRONZE.COMPANY_SPECIALITIES
WHERE IS_OBJECT(DATA)
  AND DATA:company_id IS NOT NULL;

SELECT COUNT(*) AS nb_silver_company_specialities FROM LINKEDIN.SILVER.COMPANY_SPECIALITIES;


-- ---- 2.8 COMPANY_INDUSTRIES --------------------------------
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANY_INDUSTRIES AS
SELECT
    DATA:company_id::STRING  AS company_id,
    DATA:industry::STRING    AS industry_id
FROM LINKEDIN.BRONZE.COMPANY_INDUSTRIES
WHERE IS_OBJECT(DATA)
  AND DATA:company_id IS NOT NULL;

SELECT COUNT(*) AS nb_silver_company_industries FROM LINKEDIN.SILVER.COMPANY_INDUSTRIES;


-- ============================================================
-- 3. CONTROLE QUALITE SILVER
-- ============================================================

-- Jointure JOB_POSTINGS <-> COMPANIES via company_id
SELECT COUNT(*) AS join_jobs_companies
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id = TRY_TO_NUMBER(c.company_id);

-- Jointure COMPANIES <-> COMPANY_INDUSTRIES
SELECT COUNT(*) AS join_companies_industries
FROM LINKEDIN.SILVER.COMPANIES c
JOIN LINKEDIN.SILVER.COMPANY_INDUSTRIES ci
    ON c.company_id = ci.company_id;

-- Jointure JOB_POSTINGS <-> JOB_INDUSTRIES
SELECT COUNT(*) AS join_jobs_industries
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji
    ON jp.job_id = ji.job_id;

-- Taux de remplissage
SELECT
    COUNT(*)                                             AS total_offres,
    COUNT(med_salary)                                    AS avec_salaire,
    ROUND(COUNT(med_salary) * 100.0 / COUNT(*), 1)       AS pct_avec_salaire,
    SUM(IFF(remote_allowed = TRUE, 1, 0))                AS nb_remote
FROM LINKEDIN.SILVER.JOB_POSTINGS;

-- Valeurs company_size
SELECT company_size, COUNT(*) AS nb
FROM LINKEDIN.SILVER.COMPANIES
GROUP BY company_size
ORDER BY nb DESC;


-- ============================================================
-- 4. GOLD — Tables analytiques
-- ============================================================

-- ---- 4.1 DIM_JOBS ------------------------------------------
CREATE OR REPLACE VIEW LINKEDIN.GOLD.DIM_JOBS AS
SELECT
    jp.job_id,
    NVL(jp.title, 'Unknown')        AS job_title,
    c.company_name,
    jp.formatted_experience_level,
    jp.remote_allowed,
    jp.formatted_work_type,
    jp.num_skills,
    jp.salary_range,
    jp.listed_time,
    jp.original_listed_time
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id = TRY_TO_NUMBER(c.company_id);

SELECT COUNT(*) AS nb_gold_dim_jobs FROM LINKEDIN.GOLD.DIM_JOBS;


-- ---- 4.2 DIM_COMPANIES -------------------------------------
CREATE OR REPLACE VIEW LINKEDIN.GOLD.DIM_COMPANIES AS
SELECT
    company_id,
    NVL(company_name, 'Anonymous')  AS company_name,
    description,
    company_size,
    state,
    country,
    city,
    zip_code,
    address,
    url
FROM LINKEDIN.SILVER.COMPANIES;

SELECT COUNT(*) AS nb_gold_dim_companies FROM LINKEDIN.GOLD.DIM_COMPANIES;


-- ---- 4.3 FACT_JOBS -----------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.GOLD.FACT_JOBS AS
SELECT
    jp.*,
    c.company_name,
    c.company_size,
    c.country,
    c.city,
    (
        COALESCE(jp.max_salary, 0) * 0.4
        + COALESCE(jp.views, 0)    * 0.3
        + COALESCE(jp.applies, 0)  * 0.2
        + jp.num_skills * 50
        + IFF(jp.remote_allowed, 1000, 0)
    ) AS job_score
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id = TRY_TO_NUMBER(c.company_id)
WHERE jp.job_id IS NOT NULL;

SELECT COUNT(*) AS nb_gold_fact_jobs FROM LINKEDIN.GOLD.FACT_JOBS;


-- ---- 4.4 TOP_SKILLS_BY_INDUSTRY ----------------------------
CREATE OR REPLACE TABLE LINKEDIN.GOLD.TOP_SKILLS_BY_INDUSTRY AS
SELECT
    ji.industry_id,
    js.skill_abr,
    COUNT(*) AS skill_count
FROM LINKEDIN.SILVER.JOB_SKILLS js
JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji
    ON js.job_id = ji.job_id
GROUP BY ji.industry_id, js.skill_abr
ORDER BY ji.industry_id, skill_count DESC;

SELECT COUNT(*) AS nb_gold_top_skills FROM LINKEDIN.GOLD.TOP_SKILLS_BY_INDUSTRY;


-- ---- 4.5 FACT_BENEFITS -------------------------------------
CREATE OR REPLACE TABLE LINKEDIN.GOLD.FACT_BENEFITS AS
SELECT *
FROM LINKEDIN.SILVER.BENEFITS
WHERE job_id IS NOT NULL;

SELECT COUNT(*) AS nb_gold_fact_benefits FROM LINKEDIN.GOLD.FACT_BENEFITS;


-- ============================================================
-- 5. REQUETES ANALYTIQUES — pour Streamlit
-- ============================================================

-- ANALYSE 1 : Top 10 postes les plus publies par industrie
WITH ranked AS (
    SELECT
        ji.industry_id,
        jp.title,
        COUNT(*)        AS nb_offres,
        ROW_NUMBER() OVER (
            PARTITION BY ji.industry_id
            ORDER BY COUNT(*) DESC
        )               AS rn
    FROM LINKEDIN.SILVER.JOB_POSTINGS jp
    JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji
        ON jp.job_id = ji.job_id
    WHERE jp.title IS NOT NULL AND jp.title != ''
    GROUP BY ji.industry_id, jp.title
)
SELECT industry_id, title, nb_offres
FROM ranked
WHERE rn <= 10
ORDER BY industry_id, nb_offres DESC;


-- ANALYSE 2 : Top 10 postes les mieux remuneres par industrie
WITH salaires AS (
    SELECT
        ji.industry_id,
        jp.title,
        ROUND(AVG(NULLIF(jp.min_salary, 0)), 0) AS avg_min_salary,
        ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS avg_med_salary,
        ROUND(AVG(NULLIF(jp.max_salary, 0)), 0) AS avg_max_salary,
        COUNT(*)                                AS nb_offres,
        ROW_NUMBER() OVER (
            PARTITION BY ji.industry_id
            ORDER BY AVG(NULLIF(jp.med_salary, 0)) DESC NULLS LAST
        )                                       AS rn
    FROM LINKEDIN.SILVER.JOB_POSTINGS jp
    JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji
        ON jp.job_id = ji.job_id
    WHERE jp.med_salary IS NOT NULL
      AND jp.med_salary > 0
      AND jp.title IS NOT NULL
    GROUP BY ji.industry_id, jp.title
)
SELECT industry_id, title,
       avg_min_salary, avg_med_salary, avg_max_salary, nb_offres
FROM salaires
WHERE rn <= 10
ORDER BY industry_id, avg_med_salary DESC;


-- ANALYSE 3 : Repartition par taille d entreprise
-- Jointure via company_id (pas company_name)
SELECT
    CASE c.company_size
        WHEN '1' THEN '1 - Individuel'
        WHEN '2' THEN '2 - 2 a 10 emp.'
        WHEN '3' THEN '3 - 11 a 50 emp.'
        WHEN '4' THEN '4 - 51 a 200 emp.'
        WHEN '5' THEN '5 - 201 a 500 emp.'
        WHEN '6' THEN '6 - 501 a 1000 emp.'
        WHEN '7' THEN '7 - 1K a 5K emp.'
        WHEN '8' THEN '8 - 5K a 10K emp.'
        WHEN '9' THEN '9 - Plus de 10K emp.'
        ELSE          'Non renseigne'
    END                                         AS taille_entreprise,
    COUNT(jp.job_id)                            AS nb_offres,
    ROUND(
        COUNT(jp.job_id) * 100.0
        / SUM(COUNT(jp.job_id)) OVER (),
        2
    )                                           AS pourcentage,
    ROUND(AVG(NULLIF(jp.med_salary, 0)), 0)     AS salaire_median
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id = TRY_TO_NUMBER(c.company_id)
GROUP BY taille_entreprise
ORDER BY nb_offres DESC;


-- ANALYSE 4 : Repartition par secteur d activite
SELECT
    COALESCE(NULLIF(TRIM(ci.industry_id), ''), 'Secteur inconnu') AS secteur,
    COUNT(DISTINCT jp.job_id)               AS nb_offres,
    COUNT(DISTINCT c.company_name)          AS nb_entreprises,
    ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS salaire_median_moyen
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id = TRY_TO_NUMBER(c.company_id)
LEFT JOIN LINKEDIN.SILVER.COMPANY_INDUSTRIES ci
    ON c.company_id = ci.company_id
GROUP BY secteur
ORDER BY nb_offres DESC
LIMIT 25;


-- ANALYSE 5 : Repartition par type d emploi
SELECT
    COALESCE(
        NULLIF(TRIM(formatted_work_type), ''),
        'Non specifie'
    )                                               AS type_emploi,
    COUNT(*)                                        AS nb_offres,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    )                                               AS pourcentage,
    ROUND(AVG(NULLIF(med_salary, 0)), 0)            AS salaire_median,
    ROUND(AVG(NULLIF(views, 0)), 0)                 AS vues_moyennes,
    ROUND(AVG(NULLIF(applies, 0)), 0)               AS candidatures_moyennes,
    SUM(IFF(remote_allowed = TRUE, 1, 0))           AS nb_remote
FROM LINKEDIN.SILVER.JOB_POSTINGS
GROUP BY type_emploi
ORDER BY nb_offres DESC;
