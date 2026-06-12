# Capital — Presentación de valor · Documento de traspaso

Archivo único: **`Capital_Presentacion.html`** (sin dependencias, abre con doble clic).
Toda la lógica vive en el objeto `CAP` dentro del `<script>`. El HTML solo *muestra*; nada se calcula fuera de `CAP`.

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

### D. Tiempo recuperado (slide 5 — dato real)
```
agent_hourly = utilidad_neta / work_hours_yr       ≈ 192 BOB/h
time_value   = time_saved_may × agent_hourly       ≈ 3,460 BOB
time_fee_coverage = time_value / service_fee       ≈ 1.2× el precio mensual
```

La cobertura por tiempo y la cobertura por una venta se muestran por separado. Son
ratios contra el precio mensual, no una estimación de meses transcurridos.
El slide 6 no suma `time_value` y `net_after_fee`: muestra el valor operativo real y
la ganancia neta proyectada en carriles separados para evitar doble conteo.

### E. Progreso a la 1ª venta (slide 2)
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
- **Supuesto (único no medido):** `appts_sale` — citas por venta. Marcado en ámbar en el slide 4 y en el panel (grupo "✦ Editables en diapositiva").

---

## 5. Panel "Auditar datos"
- Inputs agrupados por `g` (orden de `CAP.groups`). Buscador filtra por label/clave/fuente.
- Las variables con `s:1` (editables en slide) llevan ✦ ámbar y van primero.
- `%` se muestra ×100 (2, no 0.02) y se reconvierte al editar.
- Inputs se construyen **una vez** (`buildAuditInputs`); en cada render solo se sincroniza el valor de los campos no enfocados (`syncAuditInputs`) — por eso ya no expulsa al tipear.
- Derivados (`renderDerived`) muestran fórmula `f` + resultado; se reconstruyen en cada render (no tienen campos editables).

---

## 6. Para extender (Codex)
- **Agregar un input:** añadir a `CAP.inputs` con `g` (y `s:1` si tendrá slider). Aparece solo en el panel.
- **Agregar un cálculo:** añadir a `CAP.derived` *después* de sus dependencias. Usar `f` legible.
- **Otro mes / escenario:** los `fun_*`, `appt_rate_may`, `time_saved_may` son los que cambian por período. Se podría envolver en `CAP.periodos[...]` y un selector, replicando el patrón del pill de moneda.
- **No** volver a escribir números directamente en `render()`; romper esa regla es lo que causó los bugs de propagación.
