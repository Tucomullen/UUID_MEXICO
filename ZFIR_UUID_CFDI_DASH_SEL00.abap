*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_DASH_SEL00
*&---------------------------------------------------------------------*
*& Pantalla de selección y validaciones del dashboard
*&---------------------------------------------------------------------*

**********************************************************************
** PANTALLA DE SELECCIÓN                                            **
**********************************************************************
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-b01.
  SELECT-OPTIONS: so_datum FOR ztt_uuid_log-datum_proc,   " Fecha proceso
                  so_bukrs FOR ztt_uuid_log-bukrs,        " Sociedad
                  so_gjahr FOR ztt_uuid_log-gjahr,        " Ejercicio
                  so_monat FOR ztt_uuid_log-monat,        " Mes (01-12)
                  so_uname FOR ztt_uuid_log-uname.        " Usuario
  PARAMETERS:     p_test  AS CHECKBOX DEFAULT ' '.        " Incluir simulaciones
SELECTION-SCREEN END OF BLOCK b1.

**********************************************************************
** LÓGICA PANTALLA DE SELECCIÓN                                     **
**********************************************************************
AT SELECTION-SCREEN ON so_bukrs.
  " Verificar solo las sociedades incluidas específicamente (EQ)
  LOOP AT so_bukrs WHERE sign = 'I' AND option = 'EQ'.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD so_bukrs-low
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE e398(00) WITH 'No tiene autorización para visualizar la sociedad' so_bukrs-low '' ''.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN.
* Sin validaciones obligatorias: todos los filtros son opcionales
  IF so_datum IS INITIAL AND so_bukrs IS INITIAL
     AND so_gjahr IS INITIAL AND so_monat IS INITIAL
     AND so_uname IS INITIAL.
    MESSAGE s398(00) WITH 'Sin filtros: se leerán todos los registros permitidos.' '' '' ''.
  ENDIF.
