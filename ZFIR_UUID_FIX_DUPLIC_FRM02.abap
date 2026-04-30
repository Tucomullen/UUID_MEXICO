*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLIC_FRM02
*&---------------------------------------------------------------------*
*& Fase 3: Corrección de documentos con UUID duplicado incorrecto.
*& Fase 4: Presentación ALV del resultado consolidado.
*&
*& Formas contenidas:
*&   frm_corregir_documento   → SAVE_TEXT / DELETE_TEXT + auditoría
*&   frm_actualizar_log_ok    → marca el doc correcto en ZTT_UUID_LOG
*&   frm_actualizar_log_ko    → actualiza el doc incorrecto en ZTT_UUID_LOG
*&   frm_grabar_auditoria     → INSERT en ZTT_UUID_CORREC
*&   frm_mostrar_resultado_alv → ALV con gt_resultado
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_CORREGIR_DOCUMENTO
*&---------------------------------------------------------------------*
*& Ejecuta la corrección sobre el documento incorrecto (bukrs_ko/belnr_ko):
*&
*&   Caso B1 (ev_found='X'): asignar UUID correcto → SAVE_TEXT
*&   Caso B2 (ev_found='' ): sin UUID en CSV      → DELETE_TEXT
*&   Caso B3 (ev_found='M'): múltiples candidatos  → MANUAL (no toca nada)
*&
*& En modo simulación (P_TEST='X') no modifica SAP ni ZTT_UUID_LOG,
*& solo registra la acción que se ejecutaría en gt_resultado.
*&---------------------------------------------------------------------*
FORM frm_corregir_documento
  USING    iv_uuid_dup  TYPE char36    " UUID duplicado (el que hay ahora)
           iv_bukrs_ko  TYPE bukrs     " Sociedad doc incorrecto
           iv_belnr_ko  TYPE belnr_d   " Documento incorrecto
           iv_gjahr_ko  TYPE gjahr     " Ejercicio doc incorrecto
           iv_bukrs_ok  TYPE bukrs     " Sociedad doc correcto
           iv_belnr_ok  TYPE belnr_d   " Documento correcto
           iv_gjahr_ok  TYPE gjahr     " Ejercicio doc correcto
           iv_uuid_nvo  TYPE char36    " UUID correcto para el KO (si se encontró)
           iv_fich_nvo  TYPE string    " Fichero CSV del UUID nuevo
           iv_found_nvo TYPE c         " 'X'=único / 'M'=múltiple / ''=ninguno
           iv_fich_dup  TYPE string.   " Fichero CSV del UUID duplicado

  DATA: ls_header   TYPE thead,
        lt_lines    TYPE TABLE OF tline,
        ls_line     TYPE tline,
        lv_tdname   TYPE tdobname,
        lv_accion   TYPE char10,
        lv_mensaje  TYPE char255,
        lv_icon     TYPE icon_d,
        lv_subrc    TYPE sysubrc.

* ── Determinar acción según resultado de búsqueda inversa ─────────────
  CASE iv_found_nvo.
    WHEN 'X'.
      lv_accion  = 'CORREGIDO'.
      lv_mensaje = |UUID corregido: { iv_uuid_nvo }|.
      lv_icon    = gc_icon_ok.
    WHEN ''.
      lv_accion  = 'NO_ENCONTRADO'.
      lv_mensaje = 'UUID no encontrado en CSVs del servidor para este documento.'.
      lv_icon    = gc_icon_err.
    WHEN OTHERS.
      lv_accion  = 'ERROR'.
      lv_mensaje = 'Error desconocido en búsqueda de UUID.'.
      lv_icon    = gc_icon_err.
  ENDCASE.

