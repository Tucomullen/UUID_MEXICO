# Contexto del Proyecto: UUID CFDI México — Acciona

## Resumen ejecutivo

Proyecto ABAP para **actualizar masivamente el UUID (Folio Fiscal CFDI)** en facturas ya existentes en SAP ECC 6.0, a partir de archivos CSV generados por la herramienta Soltum. Las 14 sociedades mexicanas de Acciona necesitan completar los UUIDs históricos desde 2018.

**Repositorio:** https://github.com/Tucomullen/UUID_MEXICO.git

**Desarrollador:** xlgarcia (Acciona TIC)

**Sistema SAP:** ECC 6.0 EHP 7+ (ABAP 7.40+), servidor Windows, ruta UNC `\\sapzserverpre.echo.int\sapcorp\ZINTERFASES\ZUUID`

---

## Programas desarrollados

### 1. ZFIR_UUID_CFDI_UPDATE (programa de carga)

Actualiza UUIDs en documentos contables SAP. Tres modos de operación:

| Modo | Parámetro | Descripción | Ejecución en fondo |
|---|---|---|---|
| Fichero individual | `P_FICH` | Un CSV desde PC local via `gui_upload` | No |
| Carpeta local | `P_CARP` | Todos los CSV de 1 carpeta local | No |
| **Servidor AL11** | `P_SERV` | Recursivo desde directorio servidor | **Sí (SM36)** |

**Includes:**

| Include | Contenido |
|---|---|
| `_TOP` | Tipos, constantes, datos globales, pantalla de selección |
| `_SEL00` | F4 helps (fichero, carpeta, servidor), MODIF ID show/hide, validaciones |
| `_FRM00` | Lectura CSV (local + servidor), parseo, BOM UTF-8, exploración recursiva AL11, `frm_procesar_registros`, `frm_save_log_ztable`, `frm_procesar_servidor`, `frm_procesar_carpeta` |
| `_FRM01` | Localización documentos: `frm_tipo_factura`, `frm_obtener_factura_compra`, `frm_obtener_factura_venta`, `frm_procesar_intercompany` |
| `_FRM02` | Grabación UUID: `frm_existe_uuid`, `frm_salvar_uuid`, `frm_actualizar_factura_uuid`, ALVs |

### 2. ZFIR_UUID_CFDI_DASH (dashboard histórico)

Programa independiente que lee de `ZTT_UUID_LOG` y muestra métricas acumuladas. 5 pestañas con toolbar OO + docking container (sin Dynpro tabstrip):

- Tab 1: KPIs HTML + ALV resumen + Top 5 sociedades
- Tab 2: ALV por sociedad con coloring semáforo
- Tab 3: Tendencia mensual
- Tab 4: Errores agrupados por frecuencia
- Tab 5: Detalle completo con drill-down FB03

---

## Cómo se almacena el UUID (CRÍTICO)

El UUID **NO está en ningún campo de tabla de BD**. Se almacena como **texto largo SAPscript**:

```
SAVE_TEXT / READ_TEXT
  OBJECT   = 'BELEG'
  ID       = 'YUUD'
  LANGUAGE = 'S'
  NAME     = <BUKRS><BELNR><GJAHR>  (concatenado sin separadores)
```

Esto es compatible al 100% con el programa existente `ZFII_MEXICO_UIID` (transacción ZFI271) que graba UUIDs desde XMLs individuales.

---

## Lógica funcional clave

### Mapeo RFC → Sociedad
```
T001Z WHERE party = 'MX_RFC' AND paval = <RFC>  →  BUKRS
```

### Determinación tipo factura
- Emisor MX + Receptor MX → **Intercompany** (procesa ambos lados)
- Emisor externo + Receptor MX → **Compra** (proveedor en LFA1.STCD1)
- Emisor MX + Receptor externo → **Venta** (cliente en KNA1.STCD1)

### Búsqueda documento
1. Primaria: BKPF WHERE `xblnr LIKE '%folio%'` + validación BSEG (koart + lifnr/kunnr + importe)
2. Alternativa (sin folio): BKPF por fecha (bldat/budat) + validación BSEG
3. Pagos (`P`): BLART='DZ', BELNR LIKE, sin comparación de importe

### Estados UUID (constantes gc_stat_*)
- `gc_stat_empty` = '0': Sin UUID → proceder a grabar
- `gc_stat_same` = '1': UUID ya existe y coincide → OK, no hacer nada
- `gc_stat_diff` = '2': UUID ya existe pero es distinto → Warning discrepancia

### Intercompany
Proveedor intercompany: `V-<bukrs_emisor>`. Cliente intercompany: `C-<bukrs_receptor>`.

---

## Tablas Z (persistencia)

### ZTT_UUID_LOG (detalle por registro)
Claves: MANDT, DATUM_PROC, UZEIT_PROC, UNAME, BUKRS, BELNR, GJAHR.
Campos relevantes: ICON_STATUS, FICHERO, RFC_EMISOR, RFC_RECEPTOR, FOLIO, UUID, UUID_PREVIO, MENSAJE, BUDAT, BLDAT, MONAT, BLART, TEST_MODE.

### ZTT_UUID_EXEC (cabecera por fichero)
Claves: MANDT, DATUM_PROC, UZEIT_PROC, UNAME, FICHERO.
Campos: TEST_MODE, TOT_REG, TOT_OK, TOT_WARN, TOT_ERR.

---

