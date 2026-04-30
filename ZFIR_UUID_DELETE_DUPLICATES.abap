*&---------------------------------------------------------------------*
*& Report ZFIR_UUID_DELETE_DUPLICATES
*&---------------------------------------------------------------------*
*& Borra TODOS los UUIDs duplicados (sin excepciones).
*&
*& LÓGICA SIMPLE:
*&   1. Detecta UUIDs que aparecen en múltiples documentos.
*&   2. Borra el UUID de TODOS los documentos afectados.
*&   3. No aplica lógica inteligente (borra todo).
*&
*& MODO SIMULACIÓN (P_TEST = 'X'): no borra nada, solo informa.
*&---------------------------------------------------------------------*
REPORT zfir_uuid_delete_duplicates.

INCLUDE <icon>. " <-- Necesario para cargar las constantes de los iconos

*&---------------------------------------------------------------------*
*& TIPOS DE DATOS
*&---------------------------------------------------------------------*
TYPES: BEGIN OF gty_uuid_sap,
         uuid    TYPE char36,
         bukrs   TYPE bukrs,
         belnr   TYPE belnr_d,
         gjahr   TYPE gjahr,
         tdname  TYPE tdobname,
         xblnr   TYPE xblnr1,  " Referencia (folio)
         blart   TYPE blart,   " Clase de documento
       END OF gty_uuid_sap,
       tt_uuid_sap TYPE TABLE OF gty_uuid_sap WITH EMPTY KEY.

TYPES: BEGIN OF gty_resultado,
         icon    TYPE icon_d,
         uuid    TYPE char36,
         bukrs   TYPE bukrs,
         belnr   TYPE belnr_d,
         gjahr   TYPE gjahr,
         xblnr   TYPE xblnr1,
         accion  TYPE char10,
         mensaje TYPE string,
       END OF gty_resultado,
       tt_resultado TYPE TABLE OF gty_resultado WITH EMPTY KEY.

*&---------------------------------------------------------------------*
*& DATOS GLOBALES Y CONSTANTES
*&---------------------------------------------------------------------*
DATA: gt_duplic_docs   TYPE tt_uuid_sap,
      gt_resultado     TYPE tt_resultado,
      gv_n_duplicados  TYPE i,
      gv_n_borrados    TYPE i,
      gv_n_errores     TYPE i.

CONSTANTS: gc_object   TYPE tdobject VALUE 'BELEG',
           gc_tdid     TYPE tdid VALUE 'YUUD',
           gc_language TYPE spras VALUE 'S'.

DATA: gv_bukrs TYPE bukrs,
      gv_gjahr TYPE gjahr.

*&---------------------------------------------------------------------*
*& SELECTION-SCREEN (sin número de pantalla)
*&---------------------------------------------------------------------*
PARAMETERS: p_test AS CHECKBOX DEFAULT 'X'.
SELECT-OPTIONS: s_bukrs FOR gv_bukrs,
                s_gjahr FOR gv_gjahr.

*&---------------------------------------------------------------------*
START-OF-SELECTION.
*&---------------------------------------------------------------------*

* Fase 1: Detectar UUIDs duplicados
  PERFORM frm_detectar_duplicados.

  IF gt_duplic_docs IS INITIAL.
    MESSAGE 'No se encontraron UUIDs duplicados.' TYPE 'I'.
    RETURN.
  ENDIF.

* Fase 2: Borrar TODOS los UUIDs duplicados (sin filtrado)
  PERFORM frm_borrar_uuids.

* Fase 3: Mostrar resultado
  PERFORM frm_mostrar_resultado.

