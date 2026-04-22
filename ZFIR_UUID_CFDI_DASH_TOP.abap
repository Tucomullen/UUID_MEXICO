*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_TOP
*&---------------------------------------------------------------------*
*& Tipos, datos globales y referencias a objetos GUI del dashboard
*&---------------------------------------------------------------------*

**********************************************************************
** TABLAS PARA SELECT-OPTIONS                                       **
**********************************************************************
TABLES: ztt_uuid_log.

**********************************************************************
** CONSTANTES GLOBALES                                              **
**********************************************************************
CONSTANTS:
  gc_auth_obj  TYPE char20 VALUE 'F_BKPF_BUK', " Objeto de autorización FI
  gc_actvt_dis TYPE char2  VALUE '03'.         " Actividad: Visualizar

**********************************************************************
** TIPOS DE DATOS                                                   **
**********************************************************************

* KPIs globales
TYPES: BEGIN OF gty_kpi,
         tot_reg  TYPE i,
         tot_ok   TYPE i,
         tot_warn TYPE i,
         tot_err  TYPE i,
         pct_ok   TYPE p DECIMALS 2,
         pct_err  TYPE p DECIMALS 2,
         num_uuid TYPE i,
         num_exec TYPE i,
       END OF gty_kpi.

* Agrupación por sociedad
TYPES: BEGIN OF gty_by_bukrs,
         bukrs    TYPE bukrs,
         butxt    TYPE butxt,
         tot_reg  TYPE i,
         tot_ok   TYPE i,
         tot_warn TYPE i,
         tot_err  TYPE i,
         pct_ok   TYPE p DECIMALS 2,
         light    TYPE char4,    " C300=verde C200=amarillo C100=rojo
       END OF gty_by_bukrs.

* Agrupación por mes
TYPES: BEGIN OF gty_by_month,
         gjahr    TYPE gjahr,
         monat    TYPE monat,
         periodo  TYPE char7,    " 'AAAA/MM'
         tot_reg  TYPE i,
         tot_ok   TYPE i,
         tot_warn TYPE i,
         tot_err  TYPE i,
       END OF gty_by_month.

* Errores agrupados
TYPES: BEGIN OF gty_errors,
         rowcolor   TYPE char4,   " C100=rojo C200=amarillo
         mensaje    TYPE char255,
         bukrs      TYPE bukrs,
         gjahr      TYPE gjahr,
         monat      TYPE monat,
         cnt        TYPE i,
         belnr_ex   TYPE belnr_d,
         fichero_ex TYPE char100,
       END OF gty_errors.

**********************************************************************
** DATOS GLOBALES — TABLAS INTERNAS                                 **
**********************************************************************

* Datos en bruto leídos de ZTT_UUID_LOG
DATA: gt_zlog_raw TYPE TABLE OF ztt_uuid_log.

* KPIs globales
DATA: gs_kpi TYPE gty_kpi.

* Agrupaciones
DATA: gt_by_bukrs TYPE TABLE OF gty_by_bukrs,
      gt_by_month TYPE TABLE OF gty_by_month,
      gt_errors   TYPE TABLE OF gty_errors.

* Detalle completo (Tab 5)
DATA: gt_detail   TYPE TABLE OF ztt_uuid_log.

**********************************************************************
** NAVEGACIÓN ABAP OO (DOCKING + TOOLBAR)                           **
**********************************************************************
DATA: gv_tab_key TYPE syucomm VALUE 'TAB1'.

* Flags de inicialización por tab
DATA: gv_tab1_init   TYPE c LENGTH 1,
      gv_tab2_init   TYPE c LENGTH 1,
      gv_tab3_init   TYPE c LENGTH 1,
      gv_tab4_init   TYPE c LENGTH 1,
      gv_tab5_init   TYPE c LENGTH 1.

* Filtro activo por drill-down (KPI cards)
DATA: gv_drilldown_status TYPE char10.

