/* Funnel for the CTWA observed period: first CTWA message -> now */

WITH params AS (
  SELECT 8::bigint AS target_user_id,
         '%Capital Solutions%'::text AS appointment_source_pattern
),

/* Start of the window = first CTWA message ever */
window_start AS (
  SELECT MIN(COALESCE(cm.mensaje_enviado_el, cm.registro_creado_el)) AS t0
  FROM public.chat_messages cm
  WHERE cm.plataforma_origen ILIKE '%CTWA%'
    AND cm.lead_id IS NOT NULL
),

/* ---- Blacklist (same rules) ---- */
fixed_blacklisted_leads AS (
  SELECT unnest(ARRAY[
    1,16,40029,40358,40734,40739,40861,40955,40956,41582,41828,42818,
    41207,41164,40626,40298
  ])::bigint AS lead_id
),
manual_lead_review AS (
  SELECT * FROM (VALUES
    (42471::bigint,false,'airbnb_short_term_rental'),
    (40240::bigint,false,'non_real_estate_service')
  ) AS x(lead_id, actual_re_lead, category)
),
prospecto_flags AS (
  SELECT p.lead_id,
    BOOL_OR(
      p.prospecto_numero_whatsapp::text IN
        ('59164700143','59160028633','59176635354','59177355237','59169393294','59178586768')
      OR p.prospecto_numero_whatsapp::text LIKE '33%'
      OR p.prospecto_numero_whatsapp::text LIKE '39%'
    ) AS phone_blacklisted
  FROM public.prospectos p
  WHERE p.lead_id IS NOT NULL
  GROUP BY p.lead_id
),
lead_blacklist AS (
  SELECT al.lead_id,
    (fbl.lead_id IS NOT NULL
     OR COALESCE(pf.phone_blacklisted,false)
     OR COALESCE(mlr.actual_re_lead = false,false)) AS is_blacklisted
  FROM (
    SELECT DISTINCT cm.lead_id FROM public.chat_messages cm
    JOIN params p ON p.target_user_id = cm.user_id WHERE cm.lead_id IS NOT NULL
    UNION
    SELECT DISTINCT a.lead_id FROM public.appointments a WHERE a.lead_id IS NOT NULL
  ) al
  LEFT JOIN fixed_blacklisted_leads fbl ON fbl.lead_id = al.lead_id
  LEFT JOIN prospecto_flags pf ON pf.lead_id = al.lead_id
  LEFT JOIN manual_lead_review mlr ON mlr.lead_id = al.lead_id
),

/* ---- Per-lead flags, only for messages inside the window ---- */
msg_flags AS (
  SELECT cm.lead_id,
    BOOL_OR(NULLIF(TRIM(cm.content),'') IS NOT NULL) AS has_convo,
    BOOL_OR(NULLIF(TRIM(cm.content),'') IS NOT NULL
            AND LOWER(TRIM(cm.tipo_emisor))='bot') AS has_bot,
    BOOL_OR(NULLIF(TRIM(cm.content),'') IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.listing_projects lp
      WHERE lp.user_id = p.target_user_id AND lp.record_status = 1
        AND lp.record_deleted_at IS NULL AND NULLIF(TRIM(lp.name),'') IS NOT NULL
        AND (cm.content ILIKE '%'||lp.name||'%'
             OR word_similarity(lp.name::text, cm.content::text) >= 0.6)
    )) AS has_proj
  FROM public.chat_messages cm
  JOIN params p ON p.target_user_id = cm.user_id
  CROSS JOIN window_start w
  WHERE cm.lead_id IS NOT NULL
    AND COALESCE(cm.mensaje_enviado_el, cm.registro_creado_el) >= w.t0
  GROUP BY cm.lead_id
),

/* Bot-booked appointments inside the window (appointment-level) */
appts_in_window AS (
  SELECT a.id AS appointment_id, a.lead_id
  FROM public.appointments a
  JOIN params p ON true
  CROSS JOIN window_start w
  WHERE a.lead_id IS NOT NULL
    AND a.source_appointment ILIKE p.appointment_source_pattern
    AND a.created_at >= w.t0
),
appt_flags AS (
  SELECT DISTINCT lead_id FROM appts_in_window
),

leads AS (
  SELECT mf.lead_id,
    COALESCE(lb.is_blacklisted,false) AS bl,
    mf.has_convo, mf.has_bot, mf.has_proj,
    (mf.has_bot AND mf.has_proj) AS has_bot_proj,
    (af.lead_id IS NOT NULL) AS has_appt
  FROM msg_flags mf
  LEFT JOIN appt_flags af ON af.lead_id = mf.lead_id
  LEFT JOIN lead_blacklist lb ON lb.lead_id = mf.lead_id
),

/* CTWA lead set in the window */
ctwa_leads AS (
  SELECT DISTINCT cm.lead_id
  FROM public.chat_messages cm
  CROSS JOIN window_start w
  WHERE cm.plataforma_origen ILIKE '%CTWA%'
    AND cm.lead_id IS NOT NULL
    AND COALESCE(cm.mensaje_enviado_el, cm.registro_creado_el) >= w.t0
),
ctwa_count AS (
  SELECT COUNT(*) AS n FROM ctwa_leads
),
/* CTWA leads that also had a bot convo (blacklist applied) */
ctwa_bot_count AS (
  SELECT COUNT(*) AS n
  FROM leads l
  JOIN ctwa_leads c ON c.lead_id = l.lead_id
  WHERE l.has_bot AND NOT l.bl
),

stages AS (
  SELECT 1 s,'Leads with Convos' metric, COUNT(*) FILTER (WHERE has_convo AND NOT bl) n FROM leads
  UNION ALL SELECT 2,'Bot Engaged', COUNT(*) FILTER (WHERE has_bot AND NOT bl) FROM leads
  UNION ALL SELECT 3,'Leads with Project Mention', COUNT(*) FILTER (WHERE has_proj AND NOT bl) FROM leads
  UNION ALL SELECT 4,'Leads with Bot Convos & Project Mention', COUNT(*) FILTER (WHERE has_bot_proj AND NOT bl) FROM leads
  UNION ALL SELECT 5,'CTWA', (SELECT n FROM ctwa_count)
  UNION ALL SELECT 6,'CTWA with Bot Convos', (SELECT n FROM ctwa_bot_count)
  UNION ALL SELECT 7,'Appointments Booked by Bot',
    (SELECT COUNT(DISTINCT aw.appointment_id)
     FROM appts_in_window aw
     LEFT JOIN lead_blacklist lb ON lb.lead_id = aw.lead_id
     WHERE COALESCE(lb.is_blacklisted,false) = false)
  UNION ALL SELECT 8,'Leads with Meetings Booked by Bot', COUNT(*) FILTER (WHERE has_appt AND NOT bl) FROM leads
)

SELECT metric AS "Metric", n AS "Leads"
FROM stages
ORDER BY s;
