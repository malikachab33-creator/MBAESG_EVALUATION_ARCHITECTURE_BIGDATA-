# MBAESG_EVALUATION_ARCHITECTURE_BIGDATA-


# Projet LinkedIn — Analyse du marché de l'emploi avec Snowflake & Streamlit

## Description

Ce projet analyse un dataset d'offres d'emploi LinkedIn en utilisant une architecture **Medallion** (Bronze / Silver / Gold) sur Snowflake, avec des visualisations interactives via **Streamlit in Snowflake**.

---

## Architecture

```
S3 (snowflake-lab-bucket)
        │
        ▼
   BRONZE (données brutes)
   ├── JOB_POSTINGS     (CSV)
   ├── COMPANIES        (JSON → ARRAY)
   ├── JOB_SKILLS       (CSV)
   ├── BENEFITS         (CSV)
   ├── EMPLOYEE_COUNTS  (CSV)
   ├── JOB_INDUSTRIES   (JSON → ARRAY)
   ├── COMPANY_SPECIALITIES (JSON → ARRAY)
   └── COMPANY_INDUSTRIES   (JSON → ARRAY)
        │
        ▼
   SILVER (données nettoyées et typées)
   ├── JOB_POSTINGS     (timestamps, floats, booléens, company_id extrait)
   ├── COMPANIES        (FLATTEN + cast NUMBER::STRING)
   ├── JOB_SKILLS
   ├── BENEFITS
   ├── EMPLOYEE_COUNTS
   ├── JOB_INDUSTRIES   (FLATTEN)
   ├── COMPANY_SPECIALITIES (FLATTEN)
   └── COMPANY_INDUSTRIES   (FLATTEN + cast NUMBER::STRING)
        │
        ▼
   GOLD (tables analytiques)
   ├── DIM_JOBS         (vue)
   ├── DIM_COMPANIES    (vue)
   ├── FACT_JOBS        (table avec job_score)
   ├── TOP_SKILLS_BY_INDUSTRY
   └── FACT_BENEFITS
```

---

## Fichiers du projet

```
projet-linkedin-snowflake/
├── sql/
│   └── linkedin_sql_final_v2.sql    ← SQL complet Bronze → Silver → Gold
├── streamlit/
│   └── streamlit_linkedin_final_v3.py  ← Les 5 analyses Streamlit
└── README.md
```

---

## Commandes SQL utilisées — avec explications

### 1. Initialisation

```sql
CREATE DATABASE IF NOT EXISTS LINKEDIN;
USE DATABASE LINKEDIN;
CREATE OR REPLACE SCHEMA LINKEDIN.BRONZE;
CREATE OR REPLACE SCHEMA LINKEDIN.SILVER;
CREATE OR REPLACE SCHEMA LINKEDIN.GOLD;
```

**Explication :** Création de la base et des 3 schémas correspondant aux 3 couches de l'architecture Medallion.

```sql
CREATE OR REPLACE STAGE LINKEDIN_STAGE
    URL = 's3://snowflake-lab-bucket/';

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '', 'N/A')
    EMPTY_FIELD_AS_NULL = TRUE;
```

**Explication :** Le stage pointe vers le bucket S3 public. `FIELD_OPTIONALLY_ENCLOSED_BY` gère les champs entre guillemets. `NULL_IF` convertit les chaînes vides et 'NULL' en vraies valeurs NULL.

---

### 2. Couche Bronze — Ingestion brute

#### Fichiers CSV

```sql
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.JOB_POSTINGS (
    job_id STRING, company_name STRING, title STRING, ...
);

COPY INTO LINKEDIN.BRONZE.JOB_POSTINGS
FROM @LINKEDIN_STAGE/job_postings.csv
FILE_FORMAT = CSV_FORMAT;
```

**Explication :** Toutes les colonnes sont en STRING pour éviter les erreurs de type au chargement. Le typage se fait en Silver avec `TRY_CAST`.

#### Fichiers JSON (ARRAY)

```sql
CREATE OR REPLACE TABLE LINKEDIN.BRONZE.COMPANIES (DATA VARIANT);

COPY INTO LINKEDIN.BRONZE.COMPANIES
FROM @LINKEDIN_STAGE/companies.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;
```

**Explication :** `STRIP_OUTER_ARRAY = TRUE` est essentiel — le fichier JSON est un tableau `[{}, {}, ...]`. Sans ce paramètre, tout le tableau est chargé en une seule ligne VARIANT (IS_ARRAY = TRUE) et le parsing est impossible. Avec ce paramètre, chaque objet devient une ligne (IS_OBJECT = TRUE). `FORCE = TRUE` force le rechargement même si le fichier a déjà été chargé.

---

### 3. Couche Silver — Nettoyage et typage

#### JOB_POSTINGS

