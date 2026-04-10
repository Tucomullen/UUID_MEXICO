*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_FRM05
*&---------------------------------------------------------------------*
*& Tab 4: ALV errores agrupados con coloring por fila
*& Custom Control: CC_TAB4 en subscreen 0104
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_BUILD_TAB4
*&---------------------------------------------------------------------*
FORM frm_build_tab4.

  DATA: lt_fcat TYPE lvc_t_fcat,
        ls_fcat TYPE lvc_s_fcat,
        ls_layo TYPE lvc_s_layo.

  CREATE OBJECT go_alv_errors
    EXPORTING i_parent = go_cont_main.

  ls_layo-zebra      = 'X'.
  ls_layo-cwidth_opt = 'X'.
  ls_layo-info_fname = 'ROWCOLOR'.

  DEFINE add_fc.
    CLEAR ls_fcat.
    ls_fcat-fieldname = &1.
    ls_fcat-coltext   = &2.
    ls_fcat-outputlen = &3.
    ls_fcat-col_opt   = 'X'.
    APPEND ls_fcat TO lt_fcat.
  END-OF-DEFINITION.

  add_fc 'CNT'        'Frecuencia'  8.
  add_fc 'MENSAJE'    'Mensaje'    50.
  add_fc 'BUKRS'      'Sociedad'    6.
  add_fc 'GJAHR'      'Ejercicio'   6.
  add_fc 'MONAT'      'Mes'         4.
  add_fc 'BELNR_EX'   'Doc.Ejemplo' 10.
  add_fc 'FICHERO_EX' 'Fichero'    30.

* Campo de coloring: técnico, no visible
  CLEAR ls_fcat.
  ls_fcat-fieldname = 'ROWCOLOR'.
  ls_fcat-tech      = 'X'.
  APPEND ls_fcat TO lt_fcat.

  go_alv_errors->set_table_for_first_display(
    EXPORTING is_layout       = ls_layo
    CHANGING  it_outtab       = gt_errors
              it_fieldcatalog = lt_fcat ).

ENDFORM.
