WITH params AS (
  SELECT
    8::bigint AS target_user_id,
    '%Capital Solutions%'::text AS appointment_source_pattern
),

/* 1) Fixed dummy/test lead_id blacklist */
fixed_blacklisted_leads AS (
  SELECT unnest(ARRAY[
    1, 16, 40029, 40358, 40734, 40739, 40861, 40955, 40956, 41582, 41828, 42818,
    41207, 41164, 40626, 40298
  ])::bigint AS lead_id
),

/* 2) Manual review: actual_re_lead = false also counts as blacklisted */
manual_lead_review AS (
  SELECT *
  FROM (
    VALUES
      (42471::bigint, false, 'airbnb_short_term_rental'),
      (40240::bigint, false, 'non_real_estate_service')
  ) AS x(lead_id, actual_re_lead, category)
),

/* 3) Phone-based blacklist from prospectos */
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

/* 4) One blacklist decision per lead (time-independent) */
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

/* 5) Conversation events (any non-empty message), with timestamp */
conv_events AS (
  SELECT
    cm.lead_id,
    cm.mensaje_enviado_el AS ts,
    'lead:' || cm.lead_id::text AS record_key
  FROM public.chat_messages cm
  JOIN params p ON p.target_user_id = cm.user_id
  WHERE cm.lead_id IS NOT NULL
    AND NULLIF(TRIM(cm.content), '') IS NOT NULL
),

/* 6) Bot message events, with timestamp */
bot_events AS (
  SELECT
    cm.lead_id,
    cm.mensaje_enviado_el AS ts,
    'lead:' || cm.lead_id::text AS record_key
  FROM public.chat_messages cm
  JOIN params p ON p.target_user_id = cm.user_id
  WHERE cm.lead_id IS NOT NULL
    AND NULLIF(TRIM(cm.content), '') IS NOT NULL
    AND LOWER(TRIM(cm.tipo_emisor)) = 'bot'
),

/* 7) Project-mention events, with timestamp */
proj_events AS (
  SELECT
    cm.lead_id,
    cm.mensaje_enviado_el AS ts,
    'lead:' || cm.lead_id::text AS record_key
  FROM public.chat_messages cm
  JOIN params p ON p.target_user_id = cm.user_id
  WHERE cm.lead_id IS NOT NULL
    AND NULLIF(TRIM(cm.content), '') IS NOT NULL
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
),

/* 8) Project-mention events that fall in a month where the lead also had a
      bot message (same-month rule preserved; ts kept for window filtering) */
bot_and_proj_events AS (
  SELECT pe.lead_id, pe.ts, pe.record_key
  FROM proj_events pe
  WHERE EXISTS (
    SELECT 1 FROM bot_events be
    WHERE be.lead_id = pe.lead_id
      AND date_trunc('month', be.ts) = date_trunc('month', pe.ts)
  )
),

/* 9) Bot-booked appointment events, with created_at timestamp */
appt_events AS (
  SELECT
    a.lead_id,
    a.created_at AS ts,
    'appointment:' || a.id::text AS record_key
  FROM public.appointments a
  JOIN params p ON true
  WHERE a.lead_id IS NOT NULL
    AND a.source_appointment ILIKE p.appointment_source_pattern
),

/* 10) Every metric into one normalized event table (sort_order, metric, lead_id, ts, record_key) */
metrics AS (
  SELECT 1 AS sort_order, 'Leads with Convos' AS metric, lead_id, ts, record_key FROM conv_events
  UNION ALL
  SELECT 2, 'Leads with Bot Convos', lead_id, ts, record_key FROM bot_events
  UNION ALL
  SELECT 3, 'Leads with Project Mention', lead_id, ts, record_key FROM proj_events
  UNION ALL
  SELECT 4, 'Leads with Bot Convos & Project Mention', lead_id, ts, record_key FROM bot_and_proj_events
  UNION ALL
  SELECT 5, 'Appointments Booked by Bot', lead_id, ts, record_key FROM appt_events
  UNION ALL
  SELECT 6, 'Leads with Meetings Booked by Bot', lead_id, ts, 'lead:' || lead_id::text FROM appt_events
),

/* 11) Attach blacklist flag, keep only non-blacklisted events */
clean AS (
  SELECT
    m.sort_order,
    m.metric,
    m.ts,
    m.record_key
  FROM metrics m
  LEFT JOIN lead_blacklist lb ON lb.lead_id = m.lead_id
  WHERE COALESCE(lb.is_blacklisted, false) = false
)

/* 12) Pivot: row per metric, a column per month + last 30 days + lifetime. */
SELECT
  metric,
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-01-01') AS "2026-01",
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-02-01') AS "2026-02",
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-03-01') AS "2026-03",
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-04-01') AS "2026-04",
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-05-01') AS "2026-05",
  COUNT(DISTINCT record_key) FILTER (WHERE date_trunc('month', ts) = DATE '2026-06-01') AS "2026-06",
  COUNT(DISTINCT record_key) FILTER (WHERE ts >= now() - INTERVAL '30 days')            AS "last_30d",
  COUNT(DISTINCT record_key)                                                            AS "lifetime"
FROM clean
GROUP BY sort_order, metric
ORDER BY sort_order;
