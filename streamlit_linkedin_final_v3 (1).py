import streamlit as st
import altair as alt
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.title("Analyse du marche de l emploi LinkedIn")
st.markdown("---")

tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "Top Postes / Industrie",
    "Meilleurs Salaires",
    "Taille Entreprise",
    "Secteur Activite",
    "Type Emploi"
])


# ============================================================
# ANALYSE 1 - Top 10 postes les plus publies par industrie
# ============================================================
with tab1:
    st.header("Top 10 des titres de postes les plus publies par industrie")

    @st.cache_data
    def load_top_postes():
        queries = [
            """
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
                JOIN LINKEDIN.SILVER.JOB_INDUSTRIES ji
                    ON jp.job_id = ji.job_id
                WHERE jp.title IS NOT NULL AND jp.title != ''
                GROUP BY ji.industry_id, jp.title
            )
            SELECT industry_id, title, nb_offres
            FROM ranked
            WHERE rn <= 10
            ORDER BY industry_id, nb_offres DESC
            """,
            """
            SELECT
                'Toutes industries' AS industry_id,
                title,
                COUNT(*) AS nb_offres
            FROM LINKEDIN.SILVER.JOB_POSTINGS
            WHERE title IS NOT NULL AND title != ''
            GROUP BY title
            ORDER BY nb_offres DESC
            LIMIT 10
            """
        ]
        for q in queries:
            try:
                df = session.sql(q).to_pandas()
                if not df.empty:
                    return df
            except Exception:
                continue
        return None

    df1 = load_top_postes()

    if df1 is None or df1.empty:
        st.error("Aucune donnee disponible.")
    else:
        industries = sorted(df1["INDUSTRY_ID"].dropna().unique().tolist())
        col_a, col_b = st.columns([2, 3])
        with col_a:
            industry_sel = st.selectbox("Choisir une industrie", industries, key="t1")
        df1_f = df1[df1["INDUSTRY_ID"] == industry_sel].head(10)
        with col_b:
            st.metric("Titres distincts", len(df1_f))
            st.metric("Total offres", f"{int(df1_f['NB_OFFRES'].sum()):,}")

        chart = (
            alt.Chart(df1_f)
            .mark_bar(color="#4A90D9", cornerRadiusTopRight=4, cornerRadiusBottomRight=4)
            .encode(
                x=alt.X("NB_OFFRES:Q", title="Nombre d offres"),
                y=alt.Y("TITLE:N", sort="-x", title="Titre du poste"),
                tooltip=[
                    alt.Tooltip("TITLE:N", title="Poste"),
                    alt.Tooltip("NB_OFFRES:Q", title="Nb offres", format=",")
                ]
            )
            .properties(title=f"Top 10 postes - Industrie : {industry_sel}", height=380)
        )
        st.altair_chart(chart, use_container_width=True)

        with st.expander("Voir le tableau"):
            st.dataframe(
                df1_f.rename(columns={
                    "INDUSTRY_ID": "Industrie",
                    "TITLE": "Titre",
                    "NB_OFFRES": "Nb offres"
                }),
                use_container_width=True,
                hide_index=True
            )


