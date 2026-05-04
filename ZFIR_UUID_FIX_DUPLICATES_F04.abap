*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLICATES_F04
*&---------------------------------------------------------------------*
*& Sincronización completa de ZTT_UUID_LOG con STXH (P_RESYNC='X').
*& Registro de ejecución en ZTT_UUID_EXEC.
*& Salida ALV.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_FIX_RESYNC_LOG_COMPLETO
*&---------------------------------------------------------------------*
*& Si P_RESYNC = 'X': recorre STXH en paquetes de P_PKG y para cada
*& doc con UUID verifica que ZTT_UUID_LOG tenga la misma verdad.
*& Si discrepa → actualiza la fila del log.
*& IMPORTANTE: no toca STXH, solo lee. Solo escribe en ZTT_UUID_LOG.
*& Ejecuta COMMIT cada P_COMMIT actualizaciones para no acumular locks.
*&---------------------------------------------------------------------*
FORM frm_fix_resync_log_completo.

  WRITE: / 'P_RESYNC activo: sincronizando ZTT_UUID_LOG con STXH...'.

  DATA: lt_stxh_pkg  TYPE TABLE OF stxh,
        ls_stxh      TYPE stxh,
        lv_tdname    TYPE tdobname,
        lv_uuid_sap  TYPE char36,
        lv_bukrs     TYPE bukrs,
        lv_belnr     TYPE belnr_d,
        lv_gjahr     TYPE gjahr,
        lt_tlines    TYPE TABLE OF tline,
        ls_tline     TYPE tline,
        lv_cnt_total TYPE i,
        lv_cnt_upd   TYPE i,
        lt_zlog_upd  TYPE TABLE OF ztt_uuid_log,
        ls_zlog      TYPE ztt_uuid_log,
        lv_uuid_log  TYPE char36,
        lv_pkg_cnt   TYPE i.

  SELECT COUNT(*) FROM stxh INTO lv_cnt_total
    WHERE tdobject = gc_object
      AND tdid     = gc_tdid
      AND tdspras  = gc_language.

  WRITE: / '  Total STXH a revisar:', lv_cnt_total.
  IF lv_cnt_total = 0. RETURN. ENDIF.

  SELECT tdname
    FROM stxh
    PACKAGE SIZE p_pkg
    INTO TABLE lt_stxh_pkg
    WHERE tdobject = gc_object
      AND tdid     = gc_tdid
      AND tdspras  = gc_language.

    REFRESH: lt_zlog_upd.
    lv_pkg_cnt = lv_pkg_cnt + 1.

    LOOP AT lt_stxh_pkg INTO ls_stxh.
*     Filtros opcionales (s_bukrs / s_gjahr)
      lv_tdname = ls_stxh-tdname.
      lv_bukrs  = lv_tdname(4).
      lv_belnr  = lv_tdname+4(10).
      lv_gjahr  = lv_tdname+14(4).

      IF s_bukrs IS NOT INITIAL AND lv_bukrs NOT IN s_bukrs. CONTINUE. ENDIF.
      IF s_gjahr IS NOT INITIAL AND lv_gjahr NOT IN s_gjahr. CONTINUE. ENDIF.

*     Leer UUID real de STXH
      REFRESH lt_tlines.
      CALL FUNCTION 'READ_TEXT'
        EXPORTING
          id       = gc_tdid
          language = gc_language
          name     = lv_tdname
          object   = gc_object
        TABLES
          lines    = lt_tlines
        EXCEPTIONS
          OTHERS   = 8.

      IF sy-subrc <> 0. CONTINUE. ENDIF.

      READ TABLE lt_tlines INTO ls_tline INDEX 1.
      IF sy-subrc <> 0 OR ls_tline-tdline IS INITIAL. CONTINUE. ENDIF.

      lv_uuid_sap = ls_tline-tdline.
      CONDENSE lv_uuid_sap NO-GAPS.
      TRANSLATE lv_uuid_sap TO UPPER CASE.
      IF strlen( lv_uuid_sap ) <> 36. CONTINUE. ENDIF.

*     Leer UUID actual en ZTT_UUID_LOG (el más reciente con icon OK)
      CLEAR lv_uuid_log.
      SELECT uuid FROM ztt_uuid_log INTO lv_uuid_log
        WHERE bukrs       = lv_bukrs
          AND belnr       = lv_belnr
          AND gjahr       = lv_gjahr
          AND icon_status = gc_icon_ok
        ORDER BY datum_proc DESCENDING uzeit_proc DESCENDING.
        EXIT.
      ENDSELECT.

*     Si no hay diferencia, no es necesario actualizar
      IF lv_uuid_log = lv_uuid_sap. CONTINUE. ENDIF.

*     Actualizar ZTT_UUID_LOG para que refleje la verdad de SAP
      CLEAR ls_zlog.
      ls_zlog-fichero     = |RESYNC_{ sy-datum }|.
      ls_zlog-bukrs       = lv_bukrs.
      ls_zlog-belnr       = lv_belnr.
      ls_zlog-gjahr       = lv_gjahr.
      ls_zlog-uuid        = lv_uuid_sap.
      ls_zlog-uuid_previo = lv_uuid_log.
      ls_zlog-icon_status = gc_icon_ok.
      ls_zlog-datum_proc  = sy-datum.
      ls_zlog-uzeit_proc  = sy-uzeit.
      ls_zlog-uname       = sy-uname.
      CONCATENATE '[RESYNC] UUID en SAP:'
        lv_uuid_sap '(era:' lv_uuid_log ')'
        INTO ls_zlog-mensaje SEPARATED BY space.

      APPEND ls_zlog TO lt_zlog_upd.
      lv_cnt_upd = lv_cnt_upd + 1.

    ENDLOOP.

