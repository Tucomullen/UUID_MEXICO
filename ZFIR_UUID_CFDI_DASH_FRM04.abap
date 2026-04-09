*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM04
*&---------------------------------------------------------------------*
*& Tab 3: ALV tendencia mensual + Chart líneas
*& Custom Control: CC_TAB3 en subscreen 0103
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB3
*&---------------------------------------------------------------------*
FORM frm_build_tab3.

* Contenedor principal
  go_cont_t3_t = go_cont_main.

  PERFORM frm_build_alv_month.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_ALV_MONTH
*&---------------------------------------------------------------------*
FORM frm_build_alv_month.

  DATA: lt_fcat TYPE lvc_t_fcat,
        ls_fcat TYPE lvc_s_fcat,
        ls_layo TYPE lvc_s_layo.

  CREATE OBJECT go_alv_month
    EXPORTING i_parent = go_cont_t3_t.

  ls_layo-zebra      = 'X'.
  ls_layo-cwidth_opt = 'X'.

  DEFINE add_fc.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-outputlen = &3.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_fc 'GJAHR'    'Ejercicio' 6.
  add_fc 'MONAT'    'Mes'       4.
  add_fc 'PERIODO'  'Período'   8.
  add_fc 'TOT_REG'  'Total'     8.
  add_fc 'TOT_OK'   'OK'        8.
  add_fc 'TOT_WARN' 'Warning'   8.
  add_fc 'TOT_ERR'  'Error'     8.

  go_alv_month->set_table_for_first_display(
    EXPORTING is_layout       = ls_layo
    CHANGING  it_outtab       = gt_by_month
              it_fieldcatalog = lt_fcat ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_CHART_T3  (deshabilitado — CL_GUI_CHART_ENGINE
*&  no disponible en esta versión del sistema)
*&---------------------------------------------------------------------*
FORM frm_render_chart_t3.
ENDFORM.
