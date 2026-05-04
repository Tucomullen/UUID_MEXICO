*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLICATES_TOP
*&---------------------------------------------------------------------*
*& Tipos, datos globales, constantes y pantalla de selección
*&---------------------------------------------------------------------*

TABLES: bkpf.

**********************************************************************
** CONSTANTES                                                       **
**********************************************************************
CONSTANTS:
  gc_object    TYPE tdobject VALUE 'BELEG',
  gc_tdid      TYPE tdid     VALUE 'YUUD',
  gc_language  TYPE spras    VALUE 'S',
  gc_party     TYPE char10   VALUE 'MX_RFC',
  gc_icon_ok   TYPE icon_d   VALUE '@08@',
  gc_icon_warn TYPE icon_d   VALUE '@09@',
  gc_icon_err  TYPE icon_d   VALUE '@0A@',

  gc_acc_reasig  TYPE char15  VALUE 'REASIGNADO',
  gc_acc_borrar  TYPE char15  VALUE 'BORRADO',
  gc_acc_ganador TYPE char15  VALUE 'OK_GANADOR',
  gc_acc_ambig   TYPE char15  VALUE 'AMBIGUO',
  gc_acc_huerf   TYPE char15  VALUE 'HUERFANO',
  gc_acc_errw    TYPE char15  VALUE 'ERROR_ESCRIT'.

**********************************************************************
** TIPOS                                                            **
**********************************************************************

* Documento duplicado (enriquecido con metadatos de BKPF/BSEG/LOG)
TYPES: BEGIN OF gty_dup_doc,
         bukrs        TYPE bukrs,
         belnr        TYPE belnr_d,
         gjahr        TYPE gjahr,
         tdname       TYPE tdobname,     " clave STXH: bukrs+belnr+gjahr sin espacios
         uuid_act     TYPE char36,       " UUID actual en STXH (verificado con READ_TEXT)
         rfc_emisor   TYPE char13,
         rfc_receptor TYPE char13,
         folio        TYPE char20,
         total_num    TYPE p DECIMALS 0, " Total entero truncado (de BSEG-WRBTR)
         tipo_fac     TYPE char1,        " C=Compra V=Venta I=Interco
         tipo_cfdi    TYPE char1,        " I E P T
         xblnr        TYPE xblnr1,
         bldat        TYPE bldat,
         budat        TYPE budat,
         blart        TYPE blart,
       END OF gty_dup_doc.

* Entrada de índice CSV (una línea de CSV parseada y filtrada)
TYPES: BEGIN OF gty_csv_idx,
         rfc_emisor      TYPE char13,
         rfc_receptor    TYPE char13,
         folio           TYPE char20,
         gjahr           TYPE gjahr,
         total_num       TYPE p DECIMALS 0,
         tipocomprobante TYPE char1,
         uuid            TYPE char36,
       END OF gty_csv_idx.

* Acción determinada para cada documento duplicado
TYPES: BEGIN OF gty_accion,
         bukrs        TYPE bukrs,
         belnr        TYPE belnr_d,
         gjahr        TYPE gjahr,
         tdname       TYPE tdobname,
         uuid_act     TYPE char36,
         uuid_nuevo   TYPE char36,   " vacío si BORRAR u OK_GANADOR
         accion       TYPE char15,
         rfc_emisor   TYPE char13,
         rfc_receptor TYPE char13,
         folio        TYPE char20,
         tipo_fac     TYPE char1,
         tipo_cfdi    TYPE char1,
         budat        TYPE budat,
         blart        TYPE blart,
         mensaje      TYPE char255,
       END OF gty_accion.

* Fila del ALV resultado
TYPES: BEGIN OF gty_resultado,
         icon          TYPE icon_d,
         bukrs         TYPE bukrs,
         belnr         TYPE belnr_d,
         gjahr         TYPE gjahr,
         uuid_anterior TYPE char36,
         uuid_nuevo    TYPE char36,
         accion        TYPE char15,
         tipo_fac      TYPE char1,
         tipo_cfdi     TYPE char1,
         rfc_emisor    TYPE char13,
         rfc_receptor  TYPE char13,
         folio         TYPE char20,
         budat         TYPE budat,
         blart         TYPE blart,
         mensaje       TYPE char255,
       END OF gty_resultado.

