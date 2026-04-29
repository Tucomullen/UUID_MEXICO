*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLIC_TOP
*&---------------------------------------------------------------------*
*& Tipos, datos globales y pantalla de selección.
*&---------------------------------------------------------------------*

TABLES: t001, bkpf.


**********************************************************************
** CONSTANTES
**********************************************************************
CONSTANTS:
  gc_object    TYPE tdobject VALUE 'BELEG',
  gc_tdid      TYPE tdid     VALUE 'YUUD',
  gc_language  TYPE spras    VALUE 'S',
  gc_party     TYPE char10   VALUE 'MX_RFC',
  gc_icon_ok   TYPE icon_d   VALUE '@08@',
  gc_icon_warn TYPE icon_d   VALUE '@09@',
  gc_icon_err  TYPE icon_d   VALUE '@0A@'.

**********************************************************************
** TIPOS
**********************************************************************

* Registro CSV (un CFDI del fichero)
TYPES: BEGIN OF gty_csv_rec,
         uuid         TYPE char36,
         rfc_emisor   TYPE char13,
         rfc_receptor TYPE char13,
         serie        TYPE char10,
         folio        TYPE char20,
         fecha        TYPE char30,
         total        TYPE char25,
         tipo         TYPE char1,     " I/E/P/T
         fichero      TYPE string,
       END OF gty_csv_rec.

TYPES: tt_csv_rec TYPE TABLE OF gty_csv_rec.

* UUID asignado a un documento SAP (leído de STXH/STXL)
TYPES: BEGIN OF gty_uuid_sap,
         uuid  TYPE char36,
         bukrs TYPE bukrs,
         belnr TYPE belnr_d,
         gjahr TYPE gjahr,
       END OF gty_uuid_sap.

TYPES: tt_uuid_sap TYPE TABLE OF gty_uuid_sap.

* Fila del ALV resultado
TYPES: BEGIN OF gty_resultado,
         icon         TYPE icon_d,
         uuid         TYPE char36,    " UUID duplicado procesado
         bukrs_ok     TYPE bukrs,     " Sociedad del doc correcto
         belnr_ok     TYPE belnr_d,   " Doc correcto
         gjahr_ok     TYPE gjahr,
         bukrs_ko     TYPE bukrs,     " Sociedad del doc incorrecto
         belnr_ko     TYPE belnr_d,   " Doc incorrecto
         gjahr_ko     TYPE gjahr,
         uuid_nuevo   TYPE char36,    " UUID asignado al doc incorrecto
         accion       TYPE char10,    " CORRECTO/CORREGIDO/BORRADO/MANUAL
         mensaje      TYPE char255,
         fichero_csv  TYPE char200,
         test_mode    TYPE char1,
       END OF gty_resultado.

* Cachés de tablas maestras
TYPES: BEGIN OF gty_t001z_cache,
         paval TYPE t001z-paval,
         bukrs TYPE t001z-bukrs,
       END OF gty_t001z_cache.

TYPES: BEGIN OF gty_lfa1_cache,
         stcd1 TYPE lfa1-stcd1,
         lifnr TYPE lfa1-lifnr,
       END OF gty_lfa1_cache.

TYPES: BEGIN OF gty_kna1_cache,
         stcd1 TYPE kna1-stcd1,
         kunnr TYPE kna1-kunnr,
       END OF gty_kna1_cache.

**********************************************************************
** DATOS GLOBALES
**********************************************************************

* Índice CSV por UUID (clave única → O(1) lookup)
DATA: gt_csv_by_uuid TYPE HASHED TABLE OF gty_csv_rec
                     WITH UNIQUE KEY uuid.

* Todos los CSVs para búsqueda inversa (folio+RFC)
DATA: gt_csv_all TYPE TABLE OF gty_csv_rec.

* UUIDs leídos de STXH (solo duplicados, después de filtrar)
DATA: gt_duplic_docs TYPE TABLE OF gty_uuid_sap.

* ALV resultado
DATA: gt_resultado TYPE TABLE OF gty_resultado,
      gs_resultado TYPE gty_resultado.

* Cachés de maestros
DATA: gt_t001z_cache TYPE HASHED TABLE OF gty_t001z_cache
                     WITH UNIQUE KEY paval.
DATA: gt_lfa1_cache  TYPE HASHED TABLE OF gty_lfa1_cache
                     WITH UNIQUE KEY stcd1.
DATA: gt_kna1_cache  TYPE HASHED TABLE OF gty_kna1_cache
                     WITH UNIQUE KEY stcd1.

* Contadores de resultado
DATA: gv_n_duplic_uuids TYPE i,   " UUIDs duplicados detectados
      gv_corr_auto      TYPE i,   " Grupos corregidos automáticamente
      gv_manual         TYPE i,   " Grupos derivados a revisión manual
      gv_sin_csv        TYPE i.   " UUIDs sin CSV en servidor

**********************************************************************
** PANTALLA DE SELECCIÓN
**********************************************************************
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_t1.
  PARAMETERS: p_sdir TYPE char255.            " Directorio CSV en servidor
  PARAMETERS: p_test AS CHECKBOX DEFAULT 'X'. " Modo simulación
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE gv_t2.
  SELECT-OPTIONS: s_bukrs FOR t001-bukrs,     " Sociedad (opcional)
                  s_gjahr FOR bkpf-gjahr.     " Ejercicio (opcional)
SELECTION-SCREEN END OF BLOCK b2.