*&---------------------------------------------------------------------*
*& Form FRM_DETECTAR_DUPLICADOS
*&---------------------------------------------------------------------*
FORM frm_detectar_duplicados.

  TYPES: BEGIN OF lty_uuid_cnt,
           uuid  TYPE char36,
           count TYPE i,
         END OF lty_uuid_cnt.

  DATA: lt_uuid_sap  TYPE tt_uuid_sap,
        lt_cnt       TYPE HASHED TABLE OF lty_uuid_cnt
                     WITH UNIQUE KEY uuid,
        ls_cnt       TYPE lty_uuid_cnt,
        lt_dup_uuids TYPE HASHED TABLE OF char36
                     WITH UNIQUE KEY table_line,
        lt_tlines    TYPE TABLE OF tline,
        ls_tline     TYPE tline,
        lv_uuid      TYPE char36,
        lv_bukrs     TYPE bukrs,
        lv_belnr     TYPE belnr_d,
        lv_gjahr     TYPE gjahr.

  REFRESH gt_duplic_docs.
  CLEAR: gv_n_duplicados, gv_n_borrados, gv_n_errores.

* ─── 1. Leer todos los STXH ────────────────────────────────────────
  SELECT tdname
    FROM stxh
    WHERE tdobject = @gc_object
      AND tdid     = @gc_tdid
      AND tdspras  = @gc_language
    INTO TABLE @DATA(lt_stxh).

  IF sy-subrc <> 0 OR lt_stxh IS INITIAL.
    WRITE: / 'No se encontraron textos UUID en STXH.'.
    RETURN.
  ENDIF.

  WRITE: / |Entradas STXH encontradas: { lines( lt_stxh ) }. Leyendo UUIDs...|.

* ─── 2. Para cada STXH: parsear PK, leer UUID y datos de BKPF ─────
  LOOP AT lt_stxh INTO DATA(ls_stxh).

* Parsear TDNAME → BUKRS(4) + BELNR(10) + GJAHR(4)
    lv_bukrs = ls_stxh-tdname(4).
    lv_belnr = ls_stxh-tdname+4(10).
    lv_gjahr = ls_stxh-tdname+14(4).

    IF s_bukrs IS NOT INITIAL AND lv_bukrs NOT IN s_bukrs. CONTINUE. ENDIF.
    IF s_gjahr IS NOT INITIAL AND lv_gjahr NOT IN s_gjahr. CONTINUE. ENDIF.

* Leer XBLNR y BLART desde BKPF (necesarios para lógica Intercompany)
    DATA: lv_xblnr TYPE xblnr1,
          lv_blart TYPE blart.
    SELECT SINGLE xblnr blart
      FROM bkpf
      INTO (lv_xblnr, lv_blart)
      WHERE bukrs = lv_bukrs
        AND belnr = lv_belnr
        AND gjahr = lv_gjahr.
    IF sy-subrc <> 0.
      CLEAR: lv_xblnr, lv_blart.
    ENDIF.

* Leer UUID real con READ_TEXT
    REFRESH lt_tlines.
    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        client   = sy-mandt
        id       = gc_tdid
        language = gc_language
        name     = ls_stxh-tdname
        object   = gc_object
      TABLES
        lines    = lt_tlines
      EXCEPTIONS
        OTHERS   = 8.

    IF sy-subrc <> 0. CONTINUE. ENDIF.

    READ TABLE lt_tlines INTO ls_tline INDEX 1.
    IF sy-subrc <> 0. CONTINUE. ENDIF.

    lv_uuid = ls_tline-tdline.
    CONDENSE lv_uuid NO-GAPS.
    TRANSLATE lv_uuid TO UPPER CASE.

    IF lv_uuid IS INITIAL OR strlen( lv_uuid ) <> 36. CONTINUE. ENDIF.

    DATA(ls_uuid) = VALUE gty_uuid_sap(
      uuid   = lv_uuid
      bukrs  = lv_bukrs
      belnr  = lv_belnr
      gjahr  = lv_gjahr
      tdname = ls_stxh-tdname
      xblnr  = lv_xblnr
      blart  = lv_blart ).
    APPEND ls_uuid TO lt_uuid_sap.

  ENDLOOP.

  IF lt_uuid_sap IS INITIAL.
    WRITE: / 'No hay documentos con UUID para los filtros indicados.'.
    RETURN.
  ENDIF.

