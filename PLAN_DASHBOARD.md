# Plan: Dashboard de Métricas UUID CFDI — ZFIR_UUID_CFDI_DASH

## Contexto

El programa `ZFIR_UUID_CFDI_UPDATE` procesa cientos de ficheros CSV con UUIDs de facturas electrónicas (CFDI México) y los graba en documentos contables SAP via `SAVE_TEXT` (objeto `BELEG`, text ID `YUUD`). Las ejecuciones son masivas (miles de líneas por fichero) y muchos registros fallan por no encontrarse en SAP. Actualmente el log vive solo en memoria y se pierde al cerrar el programa.

**Objetivo:** construir un dashboard histórico con la mayor riqueza visual posible en SAP ECC 6.0, accesible en cualquier momento (programa independiente), que permita ver métricas acumuladas de todas las ejecuciones: KPIs globales, agrupación por sociedad, por mes, por año, y detalle de errores con drill-down.

---

## Fase 1 — Persistencia: tablas Z en SE11

### Tabla ZFIR_UUID_LOG (detalle de cada registro procesado)

Crear en SE11 como tabla transparente, clase de datos A, categoría de entrega C:

| Campo | Tipo | Clave | Descripción |
|---|---|---|---|
| MANDT | MANDT | X | Mandante |
| DATUM_PROC | DATS | X | Fecha de procesamiento |
| UZEIT_PROC | TIMS | X | Hora de procesamiento |
| UNAME | XUBNAME | X | Usuario ejecutor |
| BUKRS | BUKRS | X | Sociedad |
| BELNR | BELNR_D | X | Documento contable |
| GJAHR | GJAHR | X | Ejercicio |
| FICHERO | CHAR100 | | Fichero CSV origen (nombre corto) |
| ICON_STATUS | ICON_D | | Semáforo: @08@=OK @09@=warn @0A@=error |
| RFC_EMISOR | CHAR13 | | RFC emisor CFDI |
| RFC_RECEPTOR | CHAR13 | | RFC receptor CFDI |
| SERIE | CHAR10 | | Serie CFDI |
| FOLIO | CHAR20 | | Folio CFDI |
| TIPO | CHAR1 | | Tipo comprobante I/E/P/T |
| TIPO_FAC | CHAR1 | | Tipo factura C/V/I |
| UUID | CHAR36 | | UUID CFDI asignado |
| UUID_PREVIO | CHAR36 | | UUID previo (si ya existía) |
| MENSAJE | CHAR255 | | Descripción del resultado |
| BUDAT | BUDAT | | Fecha contabilización del documento |
| BLDAT | BLDAT | | Fecha del documento |
| MONAT | MONAT | | Mes derivado de BUDAT (para agrupaciones rápidas) |
| BLART | BLART | | Clase de documento |
| TEST_MODE | CHAR1 | | X = ejecución de simulación |

**Índices secundarios:**
- `~001`: MANDT, BUKRS, GJAHR, MONAT — para consultas por sociedad/mes
- `~002`: MANDT, DATUM_PROC, UNAME — para consultas por ejecución/usuario
- `~003`: MANDT, ICON_STATUS, BUKRS — para análisis de errores por sociedad

### Tabla ZFIR_UUID_EXEC (cabecera por fichero procesado)

| Campo | Tipo | Clave | Descripción |
|---|---|---|---|
| MANDT | MANDT | X | |
| DATUM_PROC | DATS | X | Fecha proceso |
| UZEIT_PROC | TIMS | X | Hora proceso |
| UNAME | XUBNAME | X | Usuario |
| FICHERO | CHAR100 | X | Nombre fichero CSV |
| TEST_MODE | CHAR1 | | |
| TOT_REG | INT4 | | Total registros |
| TOT_OK | INT4 | | Registros OK |
| TOT_WARN | INT4 | | Registros warning |
| TOT_ERR | INT4 | | Registros error |

---

## Fase 2 — Modificaciones al programa existente (ZFIR_UUID_CFDI_UPDATE)

### Ficheros a modificar

| Fichero | Cambio |
|---|---|
| `ZFIR_UUID_CFDI_UPDATE_TOP.abap` | Añadir campos BUDAT, BLDAT, MONAT, BLART, TEST_MODE a `gty_log` |
| `ZFIR_UUID_CFDI_UPDATE_FRM01.abap` | Propagar `ls_bkpf-budat`, `ls_bkpf-bldat`, `ls_bkpf-blart` a `gs_log` en los forms `frm_obtener_factura_compra` y `frm_obtener_factura_venta` |
| `ZFIR_UUID_CFDI_UPDATE_FRM02.abap` | Calcular `gs_log-monat = gs_log-budat+4(2)` en `frm_actualizar_factura_uuid` |
| `ZFIR_UUID_CFDI_UPDATE_FRM00.abap` | Añadir `PERFORM frm_save_log_ztable` al final de `frm_procesar_carpeta` y del flujo fichero único |

