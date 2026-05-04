# Contexto del Proyecto: UUID_MEXICO_2
Este proyecto se encarga de la generación y validación de UUIDs para la facturación electrónica en México (CFDI).

## Reglas de ABAP
- Utiliza sintaxis ABAP moderna (7.40+ o 7.50+).
- Prefiere expresiones `VALUE`, `NEW`, e inline declarations `DATA(...)`.
- Los nombres de variables deben seguir el estándar: `lv_` (local), `gt_` (global table), `mo_` (object ref).
- Si hay errores de compilación, analiza siempre las dependencias entre los Includes y el reporte principal.

## Instrucciones para Gemini
- Cuando analices un error, busca primero en las definiciones de los tipos de datos en el Top Include.
- Si sugieres un cambio, explica el porqué basándote en el rendimiento de la base de datos (HANA).
- No me des ninguna recomendación de cambio sin antes haber analizado qué hace el programa