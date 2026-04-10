*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM03
*&---------------------------------------------------------------------*
*& Tab 2: ALV por sociedad + Chart barras apiladas
*& Custom Control: CC_TAB2 en subscreen 0102
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB2
*&---------------------------------------------------------------------*
FORM frm_build_tab2.

* Contenedor principal
  go_cont_t2_t = go_cont_main.

  PERFORM frm_build_alv_bukrs.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_ALV_BUKRS
*&---------------------------------------------------------------------*
FORM frm_build_alv_bukrs.

  DATA: lt_fcat  TYPE lvc_t_fcat,
        ls_fcat  TYPE lvc_s_fcat,
        ls_layo  TYPE lvc_s_layo.

  CREATE OBJECT go_alv_bukrs
    EXPORTING i_parent = go_cont_t2_t.

  ls_layo-zebra      = 'X'.
  ls_layo-cwidth_opt = 'X'.
  ls_layo-info_fname = 'LIGHT'.

  DEFINE add_fc.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-outputlen = &3.
    ls_fcat-col_opt   = 'X'.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_fc 'BUKRS'    'Sociedad'    6.
  add_fc 'BUTXT'    'Descripción' 25.
  add_fc 'TOT_REG'  'Total'       8.
  add_fc 'TOT_OK'   'OK'          8.
  add_fc 'TOT_WARN' 'Warning'     8.
  add_fc 'TOT_ERR'  'Error'       8.
  add_fc 'PCT_OK'   '% OK'        8.

  go_alv_bukrs->set_table_for_first_display(
    EXPORTING is_layout       = ls_layo
    CHANGING  it_outtab       = gt_by_bukrs
              it_fieldcatalog = lt_fcat ).

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_RENDER_CHART_T2  (deshabilitado — CL_GUI_CHART_ENGINE
*&  no disponible en esta versión del sistema)
*&---------------------------------------------------------------------*
FORM frm_render_chart_t2.
ENDFORM.
