/* ============================================================
   CTWA cohort funnel
   - Population = leads whose chat originated from a CTWA ad
     (plataforma_origen ILIKE '%CTWA%'). This is the source of truth.
   - Same stages as the metrics query, but scoped to that cohort.
   - Output: count, blacklist split, % of CTWA total, % of previous stage.
   ============================================================ */

WITH params AS (
  SELECT
    8::bigint AS target_user_id,
    '%Capital Solutions%'::text AS appointment_source_pattern
),

/* ---- Blacklist (same rules as the metrics query) ---- */
fixed_blacklisted_leads AS (
  SELECT unnest(ARRAY[
    1, 16, 40029, 40358, 40734, 40739, 40861, 40955, 40956, 41582, 41828, 42818,
    41207, 41164, 40626, 40298
  ])::bigint AS lead_id
),
manual_lead_review AS (
  SELECT *
  FROM (
    VALUES
      (42471::bigint, false, 'airbnb_short_term_rental'),
      (40240::bigint, false, 'non_real_estate_service')
  ) AS x(lead_id, actual_re_lead, category)
),
prospecto_flags AS (
  SELECT
    p.lead_id,
    BOOL_OR(
      p.prospecto_numero_whatsapp::text IN (
        '59164700143','59160028633','59176635354',
        '59177355237','59169393294','59178586768'
      )
      OR p.prospecto_numero_whatsapp::text LIKE '33%'
      OR p.prospecto_numero_whatsapp::text LIKE '39%'
    ) AS phone_blacklisted
  FROM public.prospectos p
  WHERE p.lead_id IS NOT NULL
  GROUP BY p.lead_id
),
lead_blacklist AS (
  SELECT
    all_leads.lead_id,
    (
      fbl.lead_id IS NOT NULL
      OR COALESCE(pf.phone_blacklisted, false)
      OR COALESCE(mlr.actual_re_lead = false, false)
    ) AS is_blacklisted
  FROM (
    SELECT DISTINCT cm.lead_id
    FROM public.chat_messages cm
    JOIN params p ON p.target_user_id = cm.user_id
    WHERE cm.lead_id IS NOT NULL
    UNION
    SELECT DISTINCT a.lead_id
    FROM public.appointments a
    WHERE a.lead_id IS NOT NULL
  ) all_leads
  LEFT JOIN fixed_blacklisted_leads fbl ON fbl.lead_id = all_leads.lead_id
  LEFT JOIN prospecto_flags pf ON pf.lead_id = all_leads.lead_id
  LEFT JOIN manual_lead_review mlr ON mlr.lead_id = all_leads.lead_id
),

/* ---- The CTWA cohort (source of truth) ---- */
ctwa_leads AS (
  SELECT DISTINCT cm.lead_id
  FROM public.chat_messages cm
  WHERE cm.plataforma_origen ILIKE '%CTWA%'
    AND cm.lead_id IS NOT NULL
),

/* ---- Per-lead stage flags, computed only over CTWA leads ---- */
msg_flags AS (
  SELECT
    cm.lead_id,
    BOOL_OR(NULLIF(TRIM(cm.content), '') IS NOT NULL) AS has_convo,
    BOOL_OR(
      NULLIF(TRIM(cm.content), '') IS NOT NULL
      AND LOWER(TRIM(cm.tipo_emisor)) = 'bot'
    ) AS has_bot,
    BOOL_OR(
      NULLIF(TRIM(cm.content), '') IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.listing_projects lp
        WHERE lp.user_id = p.target_user_id
          AND lp.record_status = 1
          AND lp.record_deleted_at IS NULL
          AND NULLIF(TRIM(lp.name), '') IS NOT NULL
          AND (
            cm.content ILIKE '%' || lp.name || '%'
            OR word_similarity(lp.name::text, cm.content::text) >= 0.6
          )
      )
    ) AS has_proj
  FROM public.chat_messages cm
  JOIN ctwa_leads cl ON cl.lead_id = cm.lead_id
  JOIN params p ON p.target_user_id = cm.user_id
  GROUP BY cm.lead_id
),

/* Leads with a bot-booked appointment */
appt_flags AS (
  SELECT DISTINCT a.lead_id
  FROM public.appointments a
  JOIN params p ON true
  WHERE a.lead_id IS NOT NULL
    AND a.source_appointment ILIKE p.appointment_source_pattern
),