* ── Registrar en gt_resultado (siempre, también en modo simulación) ───
  CLEAR gs_resultado.
  gs_resultado-icon        = lv_icon.
  gs_resultado-uuid        = iv_uuid_dup.
  gs_resultado-bukrs_ok    = iv_bukrs_ok.
  gs_resultado-belnr_ok    = iv_belnr_ok.
  gs_resultado-gjahr_ok    = iv_gjahr_ok.
  gs_resultado-bukrs_ko    = iv_bukrs_ko.
  gs_resultado-belnr_ko    = iv_belnr_ko.
  gs_resultado-gjahr_ko    = iv_gjahr_ko.
  gs_resultado-uuid_nuevo  = iv_uuid_nvo.
  gs_resultado-accion      = lv_accion.
  gs_resultado-mensaje     = lv_mensaje.
  gs_resultado-fichero_csv = iv_fich_dup.
  gs_resultado-test_mode   = p_test.
  APPEND gs_resultado TO gt_resultado.

* ── En caso NO_ENCONTRADO: no hay nada más que hacer, solo reportar ───
  IF lv_accion = 'NO_ENCONTRADO' OR lv_accion = 'ERROR'.
    RETURN.
  ENDIF.

* ── En modo simulación: solo informar, no modificar SAP ───────────────
  IF p_test = 'X'.
    RETURN.
  ENDIF.

* ── Construir TDNAME: BUKRS(4) + BELNR(10) + GJAHR(4) ────────────────
  CONCATENATE iv_bukrs_ko iv_belnr_ko iv_gjahr_ko INTO lv_tdname.

  CLEAR ls_header.
  ls_header-tdobject = gc_object.
  ls_header-tdname   = lv_tdname.
  ls_header-tdid     = gc_tdid.
  ls_header-tdspras  = gc_language.

* ── Caso B1: asignar UUID correcto (SAVE_TEXT) ────────────────────────
  IF lv_accion = 'CORREGIDO'.

    REFRESH lt_lines.
    CLEAR   ls_line.
    ls_line-tdformat = '*'.
    ls_line-tdline   = iv_uuid_nvo.
    APPEND ls_line TO lt_lines.

    CALL FUNCTION 'SAVE_TEXT'
      EXPORTING
        header          = ls_header
        insert          = space       " Actualizar si existe
        savemode_direct = 'X'
      TABLES
        lines           = lt_lines
      EXCEPTIONS
        id              = 1
        language        = 2
        name            = 3
        object          = 4
        OTHERS          = 5.

    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      gs_resultado-icon    = gc_icon_err.
      gs_resultado-mensaje = |Error SAVE_TEXT sy-subrc={ lv_subrc }. { lv_mensaje }|.
      MODIFY gt_resultado FROM gs_resultado INDEX lines( gt_resultado ).
      RETURN.
    ENDIF.

* ── Caso B2: eliminar UUID incorrecto (DELETE_TEXT) ───────────────────
  ELSEIF lv_accion = 'BORRADO'.

    CALL FUNCTION 'DELETE_TEXT'
      EXPORTING
        id       = gc_tdid
        language = gc_language
        name     = lv_tdname
        object   = gc_object
      EXCEPTIONS
        not_found = 1
        OTHERS    = 2.

    lv_subrc = sy-subrc.

    IF lv_subrc <> 0 AND lv_subrc <> 1.  " 1 = not_found es aceptable
      gs_resultado-icon    = gc_icon_err.
      gs_resultado-mensaje = |Error DELETE_TEXT sy-subrc={ lv_subrc }. { lv_mensaje }|.
      MODIFY gt_resultado FROM gs_resultado INDEX lines( gt_resultado ).
      RETURN.
    ENDIF.

  ENDIF.

* ── Actualizar ZTT_UUID_LOG y grabar auditoría ────────────────────────
  PERFORM frm_actualizar_log_ko
    USING iv_bukrs_ko iv_belnr_ko iv_gjahr_ko
          iv_uuid_dup iv_uuid_nvo lv_accion lv_mensaje.

  PERFORM frm_grabar_auditoria
    USING iv_uuid_dup
          iv_bukrs_ko  iv_belnr_ko  iv_gjahr_ko
          iv_bukrs_ok  iv_belnr_ok  iv_gjahr_ok
          iv_uuid_nvo  lv_accion
          iv_fich_dup.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_ACTUALIZAR_LOG_OK