# ============================================================
# ANALYSE 2 - Top 10 postes les mieux remuneres par industrie
# ============================================================
with tab2:
    st.header("Top 10 des postes les mieux remuneres par industrie")

    @st.cache_data
    def load_salaires():
        queries = [
            """
            WITH salaires AS (
                SELECT
                    ji.industry_id,
                    jp.title,
                    ROUND(AVG(NULLIF(jp.min_salary, 0)), 0) AS avg_min_salary,
                    ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS avg_med_salary,
                    ROUND(AVG(NULLIF(jp.max_salary, 0)), 0) AS avg_max_salary,
                    COUNT(*) AS nb_offres,
                    ROW_NUMBER() OVER (
                        PARTITION BY ji.industry_id
                        ORDER BY AVG(NULLIF(jp.med_salary, 0)) DESC NULLS LAST
                    ) AS rn
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
            ORDER BY industry_id, avg_med_salary DESC
            """,
            """
            SELECT
                'Toutes industries' AS industry_id,
                title,
                ROUND(AVG(NULLIF(min_salary, 0)), 0) AS avg_min_salary,
                ROUND(AVG(NULLIF(med_salary, 0)), 0) AS avg_med_salary,
                ROUND(AVG(NULLIF(max_salary, 0)), 0) AS avg_max_salary,
                COUNT(*) AS nb_offres
            FROM LINKEDIN.SILVER.JOB_POSTINGS
            WHERE med_salary IS NOT NULL AND med_salary > 0
              AND title IS NOT NULL
            GROUP BY title
            ORDER BY avg_med_salary DESC
            LIMIT 10
            """
        ]
        for q in queries:
            try:
                df = session.sql(q).to_pandas()
                if not df.empty:
                    return df
            except Exception:
                continue
        return None

    df2 = load_salaires()

    if df2 is None or df2.empty:
        st.error("Aucune donnee de salaire disponible.")
    else:
        industries2 = sorted(df2["INDUSTRY_ID"].dropna().unique().tolist())
        col_a, col_b = st.columns([2, 3])
        with col_a:
            industry_sel2 = st.selectbox("Choisir une industrie", industries2, key="t2")
        df2_f = df2[df2["INDUSTRY_ID"] == industry_sel2].head(10)
        with col_b:
            st.metric("Salaire median le plus eleve",
                      f"${df2_f['AVG_MED_SALARY'].max():,.0f}")
            st.metric("Salaire median moyen top 10",
                      f"${df2_f['AVG_MED_SALARY'].mean():,.0f}")

        base = alt.Chart(df2_f)
        bars = base.mark_bar(
            color="#2E86AB",
            cornerRadiusTopRight=4,
            cornerRadiusBottomRight=4
        ).encode(
            x=alt.X("AVG_MED_SALARY:Q", title="Salaire median moyen ($)"),
            y=alt.Y("TITLE:N", sort="-x", title=None),
            tooltip=[
                alt.Tooltip("TITLE:N", title="Poste"),
                alt.Tooltip("AVG_MIN_SALARY:Q", title="Min ($)", format=",.0f"),
                alt.Tooltip("AVG_MED_SALARY:Q", title="Median ($)", format=",.0f"),
                alt.Tooltip("AVG_MAX_SALARY:Q", title="Max ($)", format=",.0f"),
                alt.Tooltip("NB_OFFRES:Q", title="Nb offres")
            ]
        )
        erreurs = base.mark_errorbar(color="#888", thickness=2).encode(
            x=alt.X("AVG_MIN_SALARY:Q", title=""),
            x2=alt.X2("AVG_MAX_SALARY:Q"),
            y=alt.Y("TITLE:N", sort="-x")
        )
        st.altair_chart(
            (bars + erreurs).properties(
                title=f"Top 10 salaires - {industry_sel2}",
                height=380
            ),
            use_container_width=True
        )
        st.caption("Les traits representent la fourchette salaire min - max.")

        with st.expander("Voir le tableau"):
            st.dataframe(
                df2_f[["TITLE", "AVG_MIN_SALARY", "AVG_MED_SALARY",
                        "AVG_MAX_SALARY", "NB_OFFRES"]]
                .rename(columns={
                    "TITLE": "Poste",
                    "AVG_MIN_SALARY": "Min ($)",
                    "AVG_MED_SALARY": "Median ($)",
                    "AVG_MAX_SALARY": "Max ($)",
                    "NB_OFFRES": "Nb offres"
                }),
                use_container_width=True,
                hide_index=True
            )


