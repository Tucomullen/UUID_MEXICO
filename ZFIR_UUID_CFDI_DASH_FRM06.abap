*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM06
*&---------------------------------------------------------------------*
*& Tab 5: ALV detalle completo + drill-down FB03 con doble clic
*& Custom Control: CC_TAB5 en subscreen 0105
*&---------------------------------------------------------------------*

**********************************************************************
** CLASE LOCAL PARA DOBLE CLIC → FB03                               **
**********************************************************************
CLASS lcl_evt DEFINITION.
  PUBLIC SECTION.
    METHODS: on_dbl_click
      FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column.
ENDCLASS.

CLASS lcl_evt IMPLEMENTATION.
  METHOD on_dbl_click.
    DATA: ls_det TYPE ztt_uuid_log.
    READ TABLE gt_detail INTO ls_det INDEX e_row-index.
    IF sy-subrc = 0 AND ls_det-belnr IS NOT INITIAL.
      SET PARAMETER ID 'BUK' FIELD ls_det-bukrs.
      SET PARAMETER ID 'BLN' FIELD ls_det-belnr.
      SET PARAMETER ID 'GJR' FIELD ls_det-gjahr.
      CALL TRANSACTION 'FB03' AND SKIP FIRST SCREEN.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

DATA: go_evt_handler TYPE REF TO lcl_evt.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB5
*&---------------------------------------------------------------------*
FORM frm_build_tab5.

  DATA: lt_fcat   TYPE lvc_t_fcat,
        ls_fcat   TYPE lvc_s_fcat,
        ls_layo   TYPE lvc_s_layo,
        lv_status TYPE char4,
        lv_title  TYPE string.

  " 1. Preparar datos: Siempre partir del total (gt_zlog_raw)
  gt_detail = gt_zlog_raw.

  " 2. Aplicar filtro si viene de drill-down desde KPI card
  IF gv_drilldown_status IS NOT INITIAL.
    CASE gv_drilldown_status.
      WHEN 'DRILLDOWN_OK'.
        lv_status = '@08@'.
        lv_title  = 'Detalle: Registros Correctos (OK)'.
      WHEN 'DRILLDOWN_WARN'.
        lv_status = '@09@'.
        lv_title  = 'Detalle: Registros con Warning'.
      WHEN 'DRILLDOWN_ERR'.
        lv_status = '@0A@'.
        lv_title  = 'Detalle: Registros con Error'.
    ENDCASE.

    IF lv_status IS NOT INITIAL.
      DELETE gt_detail WHERE icon_status <> lv_status.
    ENDIF.
  ELSE.
    lv_title = 'Detalle Completo de Registros'.
  ENDIF.

  " 3. Preparar Layout
  ls_layo-zebra      = 'X'.
  ls_layo-cwidth_opt = 'X'.
  ls_layo-grid_title = lv_title.

  " 4. Fieldcatalog
  DEFINE add_fc.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-outputlen = &3.
    ls_fcat-col_opt   = 'X'.
    IF &1 = 'ICON_STATUS'.
      ls_fcat-icon = 'X'.
    ENDIF.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_fc 'ICON_STATUS'  'Estado'      4.
  add_fc 'DATUM_PROC'   'Fec.Proceso' 10.
  add_fc 'UNAME'        'Usuario'     12.
  add_fc 'BUKRS'        'Sociedad'     6.
  add_fc 'BELNR'        'Documento'   10.
  add_fc 'GJAHR'        'Ejercicio'    4.
  add_fc 'BUDAT'        'Fec.Contab.' 10.
  add_fc 'BLDAT'        'Fec.Doc.'    10.
  add_fc 'MONAT'        'Mes'          2.
  add_fc 'BLART'        'Clase Doc.'   2.
  add_fc 'RFC_EMISOR'   'RFC Emisor'  13.
  add_fc 'RFC_RECEPTOR' 'RFC Recept.' 13.
  add_fc 'SERIE'        'Serie'       10.
  add_fc 'FOLIO'        'Folio'       20.
  add_fc 'TIPO'         'Tipo CFDI'    1.
  add_fc 'TIPO_FAC'     'Tipo Fac.'    1.
  add_fc 'UUID'         'UUID'        36.
  add_fc 'UUID_PREVIO'  'UUID Previo' 36.
  add_fc 'MENSAJE'      'Mensaje'     50.
  add_fc 'FICHERO'      'Fichero'     30.
  add_fc 'TEST_MODE'    'Simulación'   1.

  " 5. Crear ALV nuevo (siempre se destruyó previamente en frm_free_active_tab)
  "    No usar refresh: con filtro físico distinto hay que hacer set_table_for_first_display
  CREATE OBJECT go_alv_detail
    EXPORTING i_parent = go_cont_main.

  " Registrar handler de doble clic → FB03
  CREATE OBJECT go_evt_handler.
  SET HANDLER go_evt_handler->on_dbl_click FOR go_alv_detail.

  go_alv_detail->set_table_for_first_display(
    EXPORTING is_layout       = ls_layo
    CHANGING  it_outtab       = gt_detail
              it_fieldcatalog = lt_fcat ).

ENDFORM.
