*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM01
*&---------------------------------------------------------------------*
*& SELECT de ZTT_UUID_LOG y todas las agregaciones en memoria
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_CARGAR_DATOS
*&---------------------------------------------------------------------*
FORM frm_cargar_datos.
  PERFORM frm_leer_ztable.
  PERFORM frm_agregar_kpis.
  PERFORM frm_agregar_por_bukrs.
  PERFORM frm_agregar_por_mes.
  PERFORM frm_agregar_errores.
  gt_detail = gt_zlog_raw.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_LEER_ZTABLE
*&---------------------------------------------------------------------*
*& Lee ZTT_UUID_LOG aplicando los filtros de la selection screen
*&---------------------------------------------------------------------*
FORM frm_leer_ztable.

  REFRESH gt_zlog_raw.

  SELECT *
    FROM ztt_uuid_log
    INTO TABLE gt_zlog_raw
    WHERE datum_proc IN so_datum
      AND bukrs      IN so_bukrs
      AND gjahr      IN so_gjahr
      AND monat      IN so_monat
      AND uname      IN so_uname.

* Si NO es modo simulación, excluir registros de test
  IF p_test IS INITIAL.
    DELETE gt_zlog_raw WHERE test_mode <> ' '.
  ENDIF.

  IF gt_zlog_raw IS INITIAL.
    REFRESH gt_zlog_raw.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_AGREGAR_KPIS
*&---------------------------------------------------------------------*
*& Calcula KPIs globales sobre gt_zlog_raw
*&---------------------------------------------------------------------*
FORM frm_agregar_kpis.

  DATA: ls_raw     TYPE ztt_uuid_log,
        lt_uuid    TYPE TABLE OF char36,
        lv_uuid    TYPE char36,
        lt_exec    TYPE TABLE OF char50,
        lv_exec    TYPE char50.

  CLEAR gs_kpi.

  LOOP AT gt_zlog_raw INTO ls_raw.
    gs_kpi-tot_reg = gs_kpi-tot_reg + 1.
    CASE ls_raw-icon_status.
      WHEN '@08@'. gs_kpi-tot_ok   = gs_kpi-tot_ok   + 1.
      WHEN '@09@'. gs_kpi-tot_warn = gs_kpi-tot_warn  + 1.
      WHEN '@0A@'. gs_kpi-tot_err  = gs_kpi-tot_err   + 1.
    ENDCASE.
*   Acumular UUIDs únicos
    IF ls_raw-uuid IS NOT INITIAL.
      APPEND ls_raw-uuid TO lt_uuid.
    ENDIF.
*   Acumular ejecuciones únicas (datum_proc + uzeit_proc + uname)
    CONCATENATE ls_raw-datum_proc ls_raw-uzeit_proc ls_raw-uname
      INTO lv_exec.
    APPEND lv_exec TO lt_exec.
  ENDLOOP.

* UUIDs únicos
  SORT lt_uuid.
  DELETE ADJACENT DUPLICATES FROM lt_uuid.
  gs_kpi-num_uuid = lines( lt_uuid ).

* Ejecuciones únicas
  SORT lt_exec.
  DELETE ADJACENT DUPLICATES FROM lt_exec.
  gs_kpi-num_exec = lines( lt_exec ).

* Porcentajes
  IF gs_kpi-tot_reg > 0.
    gs_kpi-pct_ok  = ( gs_kpi-tot_ok  * 100 ) / gs_kpi-tot_reg.
    gs_kpi-pct_err = ( gs_kpi-tot_err * 100 ) / gs_kpi-tot_reg.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_AGREGAR_POR_BUKRS
*&---------------------------------------------------------------------*
*& Agrupa por sociedad, calcula % OK y determina semáforo de color
*&---------------------------------------------------------------------*
FORM frm_agregar_por_bukrs.

  DATA: ls_raw     TYPE ztt_uuid_log,
        ls_bukrs   TYPE gty_by_bukrs,
        lv_butxt   TYPE butxt.

  REFRESH gt_by_bukrs.

  LOOP AT gt_zlog_raw INTO ls_raw.
    READ TABLE gt_by_bukrs INTO ls_bukrs
      WITH KEY bukrs = ls_raw-bukrs.
    IF sy-subrc <> 0.
      CLEAR ls_bukrs.
      ls_bukrs-bukrs = ls_raw-bukrs.
    ENDIF.

    ls_bukrs-tot_reg = ls_bukrs-tot_reg + 1.
    CASE ls_raw-icon_status.
      WHEN '@08@'. ls_bukrs-tot_ok   = ls_bukrs-tot_ok   + 1.
      WHEN '@09@'. ls_bukrs-tot_warn = ls_bukrs-tot_warn  + 1.
      WHEN '@0A@'. ls_bukrs-tot_err  = ls_bukrs-tot_err   + 1.
    ENDCASE.

    IF sy-subrc = 0.
      MODIFY gt_by_bukrs FROM ls_bukrs
        TRANSPORTING tot_reg tot_ok tot_warn tot_err
        WHERE bukrs = ls_raw-bukrs.
    ELSE.
      APPEND ls_bukrs TO gt_by_bukrs.
    ENDIF.
  ENDLOOP.