# ============================================================
# ANALYSE 3 - Repartition par taille d entreprise
# Jointure : jp.company_id::STRING = c.company_id
# ============================================================
with tab3:
    st.header("Repartition des offres par taille d entreprise")

    @st.cache_data
    def load_taille():
        query = """
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
                    ELSE 'Non renseigne'
                END AS taille_entreprise,
                COUNT(jp.job_id) AS nb_offres,
                ROUND(
                    COUNT(jp.job_id) * 100.0 / SUM(COUNT(jp.job_id)) OVER (),
                    2
                ) AS pourcentage,
                ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS salaire_median
            FROM LINKEDIN.SILVER.JOB_POSTINGS jp
            LEFT JOIN LINKEDIN.SILVER.COMPANIES c
                ON jp.company_id::STRING = c.company_id
            GROUP BY taille_entreprise
            ORDER BY nb_offres DESC
        """
        try:
            df = session.sql(query).to_pandas()
            return df if not df.empty else None
        except Exception as e:
            st.error(f"Erreur : {e}")
            return None

    df3 = load_taille()

    if df3 is None or df3.empty:
        st.error("Aucune donnee disponible.")
    else:
        c1, c2, c3 = st.columns(3)
        c1.metric("Total offres", f"{df3['NB_OFFRES'].sum():,}")
        c2.metric("Categories", len(df3))
        sal3 = df3[df3["SALAIRE_MEDIAN"].notna() & (df3["SALAIRE_MEDIAN"] > 0)]["SALAIRE_MEDIAN"]
        c3.metric("Salaire median moyen",
                  f"${sal3.mean():,.0f}" if not sal3.empty else "N/A")

        col_g1, col_g2 = st.columns([3, 2])
        with col_g1:
            donut = (
                alt.Chart(df3)
                .mark_arc(innerRadius=80, outerRadius=160)
                .encode(
                    theta=alt.Theta("NB_OFFRES:Q"),
                    color=alt.Color(
                        "TAILLE_ENTREPRISE:N",
                        legend=alt.Legend(title="Taille"),
                        scale=alt.Scale(scheme="tableau10")
                    ),
                    tooltip=[
                        alt.Tooltip("TAILLE_ENTREPRISE:N", title="Taille"),
                        alt.Tooltip("NB_OFFRES:Q", title="Nb offres", format=","),
                        alt.Tooltip("POURCENTAGE:Q", title="%", format=".2f"),
                        alt.Tooltip("SALAIRE_MEDIAN:Q",
                                    title="Salaire median ($)", format=",.0f")
                    ]
                )
                .properties(title="Repartition par taille d entreprise", height=380)
            )
            st.altair_chart(donut, use_container_width=True)

        with col_g2:
            st.markdown("**Detail par categorie**")
            st.dataframe(
                df3[["TAILLE_ENTREPRISE", "NB_OFFRES", "POURCENTAGE"]]
                .rename(columns={
                    "TAILLE_ENTREPRISE": "Taille",
                    "NB_OFFRES": "Offres",
                    "POURCENTAGE": "%"
                }),
                use_container_width=True,
                hide_index=True,
                height=380
            )

        df3_sal = df3[df3["SALAIRE_MEDIAN"].notna() & (df3["SALAIRE_MEDIAN"] > 0)]
        if not df3_sal.empty:
            st.markdown("**Salaire median par taille d entreprise**")
            bar3 = (
                alt.Chart(df3_sal)
                .mark_bar(color="#F4845F", cornerRadiusTopRight=4,
                          cornerRadiusBottomRight=4)
                .encode(
                    x=alt.X("SALAIRE_MEDIAN:Q", title="Salaire median ($)"),
                    y=alt.Y("TAILLE_ENTREPRISE:N", sort="-x", title=None),
                    tooltip=[
                        alt.Tooltip("TAILLE_ENTREPRISE:N", title="Taille"),
                        alt.Tooltip("SALAIRE_MEDIAN:Q",
                                    title="Salaire median ($)", format=",.0f")
                    ]
                )
                .properties(height=300)
            )
            st.altair_chart(bar3, use_container_width=True)


