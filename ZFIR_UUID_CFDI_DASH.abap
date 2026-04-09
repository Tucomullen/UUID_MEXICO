*&---------------------------------------------------------------------*
*& Programa: ZFIR_UUID_CFDI_DASH
*&---------------------------------------------------------------------*
*& Dashboard histórico de métricas UUID CFDI México.
*& Accesible en cualquier momento sin necesidad de lanzar una carga.
*&---------------------------------------------------------------------*
REPORT zfir_uuid_cfdi_dash LINE-SIZE 250.

**********************************************************************
** INCLUDES                                                         **
**********************************************************************
INCLUDE zfir_uuid_cfdi_dash_top.    " Tipos, datos globales, objetos GUI
INCLUDE zfir_uuid_cfdi_dash_sel00.  " Selection screen y F4 helps
INCLUDE zfir_uuid_cfdi_dash_frm00.  " PBO/PAI Screen 100, jerarquía GUI
INCLUDE zfir_uuid_cfdi_dash_frm01.  " SELECT + agregaciones en memoria
INCLUDE zfir_uuid_cfdi_dash_frm02.  " Tab 1: KPI cards + chart pie
INCLUDE zfir_uuid_cfdi_dash_frm03.  " Tab 2: ALV por sociedad + barras
INCLUDE zfir_uuid_cfdi_dash_frm04.  " Tab 3: ALV tendencia mensual
INCLUDE zfir_uuid_cfdi_dash_frm05.  " Tab 4: ALV errores con coloring
INCLUDE zfir_uuid_cfdi_dash_frm06.  " Tab 5: ALV detalle + drill-down

**********************************************************************
** EJECUCIÓN PRINCIPAL                                              **
**********************************************************************
START-OF-SELECTION.
  PERFORM frm_cargar_datos.
  
  " 1. Escribimos algo vacío para que se instancie la pantalla de Lista (0120)
  WRITE: space.
  
  " 2. Luego construimos el UI sobre esa pantalla
  PERFORM frm_build_gui_docking.