* Calcular % OK, semáforo y enriquecer con descripción sociedad
  LOOP AT gt_by_bukrs INTO ls_bukrs.
    IF ls_bukrs-tot_reg > 0.
      ls_bukrs-pct_ok = ( ls_bukrs-tot_ok * 100 ) / ls_bukrs-tot_reg.
    ENDIF.
    IF ls_bukrs-pct_ok >= 95.
      ls_bukrs-light = 'C300'.   " Verde
    ELSEIF ls_bukrs-pct_ok >= 80.
      ls_bukrs-light = 'C200'.   " Amarillo
    ELSE.
      ls_bukrs-light = 'C100'.   " Rojo
    ENDIF.
    SELECT SINGLE butxt FROM t001 INTO ls_bukrs-butxt
      WHERE bukrs = ls_bukrs-bukrs.
    MODIFY gt_by_bukrs FROM ls_bukrs.
  ENDLOOP.

  SORT gt_by_bukrs BY bukrs.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_AGREGAR_POR_MES
*&---------------------------------------------------------------------*
*& Agrupa por ejercicio + mes, construye campo periodo 'AAAA/MM'
*&---------------------------------------------------------------------*
FORM frm_agregar_por_mes.

  DATA: ls_raw   TYPE ztt_uuid_log,
        ls_month TYPE gty_by_month.

  REFRESH gt_by_month.

  LOOP AT gt_zlog_raw INTO ls_raw.
    IF ls_raw-gjahr IS INITIAL AND ls_raw-monat IS INITIAL.
      CONTINUE.
    ENDIF.

    READ TABLE gt_by_month INTO ls_month
      WITH KEY gjahr = ls_raw-gjahr monat = ls_raw-monat.
    IF sy-subrc <> 0.
      CLEAR ls_month.
      ls_month-gjahr = ls_raw-gjahr.
      ls_month-monat = ls_raw-monat.
      CONCATENATE ls_raw-gjahr '/' ls_raw-monat INTO ls_month-periodo.
    ENDIF.

    ls_month-tot_reg = ls_month-tot_reg + 1.
    CASE ls_raw-icon_status.
      WHEN '@08@'. ls_month-tot_ok   = ls_month-tot_ok   + 1.
      WHEN '@09@'. ls_month-tot_warn = ls_month-tot_warn  + 1.
      WHEN '@0A@'. ls_month-tot_err  = ls_month-tot_err   + 1.
    ENDCASE.

    IF sy-subrc = 0.
      MODIFY gt_by_month FROM ls_month
        TRANSPORTING tot_reg tot_ok tot_warn tot_err
        WHERE gjahr = ls_raw-gjahr AND monat = ls_raw-monat.
    ELSE.
      APPEND ls_month TO gt_by_month.
    ENDIF.
  ENDLOOP.

  SORT gt_by_month BY gjahr monat.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_AGREGAR_ERRORES
*&---------------------------------------------------------------------*
*& Agrupa errores y warnings por mensaje+bukrs, ordena por frecuencia
*&---------------------------------------------------------------------*
FORM frm_agregar_errores.

  DATA: ls_raw  TYPE ztt_uuid_log,
        ls_err  TYPE gty_errors.

  REFRESH gt_errors.

  LOOP AT gt_zlog_raw INTO ls_raw
    WHERE icon_status = '@0A@' OR icon_status = '@09@'.

    IF ls_raw-icon_status = '@0A@'.
      ls_err-rowcolor = 'C100'.
    ELSE.
      ls_err-rowcolor = 'C200'.
    ENDIF.

    READ TABLE gt_errors INTO ls_err
      WITH KEY mensaje = ls_raw-mensaje bukrs = ls_raw-bukrs.
    IF sy-subrc <> 0.
      CLEAR ls_err.
      ls_err-mensaje    = ls_raw-mensaje.
      ls_err-bukrs      = ls_raw-bukrs.
      ls_err-gjahr      = ls_raw-gjahr.
      ls_err-monat      = ls_raw-monat.
      ls_err-belnr_ex   = ls_raw-belnr.
      ls_err-fichero_ex = ls_raw-fichero.
      IF ls_raw-icon_status = '@0A@'.
        ls_err-rowcolor = 'C100'.
      ELSE.
        ls_err-rowcolor = 'C200'.
      ENDIF.
      ls_err-cnt = 1.
      APPEND ls_err TO gt_errors.
    ELSE.
      ls_err-cnt = ls_err-cnt + 1.
      MODIFY gt_errors FROM ls_err
        TRANSPORTING cnt
        WHERE mensaje = ls_raw-mensaje AND bukrs = ls_raw-bukrs.
    ENDIF.
  ENDLOOP.

  SORT gt_errors BY cnt DESCENDING.

ENDFORM.