# ============================================================
# ANALYSE 4 - Repartition par secteur d activite
# Jointure : jp.company_id::STRING = c.company_id = ci.company_id
# ============================================================
with tab4:
    st.header("Repartition des offres par secteur d activite")

    @st.cache_data
    def load_secteurs():
        query = """
            SELECT
                COALESCE(NULLIF(TRIM(ci.industry_id), ''), 'Secteur inconnu') AS secteur,
                COUNT(DISTINCT jp.job_id)               AS nb_offres,
                COUNT(DISTINCT c.company_name)          AS nb_entreprises,
                ROUND(AVG(NULLIF(jp.med_salary, 0)), 0) AS salaire_median_moyen
            FROM LINKEDIN.SILVER.JOB_POSTINGS jp
            LEFT JOIN LINKEDIN.SILVER.COMPANIES c
                ON jp.company_id::STRING = c.company_id
            LEFT JOIN LINKEDIN.SILVER.COMPANY_INDUSTRIES ci
                ON c.company_id = ci.company_id
            GROUP BY secteur
            ORDER BY nb_offres DESC
            LIMIT 25
        """
        try:
            df = session.sql(query).to_pandas()
            return df if not df.empty else None
        except Exception as e:
            st.error(f"Erreur : {e}")
            return None

    df4 = load_secteurs()

    if df4 is None or df4.empty:
        st.error("Aucune donnee disponible.")
    else:
        c1, c2, c3 = st.columns(3)
        c1.metric("Total offres", f"{df4['NB_OFFRES'].sum():,}")
        c2.metric("Secteurs identifies", len(df4))
        sal4 = df4[
            df4["SALAIRE_MEDIAN_MOYEN"].notna() &
            (df4["SALAIRE_MEDIAN_MOYEN"] > 0)
        ]["SALAIRE_MEDIAN_MOYEN"]
        c3.metric("Salaire median moyen",
                  f"${sal4.mean():,.0f}" if not sal4.empty else "N/A")

        top_n = st.slider("Afficher les N premiers secteurs", 5, 25, 15, step=1)
        df4_f = df4.head(top_n)

        chart4 = (
            alt.Chart(df4_f)
            .mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4)
            .encode(
                x=alt.X("NB_OFFRES:Q", title="Nombre d offres"),
                y=alt.Y("SECTEUR:N", sort="-x", title=None),
                color=alt.Color(
                    "SALAIRE_MEDIAN_MOYEN:Q",
                    scale=alt.Scale(scheme="blues"),
                    title="Salaire median ($)"
                ),
                tooltip=[
                    alt.Tooltip("SECTEUR:N", title="Secteur"),
                    alt.Tooltip("NB_OFFRES:Q", title="Nb offres", format=","),
                    alt.Tooltip("NB_ENTREPRISES:Q", title="Nb entreprises", format=","),
                    alt.Tooltip("SALAIRE_MEDIAN_MOYEN:Q",
                                title="Salaire median ($)", format=",.0f")
                ]
            )
            .properties(
                title=f"Top {top_n} secteurs par nombre d offres",
                height=max(350, top_n * 28)
            )
        )
        st.altair_chart(chart4, use_container_width=True)
        st.caption("Plus la barre est foncee, plus le salaire median est eleve.")

        with st.expander("Voir le tableau complet"):
            st.dataframe(
                df4_f.rename(columns={
                    "SECTEUR": "Secteur",
                    "NB_OFFRES": "Nb offres",
                    "NB_ENTREPRISES": "Nb entreprises",
                    "SALAIRE_MEDIAN_MOYEN": "Salaire median ($)"
                }),
                use_container_width=True,
                hide_index=True
            )