## Formato CSV de entrada

Separador `;` (también acepta `|`). Cabecera en primera línea. UTF-8 con posible BOM.

```
EmisorRFC;ReceptorRFC;Serie;Folio;FechaFacturacion;Total;TipoComprobante;UUID
```

- Fecha: `DD/MM/YYYY HH:MM:SS a. m.` → se extrae solo GJAHR (posiciones 6-9)
- Total: formato europeo con coma (`26.640,80`) o CFDI XML con puntos (`41.760.000.000` = 41760 × 10^6)
- Serie y Folio pueden venir vacíos
- UUID: 36 chars con guiones

---

## Estructura de los CSV en servidor

```
\\sapzserverpre.echo.int\sapcorp\ZINTERFASES\ZUUID\06. CSV_Soltum\
├── 2018\
│   ├── AES180129LN8\         (RFC de la sociedad)
│   │   ├── AES180129LN8_Clientes_Egreso_0118.csv
│   │   ├── AES180129LN8_Clientes_Ingreso_0118.csv
│   │   ├── AES180129LN8_Proveedores_Egreso_0118.csv
│   │   └── ... (12 meses × tipo)
│   ├── AMG140818FK7\
│   ├── ... (14 sociedades por RFC)
│   └── TEI150930N7A\
├── 2019\
├── ...
└── 2025\
```

**Total: 4.370 archivos, 104 carpetas, 45,5 MB**. Exploración recursiva con `C_DIR_READ_START`/`C_DIR_READ_NEXT`/`C_DIR_READ_FINISH`.

---

## Naming Standards Acciona (obligatorios)

| Objeto | Convención | Ejemplo |
|---|---|---|
| Programa ejecutable | `Z<ProcessID><RICEFW>_<nombre>` | `ZFIR_UUID_CFDI_UPDATE` |
| Includes | `<Program>_TOP`, `_SELyy`, `_FRMyy`, `_LCLyy` | `ZFIR_UUID_CFDI_UPDATE_FRM00` |
| Variables globales | `GV_`, `GT_`, `GS_`, `GC_`, `GO_` | `GT_CSV_DATA` |
| Variables locales | `LV_`, `LT_`, `LS_`, `LC_`, `LO_` | `LV_BELNR` |
| Parámetros | `P_<nombre>` (máx 8 chars) | `P_FILE` |
| Select-Options | `S_<nombre>` | `S_BUKRS` |

Documento completo de naming: `Acciona_DEV_SAP Naming Standards_v2.docx` en el proyecto.

---

## Estado actual (10/04/2026)

### Lo que FUNCIONA:
- ✅ Modo fichero individual (lectura local, parseo, búsqueda BKPF/BSEG, SAVE_TEXT/READ_TEXT)
- ✅ Modo carpeta local (procesa todos los CSV de 1 directorio)
- ✅ Modo servidor AL11 recursivo (exploración con C_DIR_READ_*, OPEN DATASET)
- ✅ Lógica completa: Compra/Venta/Intercompany, búsqueda alternativa por fecha
- ✅ Estados UUID: sin UUID / mismo UUID (OK) / UUID distinto (warning discrepancia)
- ✅ Persistencia en ZTT_UUID_LOG + ZTT_UUID_EXEC
- ✅ Dashboard con 5 pestañas (KPIs, por sociedad, mensual, errores, detalle+FB03)
- ✅ Conversión de importes: formato europeo y CFDI XML
- ✅ Idempotencia: reejecutar no sobrescribe ni causa error

### Prueba en curso:
- Se ejecutó modo servidor AL11 en modo SIMULACIÓN (online, no en fondo aún)
- Ruta: `\\SAPZSERVERPRE.ECHO.INT\SAPCORP\ZINTERFASES\ZUUID\06. CSV_Soltum`
- **215 ficheros CSV encontrados** recursivamente
- Los primeros 21 ficheros muestran OK:0, Warn:0, Err:0 (todos los registros procesados sin errores en simulación)
- Resultado: los CSV se leen correctamente, la exploración recursiva funciona

### Siguiente paso:
- Verificar el resumen final del spool completo de la simulación
- Si OK → ejecutar en productivo (desmarcar P_TEST) en fondo (SM36)
- Verificar resultados en el Dashboard
- Considerar si 215 ficheros es correcto (vs los 4.370 del total — puede que la simulación solo cubra una parte de la estructura)

---

## Dependencias del sistema (ya existentes, NO crear)

- Text ID `YUUD` para objeto `BELEG` (configurado para ZFII_MEXICO_UIID)
- Tabla `T001Z` con `PARTY = 'MX_RFC'` (14 sociedades MX)
- LFA1.STCD1 (RFC proveedores), KNA1.STCD1 (RFC clientes)
- Objeto de autorización `F_BKPF_BUK`
- Tablas Z: ZTT_UUID_LOG, ZTT_UUID_EXEC

---

## Consideraciones de rendimiento

- `SELECT ... WHERE xblnr LIKE '%folio%'` fuerza full scan en BKPF (no usa índice). Aceptable porque el programa existente ZFII_MEXICO_UIID ya lo hace así.
- `COMMIT WORK AND WAIT` individual por registro: libera locks inmediatamente.
- Parámetro `P_WAIT` (pausa entre ficheros): recomendado 0 segundos. Solo aumentar si se observa degradación.
- Un job de fondo ocupa 1 work process, impacto mínimo.