```sql
CREATE OR REPLACE TABLE LINKEDIN.SILVER.JOB_POSTINGS AS
SELECT
    TRIM(job_id)                                            AS job_id,
    TRY_TO_NUMBER(TRIM(company_name))                       AS company_id,
    TRY_CAST(max_salary AS FLOAT)                           AS max_salary,
    TO_TIMESTAMP(TRY_CAST(original_listed_time AS NUMBER) / 1000)
                                                            AS original_listed_time,
    IFF(UPPER(TRIM(remote_allowed)) = 'TRUE', TRUE, FALSE)  AS remote_allowed,
    CASE
        WHEN TRY_CAST(max_salary AS FLOAT) IS NULL  THEN 'unknown'
        WHEN TRY_CAST(max_salary AS FLOAT) < 40000  THEN 'low'
        WHEN TRY_CAST(max_salary AS FLOAT) <= 90000 THEN 'medium'
        ELSE 'high'
    END AS salary_range,
    ARRAY_SIZE(SPLIT(skills_desc, ','))                     AS num_skills
FROM LINKEDIN.BRONZE.JOB_POSTINGS
WHERE TRIM(job_id) IS NOT NULL AND TRIM(job_id) != '';
```

**Explication :**
- `TRY_TO_NUMBER(company_name)` : la colonne `company_name` du CSV contient en réalité un company_id numérique (ex: `54844.0`). On le convertit proprement.
- `TO_TIMESTAMP(... / 1000)` : les timestamps sont en millisecondes (epoch ms), on divise par 1000 pour obtenir des secondes.
- `IFF(UPPER(...) = 'TRUE', ...)` : les booléens sont stockés comme chaînes, `UPPER()` gère toutes les variantes de casse.
- `TRY_CAST` / `TRY_TO_NUMBER` : ne lève pas d'erreur en cas de valeur non convertible, retourne NULL.

#### COMPANIES (JSON ARRAY)

```sql
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANIES AS
SELECT
    DATA:company_id::NUMBER::STRING     AS company_id,
    DATA:name::STRING                   AS company_name,
    DATA:company_size::NUMBER::STRING   AS company_size,
    ...
FROM LINKEDIN.BRONZE.COMPANIES
WHERE IS_OBJECT(DATA)
  AND DATA:company_id IS NOT NULL;
```

**Explication :** `DATA:company_id::NUMBER::STRING` — le JSON stocke `company_id` comme nombre entier (`1009`, sans guillemets). Il faut d'abord caster en NUMBER pour lire la valeur, puis en STRING pour la jointure avec `JOB_POSTINGS.company_id`.

#### COMPANY_INDUSTRIES (JSON imbriqué dans ARRAY)

```sql
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANY_INDUSTRIES AS
SELECT
    f.value:company_id::NUMBER::STRING  AS company_id,
    f.value:industry::STRING            AS industry_id
FROM LINKEDIN.BRONZE.COMPANY_INDUSTRIES,
LATERAL FLATTEN(input => DATA) f
WHERE f.value:company_id IS NOT NULL;
```

**Explication :** `LATERAL FLATTEN` déroulète un tableau JSON en lignes. Nécessaire quand le fichier JSON est un tableau d'objets chargé en une seule ligne VARIANT.

---

### 4. Couche Gold — Analyses

#### FACT_JOBS avec job_score

```sql
CREATE OR REPLACE TABLE LINKEDIN.GOLD.FACT_JOBS AS
SELECT
    jp.*,
    c.company_name,
    c.company_size,
    (
        COALESCE(jp.max_salary, 0) * 0.4
        + COALESCE(jp.views, 0)    * 0.3
        + COALESCE(jp.applies, 0)  * 0.2
        + jp.num_skills * 50
        + IFF(jp.remote_allowed, 1000, 0)
    ) AS job_score
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id::STRING = c.company_id;
```

**Explication :** Score composite pondéré combinant salaire (40%), vues (30%), candidatures (20%), compétences et télétravail. `COALESCE` remplace les NULL par 0 pour éviter que le score soit NULL si une valeur manque.

---

### 5. Requêtes analytiques

#### Analyse 1 — Top 10 postes par industrie

```sql
WITH ranked AS (
    SELECT
        ji.industry_id,
        jp.title,
        COUNT(*) AS nb_offres,
        ROW_NUMBER() OVER (
            PARTITION BY ji.industry_id
            ORDER BY COUNT(*) DESC
        ) AS rn
    FROM LINKEDIN.SILVER.JOB_POSTINGS jp
    JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji ON jp.job_id = ji.job_id
    WHERE jp.title IS NOT NULL AND jp.title != ''
    GROUP BY ji.industry_id, jp.title
)
SELECT industry_id, title, nb_offres
FROM ranked WHERE rn <= 10
ORDER BY industry_id, nb_offres DESC;
```