*   UPDATE batch del paquete
    IF lt_zlog_upd IS NOT INITIAL AND p_test IS INITIAL.
      MODIFY ztt_uuid_log FROM TABLE lt_zlog_upd.
      COMMIT WORK AND WAIT.
    ENDIF.
    FREE: lt_zlog_upd, lt_stxh_pkg.

    IF lv_pkg_cnt MOD 10 = 0.
      WRITE: / '  Paquete RESYNC', lv_pkg_cnt,
             '/ Actualizaciones log:', lv_cnt_upd.
    ENDIF.

    IF p_wait > 0.
      WAIT UP TO p_wait SECONDS.
    ENDIF.

  ENDSELECT.

  WRITE: / '  RESYNC completado. Filas de log actualizadas:', lv_cnt_upd.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_SAVE_EXEC_LOG
*&---------------------------------------------------------------------*
*& Registra la ejecución en ZTT_UUID_EXEC (resumen de contadores).
*&---------------------------------------------------------------------*
FORM frm_fix_save_exec_log.

  DATA: ls_exec TYPE ztt_uuid_exec.

  ls_exec-fichero    = |FIX_DUPLICATES_{ sy-datum }|.
  ls_exec-datum_proc = sy-datum.
  ls_exec-uzeit_proc = sy-uzeit.
  ls_exec-uname      = sy-uname.
  ls_exec-test_mode  = p_test.
  ls_exec-tot_reg    = lines( gt_acciones ).
  ls_exec-tot_ok     = gv_n_reasig + gv_n_ok_win.
  ls_exec-tot_warn   = gv_n_ambig  + gv_n_huerfano.
  ls_exec-tot_err    = gv_n_error.

  IF p_test IS INITIAL.
    INSERT ztt_uuid_exec FROM ls_exec.
    COMMIT WORK AND WAIT.
  ENDIF.

  WRITE: / 'Ejecución registrada en ZTT_UUID_EXEC.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_MOSTRAR_ALV
*&---------------------------------------------------------------------*
FORM frm_fix_mostrar_alv.

  DATA: lo_alv     TYPE REF TO cl_salv_table,
        lo_cols    TYPE REF TO cl_salv_columns_table,
        lo_col     TYPE REF TO cl_salv_column_table,
        lo_funcs   TYPE REF TO cl_salv_functions_list,
        lo_display TYPE REF TO cl_salv_display_settings,
        lx_msg     TYPE REF TO cx_salv_msg.

  IF gt_resultado IS INITIAL.
    WRITE: / 'No hay resultados para mostrar.'.
    RETURN.
  ENDIF.

  WRITE: / '================================================'.
  WRITE: / 'RESUMEN'.
  WRITE: / '================================================'.
  WRITE: / 'UUIDs duplicados detectados:     ', gv_n_duplic.
  WRITE: / 'Documentos afectados:            ', gv_n_docs.
  WRITE: / 'UUID reasignados (CSV correcto): ', gv_n_reasig.
  WRITE: / 'UUID borrados (huérfanos):       ', gv_n_borrado.
  WRITE: / 'Ganadores (sin cambio):          ', gv_n_ok_win.
  WRITE: / 'Ambiguos (revisión manual):      ', gv_n_ambig.
  WRITE: / 'Sin match en CSV:                ', gv_n_huerfano.
  WRITE: / 'Errores de escritura:            ', gv_n_error.
  IF p_test = 'X'.
    WRITE: / '*** MODO SIMULACIÓN — no se modificó ningún dato ***'.
  ENDIF.
  WRITE: / '================================================'.
  SKIP.

  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = gt_resultado ).

    lo_funcs = lo_alv->get_functions( ).
    lo_funcs->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
        lo_col ?= lo_cols->get_column( 'ICON' ).
        lo_col->set_short_text( '' ).
        lo_col->set_output_length( 3 ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    TRY.
        lo_col ?= lo_cols->get_column( 'UUID_ANTERIOR' ).
        lo_col->set_long_text( 'UUID anterior (SAP)' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    TRY.
        lo_col ?= lo_cols->get_column( 'UUID_NUEVO' ).
        lo_col->set_long_text( 'UUID correcto (CSV)' ).
    CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    lo_display = lo_alv->get_display_settings( ).
    IF p_test = 'X'.
      lo_display->set_list_header( 'ZFIR_UUID_FIX_DUPLICATES — MODO SIMULACIÓN' ).
    ELSE.
      lo_display->set_list_header( 'ZFIR_UUID_FIX_DUPLICATES — Resultado aplicado' ).
    ENDIF.
    lo_display->set_striped_pattern( abap_true ).

    lo_alv->display( ).

  CATCH cx_salv_msg INTO lx_msg.
    MESSAGE lx_msg->get_text( ) TYPE 'I'.
  ENDTRY.

ENDFORM.