# ============================================================
# ANALYSE 5 - Repartition par type d emploi
# ============================================================
with tab5:
    st.header("Repartition des offres par type d emploi")

    @st.cache_data
    def load_type_emploi():
        query = """
            SELECT
                COALESCE(
                    NULLIF(TRIM(formatted_work_type), ''),
                    'Non specifie'
                ) AS type_emploi,
                COUNT(*) AS nb_offres,
                ROUND(
                    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
                    2
                ) AS pourcentage,
                ROUND(AVG(NULLIF(med_salary, 0)), 0)   AS salaire_median,
                ROUND(AVG(NULLIF(views, 0)), 0)        AS vues_moyennes,
                ROUND(AVG(NULLIF(applies, 0)), 0)      AS candidatures_moyennes,
                SUM(IFF(remote_allowed = TRUE, 1, 0))  AS nb_remote
            FROM LINKEDIN.SILVER.JOB_POSTINGS
            GROUP BY type_emploi
            ORDER BY nb_offres DESC
        """
        try:
            df = session.sql(query).to_pandas()
            return df if not df.empty else None
        except Exception as e:
            st.error(f"Erreur : {e}")
            return None

    df5 = load_type_emploi()

    if df5 is None or df5.empty:
        st.error("Aucune donnee disponible.")
    else:
        nb_types = min(len(df5), 6)
        cols_m = st.columns(nb_types)
        for i, (_, row) in enumerate(df5.head(nb_types).iterrows()):
            with cols_m[i]:
                st.metric(
                    label=row["TYPE_EMPLOI"],
                    value=f"{int(row['NB_OFFRES']):,}",
                    delta=f"{row['POURCENTAGE']}%"
                )

        st.markdown("---")
        col_g1, col_g2 = st.columns([2, 3])

        with col_g1:
            donut5 = (
                alt.Chart(df5)
                .mark_arc(innerRadius=70, outerRadius=145)
                .encode(
                    theta=alt.Theta("NB_OFFRES:Q"),
                    color=alt.Color(
                        "TYPE_EMPLOI:N",
                        legend=alt.Legend(title="Type d emploi"),
                        scale=alt.Scale(scheme="set2")
                    ),
                    tooltip=[
                        alt.Tooltip("TYPE_EMPLOI:N", title="Type"),
                        alt.Tooltip("NB_OFFRES:Q", title="Nb offres", format=","),
                        alt.Tooltip("POURCENTAGE:Q", title="%", format=".2f")
                    ]
                )
                .properties(title="Repartition par type d emploi", height=340)
            )
            st.altair_chart(donut5, use_container_width=True)

        with col_g2:
            metric_options = {
                "Salaire median ($)": "SALAIRE_MEDIAN",
                "Vues moyennes": "VUES_MOYENNES",
                "Candidatures moyennes": "CANDIDATURES_MOYENNES",
                "Offres remote": "NB_REMOTE"
            }
            metric_label = st.selectbox(
                "Comparer par",
                options=list(metric_options.keys()),
                key="t5_metric"
            )
            metric_col = metric_options[metric_label]
            df5_f = df5[df5[metric_col].notna() & (df5[metric_col] > 0)]

            bar5 = (
                alt.Chart(df5_f)
                .mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4)
                .encode(
                    x=alt.X(f"{metric_col}:Q", title=metric_label),
                    y=alt.Y("TYPE_EMPLOI:N", sort="-x", title=None),
                    color=alt.Color(
                        "TYPE_EMPLOI:N",
                        scale=alt.Scale(scheme="set2"),
                        legend=None
                    ),
                    tooltip=[
                        alt.Tooltip("TYPE_EMPLOI:N", title="Type"),
                        alt.Tooltip(f"{metric_col}:Q",
                                    title=metric_label, format=",.0f")
                    ]
                )
                .properties(
                    title=f"{metric_label} par type d emploi",
                    height=340
                )
            )
            st.altair_chart(bar5, use_container_width=True)

        st.markdown("---")
        st.subheader("Tableau comparatif complet")
        st.dataframe(
            df5.rename(columns={
                "TYPE_EMPLOI": "Type d emploi",
                "NB_OFFRES": "Nb offres",
                "POURCENTAGE": "%",
                "SALAIRE_MEDIAN": "Salaire median ($)",
                "VUES_MOYENNES": "Vues moy.",
                "CANDIDATURES_MOYENNES": "Candidatures moy.",
                "NB_REMOTE": "Nb remote"
            }),
            use_container_width=True,
            hide_index=True
        )

st.markdown("---")
st.caption("Source : LinkedIn Job Postings Dataset - Snowflake LINKEDIN.SILVER - Streamlit in Snowflake")
