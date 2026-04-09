*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM02
*&---------------------------------------------------------------------*
*& Tab 1: KPI cards (CL_DD_DOCUMENT) + Chart tipo PIE
*& Custom Control: CC_TAB1 en subscreen 0101
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB1
*&---------------------------------------------------------------------*
FORM frm_build_tab1.

* Contenedor principal
  go_cont_t1_l = go_cont_main.

  PERFORM frm_render_kpi_doc.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_KPI_DOC
*&---------------------------------------------------------------------*
FORM frm_render_kpi_doc.

  DATA: lv_text TYPE sdydo_text_element,
        lv_num  TYPE char20.

  CREATE OBJECT go_kpi_doc.

  go_kpi_doc->initialize_document( ).

  go_kpi_doc->add_text(
    text      = 'RESUMEN GLOBAL UUID CFDI'
    sap_style = cl_dd_document=>heading ).
  go_kpi_doc->new_line( ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-tot_reg TO lv_num LEFT-JUSTIFIED.
  CONCATENATE 'Total registros procesados: ' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text  sap_style = cl_dd_document=>large ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-tot_ok TO lv_num LEFT-JUSTIFIED.
  CONCATENATE '  OK (verde):       ' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-tot_warn TO lv_num LEFT-JUSTIFIED.
  CONCATENATE '  Warning (amaril.):' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-tot_err TO lv_num LEFT-JUSTIFIED.
  CONCATENATE '  Error (rojo):     ' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text ).
  go_kpi_doc->new_line( ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-pct_ok TO lv_num DECIMALS 1 LEFT-JUSTIFIED.
  CONCATENATE '  % OK:    ' lv_num '%' INTO lv_text.
  go_kpi_doc->add_text( text = lv_text  sap_style = cl_dd_document=>large ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-pct_err TO lv_num DECIMALS 1 LEFT-JUSTIFIED.
  CONCATENATE '  % Error: ' lv_num '%' INTO lv_text.
  go_kpi_doc->add_text( text = lv_text  sap_style = cl_dd_document=>large ).
  go_kpi_doc->new_line( ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-num_uuid TO lv_num LEFT-JUSTIFIED.
  CONCATENATE '  UUIDs únicos grabados:     ' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text ).
  go_kpi_doc->new_line( ).

  WRITE gs_kpi-num_exec TO lv_num LEFT-JUSTIFIED.
  CONCATENATE '  Nº ejecuciones distintas:  ' lv_num INTO lv_text.
  go_kpi_doc->add_text( text = lv_text ).
  go_kpi_doc->new_line( ).

  go_kpi_doc->display_document(
    EXPORTING parent = go_cont_t1_l ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_CHART_T1  (deshabilitado — CL_GUI_CHART_ENGINE
*&  no disponible en esta versión del sistema)
*&---------------------------------------------------------------------*
FORM frm_render_chart_t1.
ENDFORM.