**Explication :** `ROW_NUMBER() OVER (PARTITION BY industry_id)` crée un rang indépendant par industrie. `WHERE rn <= 10` filtre le top 10 de chaque industrie. La CTE (WITH) sépare le calcul du filtrage pour plus de lisibilité.

#### Analyse 2 — Salaires par industrie

```sql
WITH salaires AS (
    SELECT
        ji.industry_id, jp.title,
        ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS avg_med_salary,
        ROW_NUMBER() OVER (
            PARTITION BY ji.industry_id
            ORDER BY AVG(NULLIF(jp.med_salary, 0)) DESC NULLS LAST
        ) AS rn
    ...
)
```

**Explication :** `NULLIF(med_salary, 0)` exclut les valeurs à 0 de la moyenne (sinon elles biaiseraient le calcul). `NULLS LAST` place les industries sans salaire en fin de classement.

#### Analyse 3 — Taille d'entreprise

```sql
SELECT
    CASE c.company_size
        WHEN '1' THEN '1 - Individuel'
        WHEN '7' THEN '7 - 1K a 5K emp.'
        ...
        ELSE 'Non renseigne'
    END AS taille_entreprise,
    COUNT(jp.job_id) AS nb_offres,
    ROUND(COUNT(jp.job_id) * 100.0 / SUM(COUNT(jp.job_id)) OVER (), 2) AS pourcentage
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c
    ON jp.company_id::STRING = c.company_id
GROUP BY taille_entreprise;
```

**Explication :** `SUM(COUNT(*)) OVER ()` est une fonction de fenêtre sans partition — elle calcule le total global pour obtenir le pourcentage en une seule requête. La jointure `jp.company_id::STRING = c.company_id` est la clé : `company_id` dans `JOB_POSTINGS` est un NUMBER, dans `COMPANIES` c'est un STRING issu du cast `::NUMBER::STRING`.

#### Analyse 4 — Secteur d'activité

```sql
SELECT
    COALESCE(NULLIF(TRIM(ci.industry_id), ''), 'Secteur inconnu') AS secteur,
    COUNT(DISTINCT jp.job_id) AS nb_offres
FROM LINKEDIN.SILVER.JOB_POSTINGS jp
LEFT JOIN LINKEDIN.SILVER.COMPANIES c ON jp.company_id::STRING = c.company_id
LEFT JOIN LINKEDIN.SILVER.COMPANY_INDUSTRIES ci ON c.company_id = ci.company_id
GROUP BY secteur ORDER BY nb_offres DESC LIMIT 25;
```

**Explication :** Double `LEFT JOIN` pour traverser JOB_POSTINGS → COMPANIES → COMPANY_INDUSTRIES. `COALESCE(NULLIF(TRIM(...), ''), 'Secteur inconnu')` gère les chaînes vides et NULL en une seule expression. `COUNT(DISTINCT)` évite le comptage en double.

#### Analyse 5 — Type d'emploi

```sql
SELECT
    COALESCE(NULLIF(TRIM(formatted_work_type), ''), 'Non specifie') AS type_emploi,
    COUNT(*) AS nb_offres,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pourcentage
FROM LINKEDIN.SILVER.JOB_POSTINGS
GROUP BY type_emploi ORDER BY nb_offres DESC;
```

**Explication :** Même pattern que l'analyse 3 pour le pourcentage. Pas de jointure nécessaire car `formatted_work_type` est directement dans `JOB_POSTINGS`.

---

## Problèmes rencontrés et solutions apportées

### Problème 1 — SILVER.COMPANIES vide (0 lignes)

**Cause :** Le fichier `companies.json` est un tableau JSON `[{}, {}]`. Sans `STRIP_OUTER_ARRAY = TRUE`, Snowflake charge tout le tableau en une seule ligne VARIANT avec `IS_ARRAY = TRUE`. Le filtre `WHERE IS_OBJECT(DATA)` retournait donc 0 résultats.

**Solution :**
```sql
COPY INTO LINKEDIN.BRONZE.COMPANIES
FROM @LINKEDIN_STAGE/companies.json
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
FORCE = TRUE;
```
`STRIP_OUTER_ARRAY = TRUE` découpe le tableau en autant de lignes que d'objets. `FORCE = TRUE` force le rechargement si le fichier avait déjà été chargé.

---

### Problème 2 — company_id ne matchait pas (nb_match = 0)

**Cause :** Dans le JSON, `company_id` est un NUMBER entier (`1009`, sans guillemets). Le cast `DATA:company_id::STRING` produisait parfois des formats différents. De plus, `company_name` dans `JOB_POSTINGS` contenait en réalité le `company_id` numérique (ex: `54844.0`).

