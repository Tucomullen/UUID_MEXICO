*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM02
*&---------------------------------------------------------------------*
*& Tab 1: Dashboard Rediseñado (HTML + ALVs)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB1
*&---------------------------------------------------------------------*
FORM frm_build_tab1.

  " 1. Splitter Principal Fila 1 (HTML 35%), Fila 2 (ALVs 65%)
  IF go_split_t1 IS INITIAL.
    CREATE OBJECT go_split_t1
      EXPORTING
        parent  = go_cont_main
        rows    = 2
        columns = 1.
    
    go_split_t1->set_row_height( id = 1 height = 35 ).
    go_cont_t1_t = go_split_t1->get_container( row = 1 column = 1 ).
    
    " Contenedor para la parte inferior
    DATA(lo_cont_b) = go_split_t1->get_container( row = 2 column = 1 ).
    
    " 2. Splitter Inferior (Left 50% / Right 50%)
    CREATE OBJECT go_split_t1_b
      EXPORTING
        parent  = lo_cont_b
        rows    = 1
        columns = 2.
    
    go_cont_t1_bl = go_split_t1_b->get_container( row = 1 column = 1 ).
    go_cont_t1_br = go_split_t1_b->get_container( row = 1 column = 2 ).
  ENDIF.

  PERFORM frm_render_html_kpi.
  PERFORM frm_render_alv_resumen.
  PERFORM frm_render_alv_actividad.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_HTML_KPI
