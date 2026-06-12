# Capital — Presentación de valor · Documento de traspaso

Archivo único: **`Capital_Presentacion.html`** (sin dependencias, abre con doble clic).
Toda la lógica vive en el objeto `CAP` dentro del `<script>`. El HTML solo *muestra*; nada se calcula fuera de `CAP`.
El logo va **inline** (markup `<svg>` en el `.logo`), no por `<img src>` — funciona en `file://`.

### Estructura narrativa (7 slides) · flujo: margen → conversión → cálculo → precio
Rediseñado slide por slide con referencias del cliente (layouts "card + iconos"). **Sin eyebrows** (rótulos chiquitos arriba) y **sin cintas hand-off / chips carry-in** — se quitaron por pedido (eran del viejo armado "Pruebas"). Único rótulo que queda: "El precio" dentro del closebox.
1. **Portada · Costo vs Retorno del Servicio** — card Costo (`service_fee`) + chevron + card Retorno con 3 columnas. IDs `cvr_*`.
2. **Cálculo del Tiempo Recuperado** — 18 h = lectura+escritura+documentos en 3 cards + resultado. IDs `tc_*`. (`time_saved` derivado = `t_read_h+t_write_h+t_doc_h`.)
3. **De horas a valor económico** — grid fórmula utilidad ÷ horas = tarifa; tarifa × horas = valor. IDs `ve_*`.
4. **Motor · Cuánto deja una venta asistida** — 2 cards: (1) Margen neto anual con %s + line-items SIN montos ("oculto por confidencialidad") → 53.5%; (2) venta promedio × comisión × margen → 7,482. IDs `m_*`. **Ya no hay tabla anual con eye-toggle en la slide** (los montos confidenciales solo viven en el panel Auditar datos).
5. **Embudo · La tasa cita/lead sale de Mayo** — funnel verde sólido + progreso + callout. IDs `funnelEl`, `tf_*`, `emb_*`.
6. **Proyección · Cuánto produce el sistema al mes** — cadena leads→ganancia + sliders. IDs `chainEl`, `sl_*`.
7. **Close** — el precio y las coberturas (1.2× / 3.3×).

> Velocidades (`read_pps`=15, `type_pps`=5, `sec_doc`=30) son solo informativas en el footer del slide 2 — no entran en ningún cálculo.
> Pendiente (slide 2): conteos x/y de mensajes leídos/escritos en las cajas (faltan datos del cliente; z=documentos derivable = 480).

### Conexión entre slides (sin cintas)
Las cintas `.handoff` y los chips `.carryin` se **eliminaron** (pedido del cliente). La coherencia ahora vive en el ORDEN: Motor produce el margen/venta (7,482) → Embudo muestra la conversión real (tasa 4.2%, supuesto 15 citas) → Proyección combina ambos en la cadena leads→ganancia. El hilo de datos sigue existiendo en `CAP` (`net_per_sale` y `appt_rate_may` alimentan la cadena), solo que ya no se rotula en pantalla.

---

## 1. Modelo de datos (`CAP`)

```
CAP = {
  inputs:  { clave: {v, unit, label, src, g, s} },   // números crudos, editables
  groups:  { claveGrupo: "Etiqueta visible" },        // orden y nombres del panel
  derived: [ {k, label, unit, f, fn, src} ],          // números calculados
}
```

- **`inputs`** = única fuente de verdad. Cada uno:
  - `v` valor · `unit` unidad · `label` nombre visible · `src` de dónde sale
  - `g` grupo (para el panel "Auditar datos") · `s:1` = editable también en una diapositiva (slider)
- **`derived`** = se calculan en orden con `fn(I, D)`:
  - `I` = valores de inputs · `D` = derivados ya calculados (el orden del array importa)
  - `f` = fórmula en texto (se muestra en el panel) · `fn` = la función real
- **`groups`** define el orden y los títulos de las secciones del panel.

### Regla de oro
Para cambiar un número, se edita **un solo** input (en el panel o en su slider). Nunca hay un número escrito a mano en el render: si aparece en pantalla, vino de `compute()`.

`compute()` arma `{I, D}` y `render()` pinta las 6 diapositivas + el panel. Cualquier edición llama a `render()`.

---

## 2. Cadena de cálculo (cómo se conecta todo)

### A. Modelo anual del agente → margen neto
Los costos fijos definen el margen; **no hay un "margen" suelto**.

```
ingreso_neto   = ann_bruto × (1 − com_oficina_pct − com_remax_pct)
costos_fijos   = (salario_asist_mes + contador_mes + oficina_mes) × 12
ebt            = ingreso_neto − costos_fijos
impuestos      = ebt × impuestos_pct
utilidad_neta  = ebt − impuestos
margen_neto    = utilidad_neta / ann_bruto        ≈ 53.4456 %
```
Editar **Comisión REMAX** (o cualquier costo) recalcula `margen_neto`, `utilidad_neta` y todo lo de abajo.
Esta es la tabla del **slide 3** (se construye en `annualRows(I,D)`).