* Estructura para reporte de continuidad (Gaps)
TYPES: BEGIN OF gty_continuity,
         bukrs TYPE bukrs,
         gjahr TYPE gjahr,
         m01   TYPE icon_d,
         m02   TYPE icon_d,
         m03   TYPE icon_d,
         m04   TYPE icon_d,
         m05   TYPE icon_d,
         m06   TYPE icon_d,
         m07   TYPE icon_d,
         m08   TYPE icon_d,
         m09   TYPE icon_d,
         m10   TYPE icon_d,
         m11   TYPE icon_d,
         m12   TYPE icon_d,
       END OF gty_continuity.

DATA: gt_continuity TYPE TABLE OF gty_continuity,
      gs_continuity TYPE gty_continuity.

TYPES: BEGIN OF gty_rfc_bukrs,
         rfc   TYPE char13,
         bukrs TYPE bukrs,
       END OF gty_rfc_bukrs.
DATA: gt_rfc_bukrs TYPE TABLE OF gty_rfc_bukrs.

* Contenedores principales (Substituyen a las "Screens")
DATA: go_docking       TYPE REF TO cl_gui_docking_container,
      go_main_splitter TYPE REF TO cl_gui_splitter_container,
      go_cont_toolbar  TYPE REF TO cl_gui_container,
      go_cont_main     TYPE REF TO cl_gui_container.

* Toolbar en lugar de Tabstrip
DATA: go_toolbar TYPE REF TO cl_gui_toolbar.

* Event Receiver para el Toolbar y HTML
CLASS lcl_event_receiver DEFINITION DEFERRED.
DATA: go_event_receiver TYPE REF TO lcl_event_receiver.

* Definición de la clase manejadora de eventos OO
CLASS lcl_event_receiver DEFINITION.
  PUBLIC SECTION.
    METHODS:
      on_function_selected
        FOR EVENT function_selected OF cl_gui_toolbar
        IMPORTING fcode,
      on_sapevent
        FOR EVENT sapevent OF cl_gui_html_viewer
        IMPORTING action frame getdata postdata query_table.
ENDCLASS.

**********************************************************************
** REFERENCIAS A OBJETOS GUI (CONTENIDO DE PESTAÑAS)                **
**********************************************************************

*     Tab 1: Splitter + HTML KPI + ALV Resumen
DATA: go_split_t1   TYPE REF TO cl_gui_splitter_container,
      go_split_t1_b TYPE REF TO cl_gui_splitter_container,
      go_cont_t1_t  TYPE REF TO cl_gui_container,   " Top (HTML)
      go_cont_t1_bl TYPE REF TO cl_gui_container,   " Bottom Left (ALV)
      go_cont_t1_br TYPE REF TO cl_gui_container,   " Bottom Right (ALV)
      go_html_kpi   TYPE REF TO cl_gui_html_viewer,
      go_alv_kpi    TYPE REF TO cl_gui_alv_grid,
      go_alv_kpi_2  TYPE REF TO cl_gui_alv_grid.

*     Tab 2: Splitter + ALV sociedad + Barras
DATA: go_split_t2   TYPE REF TO cl_gui_splitter_container,
      go_cont_t2_t  TYPE REF TO cl_gui_container,
      go_cont_t2_b  TYPE REF TO cl_gui_container,
      go_alv_bukrs  TYPE REF TO cl_gui_alv_grid,
      go_chart_t2   TYPE REF TO cl_gui_chart_engine.

*     Tab 3: Splitter + ALV mensual + Líneas
DATA: go_split_t3   TYPE REF TO cl_gui_splitter_container,
      go_cont_t3_t  TYPE REF TO cl_gui_container,
      go_cont_t3_b  TYPE REF TO cl_gui_container,
      go_alv_month  TYPE REF TO cl_gui_alv_grid,
      go_chart_t3   TYPE REF TO cl_gui_chart_engine.

*     Tab 4: ALV errores
DATA: go_alv_errors TYPE REF TO cl_gui_alv_grid.

*     Tab 5: ALV detalle completo
DATA: go_alv_detail TYPE REF TO cl_gui_alv_grid.