**Solution :**
```sql
-- Dans SILVER.COMPANIES :
DATA:company_id::NUMBER::STRING AS company_id  -- caster NUMBER puis STRING

-- Dans SILVER.JOB_POSTINGS :
TRY_TO_NUMBER(TRIM(company_name)) AS company_id  -- extraire l'ID numérique

-- Jointure :
ON jp.company_id::STRING = c.company_id
```

---

### Problème 3 — COMPANY_INDUSTRIES vide après reconstruction

**Cause :** Le fichier `company_industries.json` est aussi un tableau JSON mais chargé différemment — il nécessitait `LATERAL FLATTEN` car chaque ligne Bronze contenait le tableau entier.

**Solution :**
```sql
CREATE OR REPLACE TABLE LINKEDIN.SILVER.COMPANY_INDUSTRIES AS
SELECT
    f.value:company_id::NUMBER::STRING AS company_id,
    f.value:industry::STRING           AS industry_id
FROM LINKEDIN.BRONZE.COMPANY_INDUSTRIES,
LATERAL FLATTEN(input => DATA) f
WHERE f.value:company_id IS NOT NULL;
```

---

### Problème 4 — SyntaxError dans Streamlit

**Cause :** Des apostrophes dans les labels Python (`taille d'entreprise`, `1 · Individuel`) à l'intérieur de chaînes délimitées par des apostrophes provoquaient `SyntaxError: unterminated string literal`.

**Solution :** Supprimer tous les apostrophes et caractères spéciaux des labels Python :
```python
# Avant (erreur)
WHEN '1' THEN '1 · Individuel'

# Après (correct)
WHEN '1' THEN '1 - Individuel'
```

---

### Problème 5 — SQL compilation error : invalid identifier 'JP.COMPANY_ID'

**Cause :** La table `SILVER.JOB_POSTINGS` avait été créée sans la colonne `company_id` — l'ancienne version gardait le champ `company_name` tel quel.

**Solution :** Recréer `SILVER.JOB_POSTINGS` en ajoutant explicitement la colonne :
```sql
TRY_TO_NUMBER(TRIM(company_name)) AS company_id
```

---

### Problème 6 — Timestamps illisibles

**Cause :** Les colonnes `listed_time`, `expiry`, `original_listed_time` contiennent des epochs en millisecondes (ex: `1701234567000`).

**Solution :**
```sql
TO_TIMESTAMP(TRY_CAST(listed_time AS NUMBER) / 1000) AS listed_time
```
`TRY_CAST` évite une erreur si la valeur est non numérique, `/1000` convertit ms en secondes.

---

## Code Streamlit — Les 5 analyses

Le code complet se trouve dans `streamlit/streamlit_linkedin_final_v3.py`.

### Structure générale

```python
import streamlit as st
import altair as alt
from snowflake.snowpark.context import get_active_session

session = get_active_session()  # connexion automatique dans Snowflake

tab1, tab2, tab3, tab4, tab5 = st.tabs([...])
```

`get_active_session()` fournit la session Snowflake automatiquement dans l'environnement Streamlit in Snowflake — aucun credential nécessaire.

### Pattern commun à toutes les analyses

```python
@st.cache_data
def load_data():
    df = session.sql("SELECT ...").to_pandas()
    return df if not df.empty else None

df = load_data()
if df is None:
    st.error("Aucune donnee disponible.")
else:
    # visualisation Altair
    chart = alt.Chart(df).mark_bar().encode(...)
    st.altair_chart(chart, use_container_width=True)
```

`@st.cache_data` met en cache les résultats pour éviter de recharger Snowflake à chaque interaction utilisateur.

### Visualisations utilisées

| Analyse | Type de graphique | Librairie |
|---|---|---|
| Top postes / industrie | Bar chart horizontal | Altair |
| Meilleurs salaires | Bar chart + Error bar (fourchette min-max) | Altair |
| Taille entreprise | Donut chart + Bar chart | Altair |
| Secteur d'activité | Bar chart horizontal avec couleur = salaire | Altair |
| Type d'emploi | Donut chart + Bar chart dynamique | Altair |

---

## Répartition des tâches

| Tâche | Responsable |
|---|---|
| Architecture Bronze / Silver | ACHAB Malik |
| Couche Gold et requêtes analytiques | NZONDA NDE Bosco Junior |
| Analyse 1 et 4 (Streamlit) | NZONDA NDE Bosco Junior |
| Analyse 2 et 3 (Streamlit) | ACHAB Malik  |
| Analyse 5 et debug jointures | ACHAB Malik  |
| Documentation README | ACHAB Malik  |

---

## Technologies utilisées

- **Snowflake** — Data warehouse, SQL, Streamlit in Snowflake
- **Python** — Streamlit, Pandas, Altair
- **AWS S3** — Stockage des fichiers sources
- **Architecture Medallion** — Bronze / Silver / Gold
