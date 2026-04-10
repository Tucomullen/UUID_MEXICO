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
    ls_fcat-just      = &4.
    ls_fcat-col_opt   = 'X'.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_fc 'BUKRS'  'Sociedad'   6  'L'.
  add_fc 'GJAHR'  'Ejercicio'  6  'C'.
  add_fc 'M01'    'Ene'        4  'C'.
  add_fc 'M02'    'Feb'        4  'C'.
  add_fc 'M03'    'Mar'        4  'C'.
  add_fc 'M04'    'Abr'        4  'C'.
  add_fc 'M05'    'May'        4  'C'.
  add_fc 'M06'    'Jun'        4  'C'.
  add_fc 'M07'    'Jul'        4  'C'.
  add_fc 'M08'    'Ago'        4  'C'.
  add_fc 'M09'    'Sep'        4  'C'.
  add_fc 'M10'    'Oct'        4  'C'.
  add_fc 'M11'    'Nov'        4  'C'.
  add_fc 'M12'    'Dic'        4  'C'.

  go_alv_month->set_table_for_first_display(
    EXPORTING is_layout       = ls_layo
    CHANGING  it_outtab       = gt_continuity
              it_fieldcatalog = lt_fcat ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_CHART_T3  (deshabilitado — CL_GUI_CHART_ENGINE
*&  no disponible en esta versión del sistema)
*&---------------------------------------------------------------------*
FORM frm_render_chart_t3.
ENDFORM.