/* One row per CTWA lead with every stage flag + blacklist flag */
funnel_leads AS (
  SELECT
    cl.lead_id,
    COALESCE(lb.is_blacklisted, false)                              AS is_blacklisted,
    COALESCE(mf.has_convo, false)                                   AS has_convo,
    COALESCE(mf.has_bot,   false)                                   AS has_bot,
    COALESCE(mf.has_proj,  false)                                   AS has_proj,
    (COALESCE(mf.has_bot, false) AND COALESCE(mf.has_proj, false))  AS has_bot_proj,
    (af.lead_id IS NOT NULL)                                        AS has_appt
  FROM ctwa_leads cl
  LEFT JOIN msg_flags mf      ON mf.lead_id = cl.lead_id
  LEFT JOIN appt_flags af     ON af.lead_id = cl.lead_id
  LEFT JOIN lead_blacklist lb ON lb.lead_id = cl.lead_id
),

/* Count each stage: raw / blacklisted / clean */
stage_counts AS (
  SELECT 1 AS sort_order, 'CTWA Leads (source of truth)' AS stage,
         COUNT(*) AS raw,
         COUNT(*) FILTER (WHERE is_blacklisted)     AS blacklisted,
         COUNT(*) FILTER (WHERE NOT is_blacklisted) AS clean
  FROM funnel_leads
  UNION ALL
  SELECT 2, 'With Conversation',
         COUNT(*) FILTER (WHERE has_convo),
         COUNT(*) FILTER (WHERE has_convo AND is_blacklisted),
         COUNT(*) FILTER (WHERE has_convo AND NOT is_blacklisted)
  FROM funnel_leads
  UNION ALL
  SELECT 3, 'Bot Engaged',
         COUNT(*) FILTER (WHERE has_bot),
         COUNT(*) FILTER (WHERE has_bot AND is_blacklisted),
         COUNT(*) FILTER (WHERE has_bot AND NOT is_blacklisted)
  FROM funnel_leads
  UNION ALL
  SELECT 4, 'Project Mention',
         COUNT(*) FILTER (WHERE has_proj),
         COUNT(*) FILTER (WHERE has_proj AND is_blacklisted),
         COUNT(*) FILTER (WHERE has_proj AND NOT is_blacklisted)
  FROM funnel_leads
  UNION ALL
  SELECT 5, 'Bot + Project Mention',
         COUNT(*) FILTER (WHERE has_bot_proj),
         COUNT(*) FILTER (WHERE has_bot_proj AND is_blacklisted),
         COUNT(*) FILTER (WHERE has_bot_proj AND NOT is_blacklisted)
  FROM funnel_leads
  UNION ALL
  SELECT 6, 'Appointment Booked',
         COUNT(*) FILTER (WHERE has_appt),
         COUNT(*) FILTER (WHERE has_appt AND is_blacklisted),
         COUNT(*) FILTER (WHERE has_appt AND NOT is_blacklisted)
  FROM funnel_leads
)

SELECT
  stage AS "Stage",
  clean AS "Leads",
  blacklisted AS "Blacklisted",
  ROUND(
    100.0 * clean
    / NULLIF(FIRST_VALUE(clean) OVER (ORDER BY sort_order), 0), 1
  ) AS "% of CTWA",
  ROUND(
    100.0 * clean
    / NULLIF(LAG(clean) OVER (ORDER BY sort_order), 0), 1
  ) AS "% of Prev"
FROM stage_counts
ORDER BY sort_order;

/* ------------------------------------------------------------
   Observed period (run alongside, same as your CTWA period query)
   ------------------------------------------------------------ */
WITH ctwa_messages AS (
  SELECT
    lead_id,
    COALESCE(mensaje_enviado_el, registro_creado_el) AS msg_at
  FROM public.chat_messages
  WHERE plataforma_origen ILIKE '%CTWA%'
    AND lead_id IS NOT NULL
    AND COALESCE(mensaje_enviado_el, registro_creado_el) IS NOT NULL
),
elapsed AS (
  SELECT
    COUNT(DISTINCT lead_id) AS ctwa_leads,
    EXTRACT(EPOCH FROM (NOW() - MIN(msg_at))) AS seconds_passed
  FROM ctwa_messages
)
SELECT
  'Observed Period' AS "Metric",
  ctwa_leads        AS "CTWA",
  FLOOR(seconds_passed / 86400)::int            AS "Day",
  FLOOR(MOD(seconds_passed, 86400) / 3600)::int AS "Hours",
  ROUND(ctwa_leads / (seconds_passed / 86400.0), 1) AS "Leads/Day"
FROM elapsed;