*&---------------------------------------------------------------------*
*& Actualiza ZTT_UUID_LOG para el documento CORRECTO del grupo:
*& marca el semáforo verde y añade una nota en el mensaje.
*&---------------------------------------------------------------------*
FORM frm_actualizar_log_ok
  USING iv_uuid  TYPE char36
        iv_bukrs TYPE bukrs
        iv_belnr TYPE belnr_d
        iv_gjahr TYPE gjahr
        iv_fich  TYPE string.

  UPDATE ztt_uuid_log
    SET icon_status = @gc_icon_ok,
        mensaje     = @( |[FIX-DUPLIC OK] UUID verificado como correcto. { iv_fich }| )
    WHERE bukrs  = @iv_bukrs
      AND belnr  = @iv_belnr
      AND gjahr  = @iv_gjahr
      AND uuid   = @iv_uuid.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_ACTUALIZAR_LOG_KO
*&---------------------------------------------------------------------*
*& Actualiza ZTT_UUID_LOG para el documento INCORRECTO del grupo:
*& actualiza el UUID al nuevo valor (o vacío si se borró) y el mensaje.
*&---------------------------------------------------------------------*
FORM frm_actualizar_log_ko
  USING iv_bukrs    TYPE bukrs
        iv_belnr    TYPE belnr_d
        iv_gjahr    TYPE gjahr
        iv_uuid_old TYPE char36    " UUID duplicado que tenía
        iv_uuid_new TYPE char36    " UUID nuevo asignado (vacío si no encontrado)
        iv_accion   TYPE char10
        iv_mensaje  TYPE char255.

  DATA: lv_icon TYPE icon_d.

  CASE iv_accion.
    WHEN 'CORREGIDO'.      lv_icon = gc_icon_ok.
    WHEN 'BORRADO'.        lv_icon = gc_icon_warn.
    WHEN 'NO_ENCONTRADO'.  lv_icon = gc_icon_err.
    WHEN 'ERROR'.          lv_icon = gc_icon_err.
    WHEN OTHERS.           lv_icon = gc_icon_err.
  ENDCASE.

  UPDATE ztt_uuid_log
    SET icon_status = @lv_icon,
        uuid        = @iv_uuid_new,
        mensaje     = @( |[FIX-DUPLIC { iv_accion }] { iv_mensaje }| )
    WHERE bukrs  = @iv_bukrs
      AND belnr  = @iv_belnr
      AND gjahr  = @iv_gjahr
      AND uuid   = @iv_uuid_old.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_GRABAR_AUDITORIA
*&---------------------------------------------------------------------*
*& Inserta un registro en ZTT_UUID_CORREC para trazabilidad completa.
*& Permite rollback manual posterior (repetir SAVE_TEXT con uuid_old).
*&---------------------------------------------------------------------*
FORM frm_grabar_auditoria
  USING iv_uuid_old TYPE char36
        iv_bukrs_ko TYPE bukrs
        iv_belnr_ko TYPE belnr_d
        iv_gjahr_ko TYPE gjahr
        iv_bukrs_ok TYPE bukrs
        iv_belnr_ok TYPE belnr_d
        iv_gjahr_ok TYPE gjahr
        iv_uuid_new TYPE char36
        iv_accion   TYPE char10
        iv_fichero  TYPE string.

  DATA: ls_correc TYPE ztt_uuid_correc.

  CLEAR ls_correc.
  ls_correc-uuid       = iv_uuid_old.
  ls_correc-bukrs_ko   = iv_bukrs_ko.
  ls_correc-belnr_ko   = iv_belnr_ko.
  ls_correc-gjahr_ko   = iv_gjahr_ko.
  ls_correc-bukrs_ok   = iv_bukrs_ok.
  ls_correc-belnr_ok   = iv_belnr_ok.
  ls_correc-gjahr_ok   = iv_gjahr_ok.
  ls_correc-uuid_nuevo = iv_uuid_new.
  ls_correc-accion     = iv_accion.
  ls_correc-datum      = sy-datum.
  ls_correc-uzeit      = sy-uzeit.
  ls_correc-uname      = sy-uname.
  ls_correc-fichero_csv = iv_fichero.
  ls_correc-test_mode  = p_test.

  INSERT ztt_uuid_correc FROM ls_correc.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_RESULTADO_ALV