### Nuevo form `frm_save_log_ztable`

```abap
FORM frm_save_log_ztable.
  DATA: lt_zlog  TYPE TABLE OF zfir_uuid_log,
        ls_zlog  TYPE zfir_uuid_log,
        ls_zexec TYPE zfir_uuid_exec.

  LOOP AT gt_log INTO gs_log.
    MOVE-CORRESPONDING gs_log TO ls_zlog.
    ls_zlog-datum_proc  = sy-datum.
    ls_zlog-uzeit_proc  = sy-uzeit.
    ls_zlog-uname       = sy-uname.
    ls_zlog-icon_status = gs_log-icon.
    ls_zlog-test_mode   = p_test.
    APPEND ls_zlog TO lt_zlog.
  ENDLOOP.

  MODIFY zfir_uuid_log FROM TABLE lt_zlog.

  ls_zexec-datum_proc = sy-datum.
  ls_zexec-uzeit_proc = sy-uzeit.
  ls_zexec-uname      = sy-uname.
  ls_zexec-fichero    = gv_fichero_actual.  " nombre corto ya calculado
  ls_zexec-test_mode  = p_test.
  ls_zexec-tot_reg    = gv_total.
  ls_zexec-tot_ok     = gv_ok.
  ls_zexec-tot_warn   = gv_warning.
  ls_zexec-tot_err    = gv_error.
  MODIFY zfir_uuid_exec FROM ls_zexec.

  COMMIT WORK AND WAIT.
ENDFORM.
```

**Dónde llamarlo:**
- Modo carpeta: al final del `LOOP AT lt_files` dentro de `frm_procesar_carpeta`, tras acumular contadores del fichero actual
- Modo fichero único: al final de START-OF-SELECTION, antes de `frm_mostrar_alv`

---

## Fase 3 — Nuevo programa: ZFIR_UUID_CFDI_DASH

Programa independiente (transacción propia). Accesible en cualquier momento sin necesidad de lanzar una carga.

### Includes propuestos

| Include | Contenido |
|---|---|
| `ZFIR_UUID_CFDI_DASH_TOP` | Tipos, datos globales, referencias a objetos GUI |
| `ZFIR_UUID_CFDI_DASH_SEL00` | Selection screen, F4 helps, AT SELECTION-SCREEN |
| `ZFIR_UUID_CFDI_DASH_FRM00` | PBO/PAI del Screen 100, construcción jerarquía GUI |
| `ZFIR_UUID_CFDI_DASH_FRM01` | SELECT de ZFIR_UUID_LOG + todas las agregaciones |
| `ZFIR_UUID_CFDI_DASH_FRM02` | Tab 1: KPI cards (CL_DD_DOCUMENT) + chart pie |
| `ZFIR_UUID_CFDI_DASH_FRM03` | Tab 2: ALV por sociedad + chart barras apiladas |
| `ZFIR_UUID_CFDI_DASH_FRM04` | Tab 3: ALV tendencia mensual + chart líneas |
| `ZFIR_UUID_CFDI_DASH_FRM05` | Tab 4: ALV errores con coloring por fila |
| `ZFIR_UUID_CFDI_DASH_FRM06` | Tab 5: ALV detalle completo + drill-down FB03 |

### Selection screen

```
Bloque "Período de análisis":
  SO_DATUM  FOR zfir_uuid_log-datum_proc   "Fecha de procesamiento"
  SO_BUKRS  FOR zfir_uuid_log-bukrs        "Sociedad"
  SO_GJAHR  FOR zfir_uuid_log-gjahr        "Ejercicio"
  SO_MONAT  FOR zfir_uuid_log-monat        "Mes (01-12)"
  SO_UNAME  FOR zfir_uuid_log-uname        "Usuario"
  P_TEST    CHECKBOX DEFAULT ' '           "Incluir ejecuciones de simulación"
```

### Dynpro Screen 100 — Jerarquía de controles

Contiene un único Custom Control `CC_MAIN` que ocupa toda la pantalla. Toda la UI se construye en ABAP OO en el PBO:

