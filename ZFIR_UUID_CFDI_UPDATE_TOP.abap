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
  gc_tipo_interco TYPE c VALUE 'I', " Intercompany

* Estados de UUID existente
  gc_stat_empty  TYPE c VALUE '0', " Sin UUID
  gc_stat_same   TYPE c VALUE '1', " Ya existe y coincide
  gc_stat_diff   TYPE c VALUE '2'. " Ya existe y es diferente

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

* Estructura para caché de UUIDs existentes (optimización de rendimiento)
TYPES: BEGIN OF gty_uuid_cache,
         uuid   TYPE char36,
         bukrs  TYPE bukrs,
         belnr  TYPE belnr_d,
         gjahr  TYPE gjahr,
         tdname TYPE tdobname,
       END OF gty_uuid_cache.
       END OF gty_resumen_fich.

* Estructura para listado de ficheros del servidor (modo AL11)
TYPES: BEGIN OF gty_server_file,
         fullpath TYPE string,           " Ruta completa del fichero
         filename TYPE string,           " Nombre corto (sin ruta)
       END OF gty_server_file.

**********************************************************************
** DATOS GLOBALES                                                   **
**********************************************************************

* Caché de T001Z: RFC -> BUKRS (cargada una vez al inicio)
TYPES: BEGIN OF gty_t001z_cache,
         paval TYPE t001z-paval,   " RFC (valor del party)
         bukrs TYPE t001z-bukrs,   " Sociedad
       END OF gty_t001z_cache.
DATA: gt_t001z_cache TYPE HASHED TABLE OF gty_t001z_cache
                     WITH UNIQUE KEY paval.

* Caché de LFA1: RFC_EMISOR -> LIFNR (lazy-loading)
TYPES: BEGIN OF gty_lfa1_cache,
         stcd1 TYPE lfa1-stcd1,   " RFC del proveedor
         lifnr TYPE lfa1-lifnr,   " Número de proveedor (vacío = no existe)
       END OF gty_lfa1_cache.
DATA: gt_lfa1_cache TYPE HASHED TABLE OF gty_lfa1_cache
                    WITH UNIQUE KEY stcd1.

* Caché de KNA1: RFC_RECEPTOR -> KUNNR (lazy-loading)
TYPES: BEGIN OF gty_kna1_cache,
         stcd1 TYPE kna1-stcd1,   " RFC del cliente
         kunnr TYPE kna1-kunnr,   " Número de cliente (vacío = no existe)
       END OF gty_kna1_cache.
DATA: gt_kna1_cache TYPE HASHED TABLE OF gty_kna1_cache
                    WITH UNIQUE KEY stcd1.

* Tabla interna con registros del CSV
DATA: gt_csv_data TYPE TABLE OF gty_csv_data,
      gs_csv_data TYPE gty_csv_data.

* Estructura y tabla para facturas con UUID repetido
TYPES: BEGIN OF gty_factura_repetida,
         bukrs TYPE bukrs,
         belnr TYPE belnr_d,
       END OF gty_factura_repetida.
DATA: gt_facturas_repetidas TYPE HASHED TABLE OF gty_factura_repetida
                            WITH UNIQUE KEY bukrs belnr.

* Tabla de log para ALV (ejecución fichero actual)
DATA: gt_log TYPE TABLE OF gty_log,
      gs_log TYPE gty_log.

* Log consolidado de todos los ficheros (modo carpeta)
DATA: gt_log_global TYPE TABLE OF gty_log.

* Resumen por fichero (modo carpeta)
DATA: gt_resumen_fich TYPE TABLE OF gty_resumen_fich,
      gs_resumen_fich TYPE gty_resumen_fich.

* Lista de ficheros CSV encontrados en servidor (modo AL11)
DATA: gt_server_files TYPE TABLE OF gty_server_file,
      gs_server_file  TYPE gty_server_file.

* Caché de UUIDs existentes en BD (optimización de rendimiento)
DATA: gt_uuid_cache TYPE HASHED TABLE OF gty_uuid_cache
                    WITH UNIQUE KEY uuid.

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
*   text-b01 = 'Origen de datos'
*   text-b02 = 'Filtros de selección'
*   text-b03 = 'Opciones de rendimiento'
*
* SELECTION TEXTS a crear manualmente en SE38:
*   P_FICH  = 'Fichero individual (PC local)'
*   P_CARP  = 'Carpeta local (todos los CSV de 1 carpeta)'
*   P_SERV  = 'Servidor AL11 (recursivo, permite fondo)'
*   P_FILE  = 'Ruta fichero o carpeta local'
*   P_SDIR  = 'Directorio raíz en servidor (AL11)'
*   P_TEST  = 'Modo simulación (no graba)'
*   P_WAIT  = 'Pausa entre ficheros (segundos)'
*   S_BUKRS = 'Sociedad'
*   S_BLART = 'Clase de documento'

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-b01.
  PARAMETERS: p_fich RADIOBUTTON GROUP g_md DEFAULT 'X'
                USER-COMMAND md_change,                      " Fichero individual
              p_carp RADIOBUTTON GROUP g_md,                 " Carpeta local
              p_serv RADIOBUTTON GROUP g_md.                 " Servidor AL11
  SELECTION-SCREEN SKIP 1.
  PARAMETERS: p_file TYPE rlgrap-filename MODIF ID lcl.     " Ruta local
  PARAMETERS: p_sdir TYPE char255         MODIF ID srv.     " Ruta servidor
  SELECTION-SCREEN SKIP 1.
  PARAMETERS: p_test AS CHECKBOX DEFAULT 'X'.               " Modo simulación
  PARAMETERS: p_reproc AS CHECKBOX DEFAULT ' '.             " Reprocesar errores/warnings
  PARAMETERS: p_repet  AS CHECKBOX DEFAULT ' '.             " Solo reprocesar repetidos
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-b02.
  SELECT-OPTIONS: s_bukrs FOR bkpf-bukrs,                   " Sociedad (opcional)
                  s_blart FOR bkpf-blart.                   " Clase de documento
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE text-b03.
  PARAMETERS: p_wait TYPE i DEFAULT 0.                      " Pausa entre ficheros (seg)
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b_inf WITH FRAME.
  SELECTION-SCREEN COMMENT /1(79) g_des_t.
  SELECTION-SCREEN SKIP 1.
  SELECTION-SCREEN COMMENT /1(79) g_des_1.
  SELECTION-SCREEN COMMENT /1(79) g_des_2.
  SELECTION-SCREEN COMMENT /1(79) g_des_3.
  SELECTION-SCREEN COMMENT /1(79) g_des_4.
SELECTION-SCREEN END OF BLOCK b_inf.