### B. Economía por venta
```
comision_bob = venta_prom_bob × comision_pct      (700,000 × 2% = 14,000... → ver nota TC)
net_per_sale = comision_bob × margen_neto          ≈ 7,482 BOB
sale_fee_coverage = net_per_sale / service_fee     ≈ 2.5× el precio mensual
```

### C. Modelo mensual (proyección — slide 4)
```
marketing      = vol_leads × cost_lead             (variable; cost_lead viene de Ene-Mar)
citas_mes      = vol_leads × appt_rate_may
sales_qty      = citas_mes / appts_sale            (appts_sale = ÚNICO supuesto)
gross_gain     = sales_qty × net_per_sale
net_before_fee = gross_gain − marketing
net_after_fee  = net_before_fee − service_fee      ← número estrella, YA incluye el servicio
```

### D. Tiempo recuperado (slide 2 — dato real, Prueba 1)
```
agent_hourly = utilidad_neta / work_hours_yr       ≈ 192 BOB/h
time_value   = time_saved_may × agent_hourly       ≈ 3,460 BOB
time_fee_coverage = time_value / service_fee       ≈ 1.2× el precio mensual
```

La cobertura por tiempo y la cobertura por una venta se muestran por separado. Son
ratios contra el precio mensual, no una estimación de meses transcurridos.
El slide 6 no suma `time_value` y `net_after_fee`: muestra el valor operativo real y
la ganancia neta proyectada en carriles separados para evitar doble conteo.

### E. Progreso a la 1ª venta (slide 5 · Evidencia/Embudo)
```
leads_for_sale = appts_sale / appt_rate_may        (≈ 354 leads para 1 venta a 1/15)
```
Barras: leads `fun_conv` (191) vs `leads_for_sale`; citas `fun_cita` (7) vs `appts_sale` (15).

---

## 3. Conversión de moneda
Todo se guarda en **BOB**. El pill arriba (BOB / USD Of. / USD Par.) solo cambia la *visualización*:
- `FX_MAP`: BOB ×1 · USD Of. ÷7 · USD Par. ÷10
- `fmtM()` / `fmtMSign()` aplican `FX.rate` al imprimir. Los cálculos nunca cambian de moneda.

> Nota: `venta_prom_bob = 700,000` ya es "USD Paralelo × 10". 70,000 USD-Par = 700,000 BOB.

---

## 4. Supuestos vs datos reales (importante para el pitch)
- **Reales / medidos:** embudo Mayo (`fun_*`), `appt_rate_may`, `time_saved_may`, costos del modelo anual, `cost_lead` (Ene-Mar).
- **Supuestos (no medidos) — son DOS, ambos declarados:**
  1. `appts_sale` — citas por venta. Marcado en ámbar en el slide 4 (slider + chain) y en el panel.
  2. `venta_prom_bob` — venta promedio. No tenemos el valor real; marcado "supuesto" en el puente del slide 3 (Motor) y declarado en la lede del slide 4.
- El copy NO debe decir "una sola incógnita / único supuesto": son dos. Si se mide alguno, quitar su badge y actualizar la lede del slide 4.

---

## 5. Panel "Auditar datos"
- Inputs agrupados por `g` (orden de `CAP.groups`). Buscador filtra por label/clave/fuente.
- Las variables con `s:1` (editables en slide) llevan ✦ ámbar y van primero.
- `%` se muestra ×100 (2, no 0.02) y se reconvierte al editar.
- Inputs se construyen **una vez** (`buildAuditInputs`); en cada render solo se sincroniza el valor de los campos no enfocados (`syncAuditInputs`) — por eso ya no expulsa al tipear.
- Derivados (`renderDerived`) muestran fórmula `f` + resultado; se reconstruyen en cada render (no tienen campos editables).

### Valores confidenciales del cliente (slide 4 · Motor)
El rediseño del Motor **ya no muestra montos** del P&L en la slide: solo %s (oficina/REMAX/impuestos) y los nombres de los costos fijos, con la nota "Detalle de montos oculto por confidencialidad". Los montos absolutos solo se ven en el panel **Auditar datos** (para el presentador). Se quitó la tabla anual con eye-toggle (`#confToggle`, `annualRows`, `toggleDet` quedaron como código muerto sin uso).

---

## 6. Para extender (Codex)
- **Agregar un input:** añadir a `CAP.inputs` con `g` (y `s:1` si tendrá slider). Aparece solo en el panel.
- **Agregar un cálculo:** añadir a `CAP.derived` *después* de sus dependencias. Usar `f` legible.
- **Otro mes / escenario:** los `fun_*`, `appt_rate_may`, `time_saved_may` son los que cambian por período. Se podría envolver en `CAP.periodos[...]` y un selector, replicando el patrón del pill de moneda.
- **No** volver a escribir números directamente en `render()`; romper esa regla es lo que causó los bugs de propagación.