*&---------------------------------------------------------------------*
FORM frm_render_html_kpi.

  DATA: lt_html    TYPE TABLE OF w3html,
        lv_url     TYPE char255,
        lv_html    TYPE string,
        lv_status  TYPE string,
        lv_color   TYPE string,
        lv_msg     TYPE string,
        lv_bg      TYPE string.

  IF go_html_kpi IS INITIAL.
    CREATE OBJECT go_html_kpi
      EXPORTING
        parent = go_cont_t1_t.

    " Registrar manejador de eventos para clics en HTML
    SET HANDLER go_event_receiver->on_sapevent FOR go_html_kpi.

    DATA: lt_events_h TYPE cntl_simple_events,
          ls_event_h  TYPE cntl_simple_event.

    ls_event_h-eventid = cl_gui_html_viewer=>m_id_sapevent.
    ls_event_h-appl_event = 'X'.
    APPEND ls_event_h TO lt_events_h.
    go_html_kpi->set_registered_events( events = lt_events_h ).
  ENDIF.

  " Lógica de color general
  IF gs_kpi-pct_err > 20.
    lv_status = 'CRÍTICO'.
    lv_color  = '#d32f2f'. " Rojo
    lv_bg     = '#ffebee'.
    lv_msg    = 'Se han detectado errores críticos en la carga de UUIDs. Revise el detalle.'.
  ELSEIF gs_kpi-tot_warn > 0.
    lv_status = 'ATENCIÓN'.
    lv_color  = '#fbc02d'. " Amarillo
    lv_bg     = '#fffde7'.
    lv_msg    = 'Existen advertencias en el proceso. Algunos registros requieren revisión.'.
  ELSEIF gs_kpi-tot_reg > 0.
    lv_status = 'SALUDABLE'.
    lv_color  = '#388e3c'. " Verde
    lv_bg     = '#e8f5e9'.
    lv_msg    = 'El proceso se ha completado correctamente para todos los registros.'.
  ELSE.
    lv_status = 'SIN DATOS'.
    lv_color  = '#757575'. " Gris
    lv_bg     = '#f5f5f5'.
    lv_msg    = 'No hay datos cargados para los filtros seleccionados.'.
  ENDIF.

  " Definiciones de tooltips para ayuda contextual
  DATA: lv_t_total TYPE string VALUE 'Total de líneas de documentos contables SAP afectados.',
        lv_t_ok    TYPE string VALUE 'Documentos donde el UUID se asignó correctamente.',
        lv_t_warn  TYPE string VALUE 'Documentos con UUID previo diferente o que requieren revisión.',
        lv_t_err   TYPE string VALUE 'Registros con errores técnicos o documento SAP no localizado.',
        lv_t_pct   TYPE string VALUE 'Porcentaje de registros exitosos sobre el total procesado.',
        lv_t_uuid  TYPE string VALUE 'Contador de facturas fiscales reales (CFDI). Útil para control de Intercompanies.'.

  " Construcción del HTML con CSS inline para máximo impacto
  lv_html =
    '<html><head><style>' &&
    'body { font-family: "Segoe UI", Arial, sans-serif; background: #fafafa; margin: 15px; }' &&
    '.dash-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }' &&
    '.dash-title { font-size: 22px; font-weight: bold; color: #333; }' &&
    '.status-banner { padding: 10px 18px; border-radius: 8px; border-left: 5px solid ' && lv_color && '; background: ' && lv_bg && '; margin-bottom: 20px; }' &&
    '.status-title { font-weight: bold; font-size: 15px; color: ' && lv_color && '; text-transform:uppercase; }' &&
    '.cards-container { display: flex; gap: 12px; }' &&
    '.card { flex: 1; background: white; padding: 12px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); border: 1px solid #eee; text-align: center; text-decoration: none; transition: all 0.2s ease; }' &&
    '.card:hover { transform: translateY(-3px); box-shadow: 0 5px 12px rgba(0,0,0,0.1); border-color: #ccc; }' &&
    '.card-click { cursor: pointer; }' &&
    '.card-label { font-size: 10px; text-transform: uppercase; color: #888; font-weight: bold; letter-spacing: 0.5px; margin-bottom: 6px; }' &&
    '.card-value { font-size: 26px; font-weight: bold; color: #222; }' &&
    '.card-ok { border-bottom: 4px solid #4caf50; } .card-err { border-bottom: 4px solid #f44336; }' &&
    '.card-warn { border-bottom: 4px solid #fbc02d; } .card-blue { border-bottom: 4px solid #2196f3; }' &&
    '</style></head><body>' &&
    '<div class="dash-header"><div class="dash-title">Resumen Ejecutivo UUID</div></div>' &&
    '<div class="status-banner"><div class="status-title">ESTADO: ' && lv_status && '</div>' &&
    '<div style="font-size: 13px; color: #555;">' && lv_msg && '</div></div>' &&
    '<div class="cards-container">' &&
    '<div class="card card-blue" title="' && lv_t_total && '"><div class="card-label">Total Procesados</div><div class="card-value">' && |{ gs_kpi-tot_reg }| && '</div></div>' &&
    '<a href="SAPEVENT:DRILLDOWN_OK" class="card card-ok card-click" title="' && lv_t_ok && '"><div class="card-label">Correctos (OK)</div><div class="card-value" style="color:#2e7d32">' && |{ gs_kpi-tot_ok }| && '</div></a>' &&
    '<a href="SAPEVENT:DRILLDOWN_WARN" class="card card-warn card-click" title="' && lv_t_warn && '"><div class="card-label">Con Warning</div><div class="card-value" style="color:#f9a825">' && |{ gs_kpi-tot_warn }| && '</div></a>' &&
    '<a href="SAPEVENT:DRILLDOWN_ERR" class="card card-err card-click" title="' && lv_t_err && '"><div class="card-label">Con Error</div><div class="card-value" style="color:#c62828">' && |{ gs_kpi-tot_err }| && '</div></a>' &&
    '<div class="card card-blue" title="' && lv_t_pct && '"><div class="card-label">% Éxito</div><div class="card-value">' && |{ gs_kpi-pct_ok }%| && '</div></div>' &&
    '<div class="card card-blue" title="' && lv_t_uuid && '"><div class="card-label">UUIDs Únicos</div><div class="card-value">' && |{ gs_kpi-num_uuid }| && '</div></div>' &&
    '</div></body></html>'.

  " Convertir STRING a tabla W3HTML
  DATA: lv_offset TYPE i,
        lv_len    TYPE i.
  lv_len = strlen( lv_html ).
  WHILE lv_offset < lv_len.
    APPEND lv_html+lv_offset TO lt_html.
    lv_offset = lv_offset + 255.
  ENDWHILE.

  go_html_kpi->load_data( 
    IMPORTING assigned_url = lv_url
    CHANGING  data_table   = lt_html ).

  go_html_kpi->show_url( url = lv_url ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_ALV_RESUMEN
*&---------------------------------------------------------------------*
FORM frm_render_alv_resumen.

  TYPES: BEGIN OF lty_summary,
           icon    TYPE icon_d,
           status  TYPE char20,
           count   TYPE i,
           percent TYPE p DECIMALS 1,
           color   TYPE char4,
         END OF lty_summary.

  DATA: lt_summary TYPE TABLE OF lty_summary,
        ls_summary TYPE lty_summary,
        lt_fcat    TYPE lvc_t_fcat,
        ls_fcat    TYPE lvc_s_fcat,
        ls_layout  TYPE lvc_s_layo.

  " Llenar tabla de resumen
  ls_summary-icon    = '@08@'.
  ls_summary-status  = 'OK'.
  ls_summary-count   = gs_kpi-tot_ok.
  ls_summary-percent = gs_kpi-pct_ok.
  ls_summary-color   = 'C300'.
  APPEND ls_summary TO lt_summary.

  ls_summary-icon    = '@09@'.
  ls_summary-status  = 'Warning'.
  ls_summary-count   = gs_kpi-tot_warn.
  IF gs_kpi-tot_reg > 0.
    ls_summary-percent = ( gs_kpi-tot_warn * 100 ) / gs_kpi-tot_reg.
  ENDIF.
  ls_summary-color   = 'C200'.
  APPEND ls_summary TO lt_summary.

  ls_summary-icon    = '@0A@'.
  ls_summary-status  = 'Error'.
  ls_summary-count   = gs_kpi-tot_err.
  ls_summary-percent = gs_kpi-pct_err.
  ls_summary-color   = 'C110'. " Rojo intenso
  APPEND ls_summary TO lt_summary.

  IF go_alv_kpi IS INITIAL.
    CREATE OBJECT go_alv_kpi
      EXPORTING
        i_parent = go_cont_t1_bl.

    " Fieldcat minimalista
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'ICON'.    ls_fcat-scrtext_s = 'Est.'. ls_fcat-icon = 'X'. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'STATUS'.  ls_fcat-scrtext_s = 'Estado'. ls_fcat-outputlen = 10. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'COUNT'.   ls_fcat-scrtext_s = 'Cantidad'. ls_fcat-do_sum = 'X'. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'PERCENT'. ls_fcat-scrtext_s = '%'. ls_fcat-decimals_o = 1. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.

    ls_layout-grid_title = 'Resumen por Estado'.
    ls_layout-smalltitle = 'X'.
    ls_layout-no_toolbar = 'X'.
    ls_layout-cwidth_opt = 'X'.
    ls_layout-info_fname = 'COLOR'.

    go_alv_kpi->set_table_for_first_display(
      EXPORTING
        is_layout       = ls_layout
      CHANGING
        it_outtab       = lt_summary
        it_fieldcatalog = lt_fcat ).
  ELSE.
    go_alv_kpi->refresh_table_display( ).
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_ALV_ACTIVIDAD
*&---------------------------------------------------------------------*
FORM frm_render_alv_actividad.

  DATA: lt_fcat    TYPE lvc_t_fcat,
        ls_fcat    TYPE lvc_s_fcat,
        ls_layout  TYPE lvc_s_layo,
        lt_top_buk TYPE TABLE OF gty_by_bukrs.

  " Usar las top 5 sociedades con registros
  lt_top_buk = gt_by_bukrs.
  SORT lt_top_buk BY tot_reg DESCENDING.
  DELETE lt_top_buk FROM 6.

  IF go_alv_kpi_2 IS INITIAL.
    CREATE OBJECT go_alv_kpi_2
      EXPORTING
        i_parent = go_cont_t1_br.

    " Fieldcat
    CLEAR ls_fcat.
    ls_fcat-fieldname = 'BUKRS'.   ls_fcat-scrtext_s = 'Soc.'. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'BUTXT'.   ls_fcat-scrtext_s = 'Descripción'. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'TOT_REG'. ls_fcat-scrtext_s = 'Total'. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.
    ls_fcat-fieldname = 'PCT_OK'.  ls_fcat-scrtext_s = '% OK'. ls_fcat-decimals_o = 1. ls_fcat-col_opt = 'X'. APPEND ls_fcat TO lt_fcat.

    ls_layout-grid_title = 'Top Sociedades con Actividad'.
    ls_layout-smalltitle = 'X'.
    ls_layout-no_toolbar = 'X'.
    ls_layout-cwidth_opt = 'X'.
    ls_layout-info_fname = 'LIGHT'.

    go_alv_kpi_2->set_table_for_first_display(
      EXPORTING
        is_layout       = ls_layout
      CHANGING
        it_outtab       = lt_top_buk
        it_fieldcatalog = lt_fcat ).
  ELSE.
    go_alv_kpi_2->refresh_table_display( ).
  ENDIF.

ENDFORM.
