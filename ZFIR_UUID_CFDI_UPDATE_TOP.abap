*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_TOP
*&---------------------------------------------------------------------*
*& Tipos de datos, datos globales, constantes y pantalla de selección
*&---------------------------------------------------------------------*

**********************************************************************
** TABLAS PARA SELECT-OPTIONS                                       **
**********************************************************************
TABLES: bkpf.

**********************************************************************
** CONSTANTES GLOBALES                                              **
**********************************************************************
CONSTANTS:
  gc_object    TYPE tdobject VALUE 'BELEG',   " Objeto texto SAPscript
  gc_tdid      TYPE tdid     VALUE 'YUUD',    " ID texto para UUID
  gc_language  TYPE spras    VALUE 'S',        " Idioma español
  gc_party     TYPE char10   VALUE 'MX_RFC',   " Party en T001Z para RFC MX
  gc_actvt_mod TYPE char2    VALUE '10',       " Actividad: Modificar
  gc_auth_obj  TYPE char20   VALUE 'F_BKPF_BUK', " Objeto autorización

* Semáforos para ALV
  gc_icon_ok   TYPE icon_d   VALUE '@08@',     " Semáforo verde
  gc_icon_warn TYPE icon_d   VALUE '@09@',     " Semáforo amarillo
  gc_icon_err  TYPE icon_d   VALUE '@0A@',     " Semáforo rojo

* Tipos de factura
  gc_tipo_compra TYPE c VALUE 'C',  " Compra
  gc_tipo_venta  TYPE c VALUE 'V',  " Venta
  gc_tipo_interco TYPE c VALUE 'I'. " Intercompany

**********************************************************************
** TIPOS DE DATOS                                                   **
**********************************************************************

* Estructura para datos leídos del CSV
TYPES: BEGIN OF gty_csv_data,
         rfc_emisor       TYPE char13,   " RFC de la sociedad emisora
         rfc_receptor     TYPE char13,   " RFC del receptor
         serie            TYPE char10,   " Serie del CFDI
         folio            TYPE char20,   " Folio del CFDI
         fecha            TYPE char30,   " Fecha facturación (texto)
         total            TYPE char25,   " Total con separador de miles
         tipocomprobante  TYPE char1,    " I=Ingreso, E=Egreso, P=Pago, T=Traslado
         uuid             TYPE char36,   " UUID del CFDI
       END OF gty_csv_data.

* Estructura para documentos BKPF encontrados
TYPES: BEGIN OF gty_bkpf,
         bukrs TYPE bukrs,
         belnr TYPE belnr_d,
         gjahr TYPE gjahr,
         xblnr TYPE xblnr1,
         blart TYPE blart,
         budat TYPE budat,
         bldat TYPE bldat,
       END OF gty_bkpf.

* Estructura para líneas de texto (compatible con READ_TEXT/SAVE_TEXT)
TYPES: BEGIN OF gty_tline,
         tdformat(2) TYPE c,
         tdline(132) TYPE c,
       END OF gty_tline.

* Estructura para log de salida ALV
TYPES: BEGIN OF gty_log,
         icon         TYPE icon_d,       " Semáforo
         fichero      TYPE char100,      " Fichero CSV origen
         bukrs        TYPE bukrs,        " Sociedad
         belnr        TYPE belnr_d,      " Nº documento contable
         gjahr        TYPE gjahr,        " Ejercicio
         rfc_emisor   TYPE char13,       " RFC emisor del CSV
         rfc_receptor TYPE char13,       " RFC receptor del CSV
         serie        TYPE char10,       " Serie del CSV
         folio        TYPE char20,       " Folio del CSV
         tipo         TYPE char1,        " Tipo comprobante (I/E/P/T)
         tipo_fac     TYPE char1,        " Tipo factura (C/V/I)
         uuid         TYPE char36,       " UUID asignado
         uuid_previo  TYPE char36,       " UUID previo (si existía)
         mensaje      TYPE char255,      " Descripción del resultado
         budat        TYPE budat,        " Fecha contabilización
         bldat        TYPE bldat,        " Fecha del documento
         monat        TYPE monat,        " Mes (derivado de BUDAT)
         blart        TYPE blart,        " Clase de documento
         test_mode    TYPE char1,        " X = ejecución simulación
       END OF gty_log.

* Estructura para resumen por fichero (modo carpeta)
TYPES: BEGIN OF gty_resumen_fich,
         fichero  TYPE char100,          " Nombre del fichero
         total    TYPE i,               " Total registros
         ok       TYPE i,               " Actualizados OK
         warning  TYPE i,               " Con UUID previo
         error    TYPE i,               " Con error
       END OF gty_resumen_fich.

**********************************************************************
** DATOS GLOBALES                                                   **
**********************************************************************

* Tabla interna con registros del CSV
DATA: gt_csv_data TYPE TABLE OF gty_csv_data,
      gs_csv_data TYPE gty_csv_data.

* Tabla de log para ALV (ejecución fichero actual)
DATA: gt_log TYPE TABLE OF gty_log,
      gs_log TYPE gty_log.

* Log consolidado de todos los ficheros (modo carpeta)
DATA: gt_log_global TYPE TABLE OF gty_log.

* Resumen por fichero (modo carpeta)
DATA: gt_resumen_fich TYPE TABLE OF gty_resumen_fich,
      gs_resumen_fich TYPE gty_resumen_fich.

* Fichero en proceso actualmente
DATA: gv_fichero_actual TYPE string.

* Contadores por ejecución (un fichero)
DATA: gv_total     TYPE i,  " Total registros procesados
      gv_ok        TYPE i,  " Registros actualizados OK
      gv_warning   TYPE i,  " Registros con UUID previo
      gv_error     TYPE i.  " Registros con error

* Contadores globales acumulados (todos los ficheros en modo carpeta)
DATA: gv_g_total    TYPE i,  " Total global
      gv_g_ok       TYPE i,  " OK global
      gv_g_warning  TYPE i,  " Warning global
      gv_g_error    TYPE i,  " Error global
      gv_g_ficheros TYPE i.  " Nº ficheros procesados

**********************************************************************
** PANTALLA DE SELECCIÓN                                            **
**********************************************************************
* TEXT ELEMENTS a crear manualmente en SE38:
*   text-b01 = 'Archivo de entrada'
*   text-b02 = 'Filtros de selección'
*
* SELECTION TEXTS a crear manualmente en SE38:
*   P_FICH  = 'Fichero individual'
*   P_CARP  = 'Carpeta de ficheros (procesa todos los CSV)'
*   P_FILE  = 'Ruta (fichero o carpeta)'
*   P_TEST  = 'Modo simulación (no graba)'
*   S_BUKRS = 'Sociedad'
*   S_BLART = 'Clase de documento'

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-b01.
  PARAMETERS: p_fich RADIOBUTTON GROUP g_md DEFAULT 'X',   " Fichero individual
              p_carp RADIOBUTTON GROUP g_md.               " Carpeta de ficheros
  PARAMETERS: p_file TYPE rlgrap-filename OBLIGATORY.      " Ruta CSV o carpeta
  PARAMETERS: p_test AS CHECKBOX DEFAULT 'X'.              " Modo simulación
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-b02.
  SELECT-OPTIONS: s_bukrs FOR bkpf-bukrs,                   " Sociedad (opcional)
                  s_blart FOR bkpf-blart.                   " Clase de documento
SELECTION-SCREEN END OF BLOCK b2.