* ─── 3. Contar ocurrencias por UUID ────────────────────────────────
  LOOP AT lt_uuid_sap INTO DATA(ls_u).
    READ TABLE lt_cnt INTO ls_cnt WITH TABLE KEY uuid = ls_u-uuid.
    IF sy-subrc = 0.
      ls_cnt-count = ls_cnt-count + 1.
      MODIFY TABLE lt_cnt FROM ls_cnt.
    ELSE.
      ls_cnt-uuid  = ls_u-uuid.
      ls_cnt-count = 1.
      INSERT ls_cnt INTO TABLE lt_cnt.
    ENDIF.
  ENDLOOP.

* ─── 4. Extraer solo los duplicados ────────────────────────────────
  LOOP AT lt_cnt INTO ls_cnt WHERE count > 1.
    INSERT ls_cnt-uuid INTO TABLE lt_dup_uuids.
    gv_n_duplicados = gv_n_duplicados + 1.
  ENDLOOP.

  LOOP AT lt_uuid_sap INTO ls_uuid.
    IF line_exists( lt_dup_uuids[ table_line = ls_uuid-uuid ] ).
      APPEND ls_uuid TO gt_duplic_docs.
    ENDIF.
  ENDLOOP.

  WRITE: / |UUIDs duplicados detectados: { gv_n_duplicados }|.
  WRITE: / |Documentos afectados:       { lines( gt_duplic_docs ) }|.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_BORRAR_UUIDS
*&---------------------------------------------------------------------*
FORM frm_borrar_uuids.

  DATA: lr_tdnames   TYPE RANGE OF tdobname,
        ls_tdname    LIKE LINE OF lr_tdnames,
        lv_deleted   TYPE i,
        lv_total     TYPE i,
        gs_res       TYPE gty_resultado.

  lv_total = lines( gt_duplic_docs ).

* En modo simulación: solo contar
  IF p_test = 'X'.
    LOOP AT gt_duplic_docs INTO DATA(ls_doc).
      CLEAR gs_res.
      gs_res-uuid    = ls_doc-uuid.
      gs_res-bukrs   = ls_doc-bukrs.
      gs_res-belnr   = ls_doc-belnr.
      gs_res-gjahr   = ls_doc-gjahr.
      gs_res-xblnr   = ls_doc-xblnr.
      gs_res-accion  = 'BORRADO'.
      gs_res-mensaje = 'Simulación: se borraría el UUID.'.
      gs_res-icon    = icon_led_yellow.
      gv_n_borrados  = gv_n_borrados + 1.
      APPEND gs_res TO gt_resultado.
    ENDLOOP.
    RETURN.
  ENDIF.

* ─── MODO PRODUCTIVO: DELETE masivo ───────────────────────────────
* Acumular TDNAMEs a borrar en una tabla tipo RANGES
  LOOP AT gt_duplic_docs INTO DATA(ls_doc_delete).
    ls_tdname-sign   = 'I'.
    ls_tdname-option = 'EQ'.
    ls_tdname-low    = ls_doc_delete-tdname.
    APPEND ls_tdname TO lr_tdnames.
  ENDLOOP.

  IF lr_tdnames IS NOT INITIAL.
* ─── SOLUCIÓN AL DUMP: Paquetización para evitar límite de BD ───
    DATA: lr_tdnames_pkg TYPE RANGE OF tdobname,
          lv_idx_from    TYPE i VALUE 1,
          lv_idx_to      TYPE i,
          lv_pkg_size    TYPE i VALUE 2000. " Tamaño del paquete: 2000

    WHILE lv_idx_from <= lines( lr_tdnames ).
      CLEAR lr_tdnames_pkg.
      lv_idx_to = lv_idx_from + lv_pkg_size - 1.

      " Extraemos un paquete de máximo 2000 registros
      APPEND LINES OF lr_tdnames FROM lv_idx_from TO lv_idx_to TO lr_tdnames_pkg.

* Borrar STXH del paquete actual
      DELETE FROM stxh
        WHERE tdobject = gc_object
          AND tdid     = gc_tdid
          AND tdspras  = gc_language
          AND tdname   IN lr_tdnames_pkg.

      lv_deleted = lv_deleted + sy-dbcnt.

