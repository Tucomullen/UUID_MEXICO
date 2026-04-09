*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM00
*&---------------------------------------------------------------------*
*& Renderizado 100% ABAP OO del Dashboard (Substituye al Dynpro 100)
*&---------------------------------------------------------------------*

CLASS lcl_event_receiver IMPLEMENTATION.
  METHOD on_function_selected.
    gv_tab_key = fcode.
    " Disparar la lógica de renderizar tab
    PERFORM frm_render_active_tab.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_GUI_DOCKING
*&---------------------------------------------------------------------*
FORM frm_build_gui_docking.
* 1. Crear Docking Container sobre la pantalla activa (Lista)
  IF go_docking IS INITIAL.
    CREATE OBJECT go_docking
      EXPORTING
        repid     = sy-repid
        dynnr     = '0120'  " 0120 es el código de pantalla nativo de la lista
        side      = cl_gui_docking_container=>dock_at_top
        extension = 99999.  " Tamaño máximo para forzar visibilidad

* 2. Splitter 2 Filas: Fila 1 Toolbar, Fila 2 Contenido principal
    CREATE OBJECT go_main_splitter
      EXPORTING
        parent  = go_docking
        rows    = 2
        columns = 1.

    go_main_splitter->set_row_height( id = 1 height = 5 ). " 5% altura para la botonera

    go_cont_toolbar = go_main_splitter->get_container( row = 1 column = 1 ).
    go_cont_main    = go_main_splitter->get_container( row = 2 column = 1 ).

* 3. Toolbar
    CREATE OBJECT go_toolbar
      EXPORTING
        parent = go_cont_toolbar.

    PERFORM frm_build_toolbar_buttons.

* 4. Registrar Eventos
    CREATE OBJECT go_event_receiver.
    SET HANDLER go_event_receiver->on_function_selected FOR go_toolbar.

    DATA: lt_events TYPE cntl_simple_events,
          ls_event  TYPE cntl_simple_event.

    ls_event-eventid = cl_gui_toolbar=>m_id_function_selected.
    ls_event-appl_event = 'X'.
    APPEND ls_event TO lt_events.
    go_toolbar->set_registered_events( events = lt_events ).

* 5. Mostrar la primera tab
    PERFORM frm_render_active_tab.

  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TOOLBAR_BUTTONS
*&---------------------------------------------------------------------*
FORM frm_build_toolbar_buttons.
  DATA: ls_button TYPE stb_button.

  ls_button-function  = 'TAB1'.
  ls_button-icon      = '@0Q@'.  " Icono KPI
  ls_button-text      = 'Resumen KPIs'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).

  ls_button-function  = 'TAB2'.
  ls_button-icon      = '@8D@'.  " Edificio
  ls_button-text      = 'Por Sociedad'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).

  ls_button-function  = 'TAB3'.
  ls_button-icon      = '@5A@'.  " Calendario
  ls_button-text      = 'Tendencia Mensual'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).

  ls_button-function  = 'TAB4'.
  ls_button-icon      = '@0A@'.  " Error
  ls_button-text      = 'Análisis Errores'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).

  ls_button-function  = 'TAB5'.
  ls_button-icon      = '@16@'.  " Lupa
  ls_button-text      = 'Detalle Completo'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).

  go_toolbar->add_button( fcode = '' icon = '' butn_type = 3 ). " Separador visual

  ls_button-function  = 'REFRESH'.
  ls_button-icon      = '@42@'.
  ls_button-text      = 'Actualizar Datos'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).
  
  ls_button-function  = 'EXCEL'.
  ls_button-icon      = '@J2@'.
  ls_button-text      = 'Exportar'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_ACTIVE_TAB
*&---------------------------------------------------------------------*
FORM frm_render_active_tab.

  IF gv_tab_key = 'REFRESH'.
    PERFORM frm_cargar_datos.
    PERFORM frm_refresh_all_tabs.
    gv_tab_key = 'TAB1'. " Por defecto ir a tab 1 despues de refrescar
  ENDIF.
  
  IF gv_tab_key = 'EXCEL'.
    PERFORM frm_export_excel.
    RETURN.
  ENDIF.

* Ocultar todos los objetos de la pestaña anterior destruyendo componentes viejos 
* para usar el contenedor go_cont_main como pivot
  FREE: go_split_t1, go_split_t2, go_split_t3,
        go_kpi_doc, go_alv_bukrs, go_alv_month, 
        go_alv_errors, go_alv_detail.

  CASE gv_tab_key.
    WHEN 'TAB1'.
      IF gv_tab1_init IS INITIAL.
        gv_tab1_init = 'X'.
      ENDIF.
      PERFORM frm_build_tab1.
    WHEN 'TAB2'.
      IF gv_tab2_init IS INITIAL.
        gv_tab2_init = 'X'.
      ENDIF.
      PERFORM frm_build_tab2.
    WHEN 'TAB3'.
      IF gv_tab3_init IS INITIAL.
        gv_tab3_init = 'X'.
      ENDIF.
      PERFORM frm_build_tab3.
    WHEN 'TAB4'.
      IF gv_tab4_init IS INITIAL.
        gv_tab4_init = 'X'.
      ENDIF.
      PERFORM frm_build_tab4.
    WHEN 'TAB5'.
      IF gv_tab5_init IS INITIAL.
        gv_tab5_init = 'X'.
      ENDIF.
      PERFORM frm_build_tab5.
  ENDCASE.

* Hacer que se repinte la GUI para mostrar los hijos regenerados
  cl_gui_cfw=>flush( ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_REFRESH_ALL_TABS
*&---------------------------------------------------------------------*
FORM frm_refresh_all_tabs.
  CLEAR: gv_tab1_init, gv_tab2_init, gv_tab3_init,
         gv_tab4_init, gv_tab5_init.

* Liberar objetos GUI existentes
  FREE: go_alv_bukrs, go_alv_month, go_alv_errors, go_alv_detail.
  FREE: go_chart_t1, go_chart_t2, go_chart_t3.
  FREE: go_kpi_doc.
  FREE: go_split_t1, go_split_t2, go_split_t3.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_EXPORT_EXCEL
*&---------------------------------------------------------------------*
FORM frm_export_excel.
* Exportación disponible desde la barra de herramientas estándar del propio ALV:
  MESSAGE 'Use el botón "Local File" o "Export" nativo del ALV activo actualmente.' TYPE 'I'.
ENDFORM.