*&---------------------------------------------------------------------*
*& Muestra gt_resultado en un ALV cl_salv_table con iconos y etiquetas.
*& Al final imprime el resumen en WRITE.
*&---------------------------------------------------------------------*
FORM frm_mostrar_resultado_alv.

  DATA: lo_alv     TYPE REF TO cl_salv_table,
        lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lo_display TYPE REF TO cl_salv_display_settings,
        lx_msg     TYPE REF TO cx_salv_msg.

* ── Resumen antes del ALV (visible en spool/background) ───────────────
  SKIP.
  WRITE: / '===== RESUMEN ZFIR_UUID_FIX_DUPLIC ====='.
  WRITE: / |UUIDs duplicados detectados : { gv_n_duplic_uuids }|.
  WRITE: / |Grupos corregidos auto      : { gv_corr_auto }|.
  WRITE: / |Grupos con revisión manual  : { gv_manual }|.
  WRITE: / |UUIDs sin CSV en servidor   : { gv_sin_csv }|.
  IF p_test = 'X'.
    WRITE: / '*** MODO SIMULACIÓN — ningún cambio grabado en SAP ***'.
  ENDIF.
  SKIP.

  IF gt_resultado IS INITIAL.
    WRITE: / 'No hay registros en el resultado.'.
    RETURN.
  ENDIF.

* ── Crear ALV ─────────────────────────────────────────────────────────
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

* ── Funciones estándar (ordenar, filtrar, exportar) ───────────────────
  lo_funcs = lo_alv->get_functions( ).
  lo_funcs->set_all( abap_true ).

* ── Configuración de columnas ─────────────────────────────────────────
  lo_cols = lo_alv->get_columns( ).
  lo_cols->set_optimize( abap_true ).

  TRY.
      lo_col ?= lo_cols->get_column( 'ICON' ).
      lo_col->set_short_text( '' ).
      lo_col->set_medium_text( '' ).
      lo_col->set_long_text( 'St' ).
      lo_col->set_output_length( 3 ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'UUID' ).
      lo_col->set_long_text( 'UUID duplicado' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BUKRS_OK' ).
      lo_col->set_long_text( 'Soc.OK' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BELNR_OK' ).
      lo_col->set_long_text( 'Doc.OK' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'GJAHR_OK' ).
      lo_col->set_long_text( 'Ej.OK' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BUKRS_KO' ).
      lo_col->set_long_text( 'Soc.KO' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'BELNR_KO' ).
      lo_col->set_long_text( 'Doc.KO' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'GJAHR_KO' ).
      lo_col->set_long_text( 'Ej.KO' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'UUID_NUEVO' ).
      lo_col->set_long_text( 'UUID asignado al KO' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'ACCION' ).
      lo_col->set_long_text( 'Acción' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'MENSAJE' ).
      lo_col->set_long_text( 'Descripción' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'FICHERO_CSV' ).
      lo_col->set_long_text( 'Fichero CSV' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

  TRY.
      lo_col ?= lo_cols->get_column( 'TEST_MODE' ).
      lo_col->set_long_text( 'Simulación' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
  ENDTRY.

* ── Título del ALV ────────────────────────────────────────────────────
  lo_display = lo_alv->get_display_settings( ).
  IF p_test = 'X'.
    lo_display->set_list_header( 'ZFIR_UUID_FIX_DUPLIC — MODO SIMULACIÓN' ).
  ELSE.
    lo_display->set_list_header( 'ZFIR_UUID_FIX_DUPLIC — Correcciones ejecutadas' ).
  ENDIF.
  lo_display->set_striped_pattern( abap_true ).

* ── Mostrar ───────────────────────────────────────────────────────────
  lo_alv->display( ).

ENDFORM.