```
CC_MAIN (CL_GUI_CUSTOM_CONTAINER)
└── go_tabstrip (CL_GUI_TABSTRIP)
    ├── Tab 1 "Resumen KPIs"      → go_split_t1 (CL_GUI_SPLITTER_CONTAINER 40|60)
    │   ├── Izq 40%: CL_DD_DOCUMENT  → KPI cards con semáforos e iconos
    │   └── Der 60%: CL_GUI_CHART_ENGINE → chart tipo PIE (OK/Warn/Error)
    ├── Tab 2 "Por Sociedad"      → go_split_t2 (CL_GUI_SPLITTER_CONTAINER 55|45)
    │   ├── Arr 55%: CL_GUI_ALV_GRID → bukrs/butxt/total/ok/warn/error/% con coloring
    │   └── Aba 45%: CL_GUI_CHART_ENGINE → barras apiladas por sociedad
    ├── Tab 3 "Tendencia Mensual" → go_split_t3 (CL_GUI_SPLITTER_CONTAINER 55|45)
    │   ├── Arr 55%: CL_GUI_ALV_GRID → gjahr/monat/periodo/total/ok/warn/error
    │   └── Aba 45%: CL_GUI_CHART_ENGINE → líneas (total + errores por mes)
    ├── Tab 4 "Análisis Errores"  → CL_GUI_ALV_GRID con coloring por fila
    │   Columnas: semáforo | mensaje | bukrs | gjahr | monat | cantidad | doc.ejemplo
    │   Ordenado: más frecuentes primero. Rojo=C100, Amarillo=C200
    └── Tab 5 "Detalle Completo"  → CL_GUI_ALV_GRID con todos los campos de ZFIR_UUID_LOG
        Doble clic en fila → FB03 (SET PARAMETER ID + CALL TRANSACTION)
```

### GUI Status (SE41): `DASH_STATUS`

- F3/BACK, F15/EXIT, F12/CANCEL
- Botón toolbar **REFRESH** → releer Z-table y refrescar todos los tabs
- Botón toolbar **EXCEL** → exportar ALV activo

---

## Tipos de datos globales clave (TOP del dashboard)

```abap
TYPES: BEGIN OF gty_kpi,
  tot_reg  TYPE i,    tot_ok   TYPE i,
  tot_warn TYPE i,    tot_err  TYPE i,
  pct_ok   TYPE p DECIMALS 2,
  pct_err  TYPE p DECIMALS 2,
  num_uuid TYPE i,    num_exec TYPE i,
END OF gty_kpi.

TYPES: BEGIN OF gty_by_bukrs,
  bukrs    TYPE bukrs,   butxt   TYPE butxt,
  tot_reg  TYPE i,       tot_ok  TYPE i,
  tot_warn TYPE i,       tot_err TYPE i,
  pct_ok   TYPE p DECIMALS 2,
  light    TYPE char4,   " 'C300'=verde, 'C200'=amarillo, 'C100'=rojo
END OF gty_by_bukrs.

TYPES: BEGIN OF gty_by_month,
  gjahr    TYPE gjahr,   monat   TYPE monat,
  periodo  TYPE char7,   " 'AAAA/MM'
  tot_reg  TYPE i,       tot_ok  TYPE i,
  tot_warn TYPE i,       tot_err TYPE i,
END OF gty_by_month.

TYPES: BEGIN OF gty_errors,
  rowcolor   TYPE char4,    " 'C100'=rojo, 'C200'=amarillo
  mensaje    TYPE char255,  bukrs      TYPE bukrs,
  gjahr      TYPE gjahr,    monat      TYPE monat,
  cnt        TYPE i,        belnr_ex   TYPE belnr_d,
  fichero_ex TYPE char100,
END OF gty_errors.
```

---

## Implementación CL_GUI_CHART_ENGINE

El chart engine de ECC acepta datos en XML via `set_data_xml`:

**Tab 1 — Pie (OK/Warn/Error):**
```xml
<ChartData>
  <Series name="Estados">
    <DataPoint label="OK"      value="[tot_ok]"/>
    <DataPoint label="Warning" value="[tot_warn]"/>
    <DataPoint label="Error"   value="[tot_err]"/>
  </Series>
</ChartData>
```
`chart_type = cl_gui_chart_engine=>chart_type_pie`

**Tab 2 — Barras apiladas por sociedad:**
Tres series OK/Warning/Error, un DataPoint por BUKRS.
`chart_type = cl_gui_chart_engine=>chart_type_bar_stacked`

**Tab 3 — Líneas tendencia mensual:**
Series "Total" y "Errores", un DataPoint por período 'AAAA/MM'.
`chart_type = cl_gui_chart_engine=>chart_type_line`

---

## Lectura y agregaciones (FRM01 del dashboard)

```abap
SELECT * FROM zfir_uuid_log
  INTO TABLE gt_zlog_raw
  WHERE datum_proc IN so_datum
    AND bukrs      IN so_bukrs
    AND gjahr      IN so_gjahr
    AND monat      IN so_monat
    AND uname      IN so_uname
    AND ( p_test = 'X' OR test_mode = ' ' ).
```

