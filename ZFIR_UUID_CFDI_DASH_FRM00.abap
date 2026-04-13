*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM00
*&---------------------------------------------------------------------*
*& Renderizado 100% ABAP OO del Dashboard (Substituye al Dynpro 100)
*&---------------------------------------------------------------------*

CLASS lcl_event_receiver IMPLEMENTATION.
  METHOD on_function_selected.
    " Si el usuario hace clic MANUAL en una pestaña distinta a TAB5,
    " limpiar el filtro de drill-down. Si hace clic en TAB5 manualmente
    " (sin venir de drill-down), también limpiar para mostrar todo.
    " Si viene de drill-down (gv_drilldown_status ya tiene valor),
    " NO limpiar porque el on_sapevent ya lo puso.
    IF fcode CP 'TAB*' AND fcode <> 'TAB5'.
      CLEAR gv_drilldown_status.
    ELSEIF fcode = 'TAB5' AND gv_drilldown_status IS INITIAL.
      " Clic manual en Tab5 sin drill-down previo → mostrar todo
      CLEAR gv_drilldown_status.
    ENDIF.

    gv_tab_key = fcode.
    PERFORM frm_render_active_tab.
  ENDMETHOD.

  METHOD on_sapevent.
    " Manejar clics desde el HTML (KPI cards)
    " IMPORTANTE: No renderizar aquí directamente. El on_sapevent se ejecuta
    " dentro del dispatch del Control Framework, y cualquier destrucción/creación
    " de controles GUI no se repinta hasta el siguiente PBO. La solución es
    " guardar el estado deseado y forzar un nuevo ciclo PAI completo con
    " set_new_ok_code, donde el MODULE user_command_0100 ejecutará el render.
    DATA: lv_action TYPE string.
    lv_action = action.
    TRANSLATE lv_action TO UPPER CASE.

    CASE lv_action.
      WHEN 'DRILLDOWN_OK' OR 'DRILLDOWN_WARN' OR 'DRILLDOWN_ERR'.
        " 1. Guardar estado de navegación
        gv_drilldown_status = lv_action.
        gv_tab_key          = 'TAB5'.
        " 2. Forzar un nuevo roundtrip PAI→PBO para que la GUI se repinte
        cl_gui_cfw=>set_new_ok_code( new_code = 'DRILL_NAV' ).
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& PBO / PAI Modules for Empty Screen 0100
*&---------------------------------------------------------------------*
MODULE status_0100 OUTPUT.
  SET PF-STATUS 'ZSTD'.
  SET TITLEBAR 'ZUUID_DASH'.

  IF go_docking IS INITIAL.
    PERFORM frm_build_gui_docking.
  ENDIF.
ENDMODULE.

MODULE user_command_0100 INPUT.
  DATA: lv_rc    TYPE i,
        lv_ucomm TYPE syucomm.

  " Capturar y limpiar ucomm para evitar bucles
  lv_ucomm = sy-ucomm.
  CLEAR sy-ucomm.

  " CRUCIAL: Despachar eventos de aplicación del Control Framework (Toolbar)
  CALL METHOD cl_gui_cfw=>dispatch
    IMPORTING
      return_code = lv_rc.

  CASE lv_ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      PERFORM frm_free_gui.
      LEAVE TO SCREEN 0.
    WHEN 'DRILL_NAV'.
      " Viene de on_sapevent (clic en KPI card HTML).
      " gv_drilldown_status y gv_tab_key ya están puestos.
      " Ahora sí renderizamos en el flujo normal PAI donde el
      " repintado de la GUI funciona correctamente.
      PERFORM frm_render_active_tab.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_GUI_DOCKING
*&---------------------------------------------------------------------*
FORM frm_build_gui_docking.
* 1. Crear Docking Container sobre la pantalla activa (0100)
    CREATE OBJECT go_docking
      EXPORTING
        repid     = sy-repid
        dynnr     = sy-dynnr
        side      = cl_gui_docking_container=>dock_at_top
        extension = 3000.  " Tamaño base para expandir

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

    cl_gui_cfw=>flush( ).

* 5. Mostrar la primera tab
    PERFORM frm_render_active_tab.

    cl_gui_cfw=>flush( ).
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

  go_toolbar->add_button( fcode = '' icon = '' butn_type = 3 ). " Separador

  ls_button-function  = 'DELETE'.
  ls_button-icon      = '@11@'.  " Papelera
  ls_button-text      = 'Borrar Histórico'.
  go_toolbar->add_button( fcode = ls_button-function icon = ls_button-icon butn_type = 0 text = ls_button-text ).
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_ACTIVE_TAB
*&---------------------------------------------------------------------*
*& Determina qué contenido mostrar en base a la función seleccionada
*&---------------------------------------------------------------------*
FORM frm_render_active_tab.

  IF gv_tab_key = 'REFRESH'.
    PERFORM frm_cargar_datos.
    PERFORM frm_refresh_all_tabs.
    gv_tab_key = 'TAB1'. " Por defecto ir a tab 1 después de refrescar
  ENDIF.
  
  IF gv_tab_key = 'DELETE'.
    PERFORM frm_delete_logs.
    RETURN.
  ENDIF.

  IF gv_tab_key = 'EXCEL'.
    PERFORM frm_export_excel.
    RETURN.
  ENDIF.

