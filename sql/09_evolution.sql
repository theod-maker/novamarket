\echo ''
\echo '== E1. Couverture des periodes : jours couverts par mois'
\echo '   Grain de sortie : une ligne par mois de commande, tous statuts.'
SELECT
    DATE_TRUNC('month', ordered_on)::date AS order_month,
    MIN(ordered_on) AS first_day,
    MAX(ordered_on) AS last_day,
    COUNT(DISTINCT ordered_on) AS days_with_orders,
    (DATE_TRUNC('month', ordered_on) + INTERVAL '1 month' - INTERVAL '1 day')::date
        - DATE_TRUNC('month', ordered_on)::date + 1 AS days_in_month,
    COUNT(*) AS orders
FROM core.orders
GROUP BY DATE_TRUNC('month', ordered_on)
ORDER BY order_month;

\echo ''
\echo '== E2. Evolution mensuelle du chiffre d affaires avec LAG et LEAD'
\echo '   Grain de sortie : une ligne par mois. Perimetre : status = completed.'
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.ordered_on)::date AS order_month,
        COUNT(DISTINCT o.ordered_on) AS days_with_orders,
        COUNT(DISTINCT o.order_id) AS completed_orders,
        SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.orders AS o
    JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY DATE_TRUNC('month', o.ordered_on)
)
SELECT
    order_month,
    days_with_orders,
    completed_orders,
    ROUND(revenue_cents / 100.0, 2) AS revenue_eur,
    ROUND(LAG(revenue_cents) OVER (ORDER BY order_month) / 100.0, 2) AS previous_month_eur,
    ROUND(LEAD(revenue_cents) OVER (ORDER BY order_month) / 100.0, 2) AS next_month_eur,
    ROUND(100.0 * (revenue_cents - LAG(revenue_cents) OVER (ORDER BY order_month))
        / LAG(revenue_cents) OVER (ORDER BY order_month), 1) AS change_pct,
    ROUND(revenue_cents / 100.0 / days_with_orders, 2) AS revenue_per_day_eur,
    ROUND(100.0 * (revenue_cents * 1.0 / days_with_orders
        - LAG(revenue_cents * 1.0 / days_with_orders) OVER (ORDER BY order_month))
        / LAG(revenue_cents * 1.0 / days_with_orders) OVER (ORDER BY order_month), 1)
        AS change_per_day_pct
FROM monthly
ORDER BY order_month;

\echo ''
\echo '== E3. Evolution hebdomadaire (semaines du lundi au dimanche)'
\echo '   Grain de sortie : une ligne par semaine. Perimetre : status = completed.'
WITH weekly AS (
    SELECT
        DATE_TRUNC('week', o.ordered_on)::date AS week_start,
        COUNT(DISTINCT o.ordered_on) AS days_with_orders,
        SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.orders AS o
    JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY DATE_TRUNC('week', o.ordered_on)
)
SELECT
    week_start,
    days_with_orders,
    ROUND(revenue_cents / 100.0, 2) AS revenue_eur,
    ROUND((revenue_cents - LAG(revenue_cents) OVER (ORDER BY week_start)) / 100.0, 2)
        AS change_vs_previous_week_eur,
    week_start - LAG(week_start) OVER (ORDER BY week_start) AS days_since_previous_week,
    CASE WHEN days_with_orders < 7 THEN 'semaine incomplete' ELSE 'complete' END AS coverage
FROM weekly
ORDER BY week_start;

\echo ''
\echo '== E4. Coherence des dates ventes / catalogue sur le chiffre d affaires mensuel'
SELECT
    DATE_TRUNC('month', o.ordered_on)::date AS order_month,
    ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS revenue_eur,
    ROUND(SUM(i.quantity * i.unit_price_cents)
        FILTER (WHERE o.ordered_on < p.first_listed_on) / 100.0, 2)
        AS revenue_before_listing_date_eur
FROM core.orders AS o
JOIN core.order_items AS i ON i.order_id = o.order_id
JOIN core.products AS p ON p.product_id = i.product_id
WHERE o.status = 'completed'
GROUP BY DATE_TRUNC('month', o.ordered_on)
ORDER BY order_month;