* Borrar STXL del paquete actual
      DELETE FROM stxl
        WHERE tdobject = gc_object
          AND tdid     = gc_tdid
          AND tdspras  = gc_language
          AND tdname   IN lr_tdnames_pkg.

      " Avanzamos al siguiente paquete
      lv_idx_from = lv_idx_from + lv_pkg_size.
    ENDWHILE.
  ENDIF.

* UN SOLO COMMIT al final
  COMMIT WORK AND WAIT.

* Registrar resultados: todos como OK
  LOOP AT gt_duplic_docs INTO DATA(ls_doc_result).
    CLEAR gs_res.
    gs_res-uuid    = ls_doc_result-uuid.
    gs_res-bukrs   = ls_doc_result-bukrs.
    gs_res-belnr   = ls_doc_result-belnr.
    gs_res-gjahr   = ls_doc_result-gjahr.
    gs_res-xblnr   = ls_doc_result-xblnr.
    gs_res-accion  = 'BORRADO'.
    gs_res-mensaje = 'UUID eliminado correctamente.'.
    gs_res-icon    = icon_led_green.
    gv_n_borrados  = gv_n_borrados + 1.
    APPEND gs_res TO gt_resultado.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_RESULTADO
*&---------------------------------------------------------------------*
FORM frm_mostrar_resultado.

  DATA: lo_alv     TYPE REF TO cl_salv_table,
        lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lo_display TYPE REF TO cl_salv_display_settings,
        lx_msg     TYPE REF TO cx_salv_msg.

* ─── Resumen ──────────────────────────────────────────────────────
  SKIP.
  WRITE: / '===== ZFIR_UUID_DELETE_DUPLICATES - RESUMEN ====='.
  WRITE: / |UUIDs duplicados detectados: { gv_n_duplicados }|.
  WRITE: / |Documentos afectados:       { lines( gt_duplic_docs ) }|.
  WRITE: / |Borrados correctamente:     { gv_n_borrados }|.
  WRITE: / |Errores:                    { gv_n_errores }|.
  IF p_test = 'X'.
    WRITE: / '*** MODO SIMULACIÓN — no se borraron los UUID ***'.
  ENDIF.
  SKIP.

  IF gt_resultado IS INITIAL.
    WRITE: / 'No hay resultados.'.
    RETURN.
  ENDIF.

* ─── Crear ALV ────────────────────────────────────────────────────
  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = gt_resultado ).
    CATCH cx_salv_msg INTO lx_msg.
      MESSAGE lx_msg->get_text( ) TYPE 'I'.
      RETURN.
  ENDTRY.

  lo_funcs = lo_alv->get_functions( ).
  lo_funcs->set_all( abap_true ).

  lo_cols = lo_alv->get_columns( ).
  lo_cols->set_optimize( abap_true ).

* ─── Configurar columnas ──────────────────────────────────────────
  TRY.
      lo_col ?= lo_cols->get_column( 'ICON' ).
      lo_col->set_short_text( '' ).
      lo_col->set_output_length( 3 ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'UUID' ).
      lo_col->set_long_text( 'UUID Duplicado' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BUKRS' ).
      lo_col->set_long_text( 'Sociedad' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BELNR' ).
      lo_col->set_long_text( 'Documento' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'GJAHR' ).
      lo_col->set_long_text( 'Ejercicio' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'XBLNR' ).
      lo_col->set_long_text( 'Referencia' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'ACCION' ).
      lo_col->set_long_text( 'Acción' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'MENSAJE' ).
      lo_col->set_long_text( 'Detalle' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  lo_display = lo_alv->get_display_settings( ).
  IF p_test = 'X'.
    lo_display->set_list_header( 'ZFIR_UUID_DELETE_DUPLICATES — MODO SIMULACIÓN' ).
  ELSE.
    lo_display->set_list_header( 'ZFIR_UUID_DELETE_DUPLICATES — Eliminación ejecutada' ).
  ENDIF.
  lo_display->set_striped_pattern( abap_true ).

  lo_alv->display( ).

ENDFORM.