* Ocultar todos los objetos de la pestaña anterior destruyendo componentes de forma segura
  PERFORM frm_free_active_tab.

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
*& Form FRM_DELETE_LOGS
*&---------------------------------------------------------------------*
*& Borra todo el histórico de logs con confirmación previa.
*&---------------------------------------------------------------------*
FORM frm_delete_logs.
  DATA: lv_answer TYPE c.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = 'Confirmar borrado de histórico'
      text_question         = '¿Desea borrar TODOS los registros de log y ejecuciones? Esta acción no se puede deshacer.'
      text_button_1         = 'Sí, borrar todo'
      icon_button_1         = '@11@'
      text_button_2         = 'No, cancelar'
      icon_button_2         = '@12@'
      display_cancel_button = ' '
    IMPORTING
      answer                = lv_answer
    EXCEPTIONS
      text_not_found        = 1
      OTHERS                = 2.

  IF lv_answer = '1'.
    " Borrado total de tablas Z
    DELETE FROM ztt_uuid_log.
    DELETE FROM ztt_uuid_exec.
    COMMIT WORK AND WAIT.
    
    MESSAGE 'Historial de logs borrado correctamente.' TYPE 'S'.
    
    " Limpiar datos en memoria y refrescar UI
    PERFORM frm_cargar_datos.
    PERFORM frm_refresh_all_tabs.
    
    " Volver a la pestaña principal para ver los KPIs a cero
    gv_tab_key = 'TAB1'.
    PERFORM frm_render_active_tab.
  ELSE.
    " Si cancela, volvemos a la pestaña donde estaba (o a la 1 por defecto)
    IF gv_tab_key = 'DELETE'.
       gv_tab_key = 'TAB1'.
    ENDIF.
    PERFORM frm_render_active_tab.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_REFRESH_ALL_TABS
*&---------------------------------------------------------------------*
FORM frm_refresh_all_tabs.
  CLEAR: gv_tab1_init, gv_tab2_init, gv_tab3_init,
         gv_tab4_init, gv_tab5_init.

* Liberar objetos GUI existentes
  PERFORM frm_free_active_tab.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FREE_ACTIVE_TAB
*&---------------------------------------------------------------------*
FORM frm_free_active_tab.

  " 1. Controles individuales
  IF go_html_kpi IS BOUND.
    go_html_kpi->free( ).
    FREE go_html_kpi.
  ENDIF.

  IF go_alv_kpi IS BOUND.
    go_alv_kpi->free( ).
    FREE go_alv_kpi.
  ENDIF.

  IF go_alv_kpi_2 IS BOUND.
    go_alv_kpi_2->free( ).
    FREE go_alv_kpi_2.
  ENDIF.

  IF go_alv_bukrs IS BOUND.
    go_alv_bukrs->free( ).
    FREE go_alv_bukrs.
  ENDIF.

  IF go_alv_month IS BOUND.
    go_alv_month->free( ).
    FREE go_alv_month.
  ENDIF.

  IF go_alv_errors IS BOUND.
    go_alv_errors->free( ).
    FREE go_alv_errors.
  ENDIF.

  IF go_alv_detail IS BOUND.
    go_alv_detail->free( ).
    FREE go_alv_detail.
  ENDIF.

  " --- Charts (Limpieza de referencia ABAP únicamente) ---
  FREE: go_chart_t2, go_chart_t3.

  " 2. Splitters (después de sus hijos)
  IF go_split_t1_b IS BOUND.
    go_split_t1_b->free( ).
    FREE go_split_t1_b.
  ENDIF.

  IF go_split_t1 IS BOUND.
    go_split_t1->free( ).
    FREE go_split_t1.
  ENDIF.

  IF go_split_t2 IS BOUND.
    go_split_t2->free( ).
    FREE go_split_t2.
  ENDIF.

  IF go_split_t3 IS BOUND.
    go_split_t3->free( ).
    FREE go_split_t3.
  ENDIF.

  " 3. Limpiar referencias a contenedores
  FREE: go_cont_t1_t, go_cont_t1_bl, go_cont_t1_br,
        go_cont_t2_t, go_cont_t2_b,
        go_cont_t3_t, go_cont_t3_b.

  cl_gui_cfw=>flush( ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_EXPORT_EXCEL
*&---------------------------------------------------------------------*
FORM frm_export_excel.
* Exportación disponible desde la barra de herramientas estándar del propio ALV:
  MESSAGE 'Use el botón "Local File" o "Export" nativo del ALV activo actualmente.' TYPE 'I'.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FREE_GUI
*&---------------------------------------------------------------------*
FORM frm_free_gui.
  PERFORM frm_free_active_tab.
  FREE: go_event_receiver, go_toolbar, go_cont_toolbar, go_cont_main, go_main_splitter.

  IF go_docking IS BOUND.
    go_docking->free( ).
  ENDIF.
  FREE go_docking.
ENDFORM.