Agregaciones en memoria sobre `gt_zlog_raw`:
- **KPIs globales** (`gs_kpi`): LOOP por ICON_STATUS + UUIDs únicos (SORT+DELETE DUPLICATES) + porcentajes
- **Por BUKRS** (`gt_by_bukrs`): coloring `pct_ok >= 95` → C300 verde, `>= 80` → C200 amarillo, `< 80` → C100 rojo. Enriquecer con `SELECT butxt FROM t001`
- **Por mes** (`gt_by_month`): clave GJAHR+MONAT, campo `periodo = 'AAAA/MM'`, ordenado cronológicamente
- **Errores agrupados** (`gt_errors`): solo icon_status IN ('@0A@','@09@'), agrupados por mensaje+bukrs, ordenados por `cnt DESC`

---

## Drill-down Tab 5 — Clase local de eventos

```abap
CLASS lcl_evt DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS on_dbl_click
      FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column.
ENDCLASS.
CLASS lcl_evt IMPLEMENTATION.
  METHOD on_dbl_click.
    DATA ls_det TYPE zfir_uuid_log.
    READ TABLE gt_detail INTO ls_det INDEX e_row-index.
    IF sy-subrc = 0 AND ls_det-belnr IS NOT INITIAL.
      SET PARAMETER ID 'BUK' FIELD ls_det-bukrs.
      SET PARAMETER ID 'BLN' FIELD ls_det-belnr.
      SET PARAMETER ID 'GJR' FIELD ls_det-gjahr.
      CALL TRANSACTION 'FB03' AND SKIP FIRST SCREEN.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
```

---

## Secuencia de implementación

### Bloque A — Persistencia (modifica programa de carga existente)
1. Crear `ZFIR_UUID_LOG` y `ZFIR_UUID_EXEC` en SE11 + activar + índices secundarios
2. Ampliar `gty_log` en `ZFIR_UUID_CFDI_UPDATE_TOP.abap` (BUDAT, BLDAT, MONAT, BLART, TEST_MODE)
3. Propagar `ls_bkpf-budat/bldat/blart` → `gs_log` en FRM01 (forms `frm_obtener_factura_compra` y `frm_obtener_factura_venta`)
4. Calcular `gs_log-monat = gs_log-budat+4(2)` en `frm_actualizar_factura_uuid` (FRM02)
5. Añadir `frm_save_log_ztable` y llamarlo desde `frm_procesar_carpeta` y flujo fichero único

### Bloque B — Programa dashboard (nuevo)
6. Crear programa `ZFIR_UUID_CFDI_DASH` con todos los includes en SE38
7. TOP: tipos + variables globales + referencias a objetos GUI
8. SEL00: selection screen con filtros
9. FRM01: SELECT + 4 agregaciones en memoria
10. Screen 100 en SE51 + Custom Control `CC_MAIN` + Flow Logic PBO/PAI
11. GUI Status `DASH_STATUS` en SE41
12. FRM00: PBO/PAI + `frm_create_gui_hierarchy` (tabstrip → splitters → contenedores)
13. FRM02: Tab 1 — `CL_DD_DOCUMENT` KPI cards + `CL_GUI_CHART_ENGINE` pie
14. FRM03: Tab 2 — `CL_GUI_ALV_GRID` por sociedad + chart barras
15. FRM04: Tab 3 — `CL_GUI_ALV_GRID` tendencia + chart líneas
16. FRM05: Tab 4 — `CL_GUI_ALV_GRID` errores con coloring (`info_fname`)
17. FRM06: Tab 5 — `CL_GUI_ALV_GRID` detalle + handler `lcl_evt` doble clic → FB03

---

## Verificación end-to-end

1. Ejecutar `ZFIR_UUID_CFDI_UPDATE` con un fichero CSV pequeño en modo simulación → verificar filas en `ZFIR_UUID_LOG` y `ZFIR_UUID_EXEC` via SE16
2. Verificar que BUDAT/BLDAT/MONAT se populan correctamente
3. Lanzar `ZFIR_UUID_CFDI_DASH` con filtro fecha = hoy → debe mostrar los registros recién grabados
4. Comprobar que los KPIs en Tab 1 coinciden con los totales en `ZFIR_UUID_EXEC`
5. Doble clic en Tab 5 → debe abrir FB03 con el documento correcto
6. Ejecutar con múltiples fechas → verificar tendencia mensual en Tab 3
7. Botón REFRESH sin salir → releer datos y actualizar todos los tabs