* Lista de ficheros CSV del servidor
TYPES: BEGIN OF gty_server_file_fx,
         fullpath TYPE string,
         filename TYPE string,
       END OF gty_server_file_fx.

* Registro intermedio de detección: doc + UUID confirmado en STXH
TYPES: BEGIN OF gty_stxh_raw,
         uuid   TYPE char36,
         bukrs  TYPE bukrs,
         belnr  TYPE belnr_d,
         gjahr  TYPE gjahr,
         tdname TYPE tdobname,
       END OF gty_stxh_raw,
       gtt_stxh_raw TYPE TABLE OF gty_stxh_raw WITH EMPTY KEY.

* Caché T001Z (RFC → BUKRS)
TYPES: BEGIN OF gty_t001z_c,
         paval TYPE t001z-paval,
         bukrs TYPE t001z-bukrs,
       END OF gty_t001z_c.

* Caché LFA1 (RFC → LIFNR)
TYPES: BEGIN OF gty_lfa1_c,
         stcd1 TYPE lfa1-stcd1,
         lifnr TYPE lfa1-lifnr,
       END OF gty_lfa1_c.

* Caché KNA1 (RFC → KUNNR)
TYPES: BEGIN OF gty_kna1_c,
         stcd1 TYPE kna1-stcd1,
         kunnr TYPE kna1-kunnr,
       END OF gty_kna1_c.

**********************************************************************
** DATOS GLOBALES                                                   **
**********************************************************************

* Cachés maestras
DATA: gt_t001z_c TYPE HASHED TABLE OF gty_t001z_c WITH UNIQUE KEY paval,
      gt_lfa1_c  TYPE HASHED TABLE OF gty_lfa1_c  WITH UNIQUE KEY stcd1,
      gt_kna1_c  TYPE HASHED TABLE OF gty_kna1_c  WITH UNIQUE KEY stcd1.

* Documentos duplicados detectados y enriquecidos
DATA: gt_dup_docs TYPE TABLE OF gty_dup_doc.

* Índice CSV (SORTED para búsqueda eficiente por rfc_emisor+rfc_receptor+folio+gjahr)
DATA: gt_csv_idx TYPE SORTED TABLE OF gty_csv_idx
                 WITH NON-UNIQUE KEY rfc_emisor rfc_receptor folio gjahr.

* RFCs relevantes (emisores/receptores implicados en duplicados) — HASHED O(1)
DATA: gt_rfcs_rel TYPE HASHED TABLE OF char13 WITH UNIQUE KEY table_line.

* Acciones resueltas
DATA: gt_acciones TYPE TABLE OF gty_accion.

* Resultados para ALV
DATA: gt_resultado TYPE TABLE OF gty_resultado.

* Contadores
DATA: gv_n_duplic   TYPE i,   " UUIDs con duplicidad detectados
      gv_n_docs     TYPE i,   " Documentos afectados
      gv_n_reasig   TYPE i,   " UUID reasignado (CSV dice otro UUID)
      gv_n_borrado  TYPE i,   " UUID borrado (huérfano)
      gv_n_ok_win   TYPE i,   " Ganador (CSV confirma UUID actual)
      gv_n_ambig    TYPE i,   " Ambiguo (varios UUID en CSV)
      gv_n_huerfano TYPE i,   " Sin match en CSV
      gv_n_error    TYPE i.   " Error de escritura

**********************************************************************
** PANTALLA DE SELECCIÓN                                            **
**********************************************************************
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
  PARAMETERS: p_sdir TYPE char255.                   " Directorio AL11
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  SELECT-OPTIONS: s_bukrs FOR bkpf-bukrs,
                  s_gjahr FOR bkpf-gjahr.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS: p_test   AS CHECKBOX DEFAULT 'X',      " Modo simulación
              p_resync AS CHECKBOX DEFAULT ' '.       " Sincronizar también filas OK
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-b04.
  PARAMETERS: p_pkg    TYPE i DEFAULT 500,            " Paquete detección/enriquec.
              p_commit TYPE i DEFAULT 100,             " COMMIT cada N escrituras
              p_wait   TYPE i DEFAULT 1.               " Pausa entre paquetes (seg)
SELECTION-SCREEN END OF BLOCK b4.
