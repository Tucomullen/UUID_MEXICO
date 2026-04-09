# Instrucciones de instalación — ZFIR_UUID_CFDI_UPDATE

## Resumen de objetos a crear

| Nº | Objeto | Nombre | Transacción |
|----|--------|--------|-------------|
| 1 | Programa principal | `ZFIR_UUID_CFDI_UPDATE` | SE38 |
| 2 | Include | `ZFIR_UUID_CFDI_UPDATE_TOP` | SE38 |
| 3 | Include | `ZFIR_UUID_CFDI_UPDATE_SEL00` | SE38 |
| 4 | Include | `ZFIR_UUID_CFDI_UPDATE_FRM00` | SE38 |
| 5 | Include | `ZFIR_UUID_CFDI_UPDATE_FRM01` | SE38 |
| 6 | Include | `ZFIR_UUID_CFDI_UPDATE_FRM02` | SE38 |
| 7 | Transacción | (ej. `Z272` o la que esté libre) | SE93 |
| 8 | Text Elements | 2 textos de bloque | SE38 → Ir a → Elementos de texto |
| 9 | Selection Texts | 4 textos de parámetro | SE38 → Ir a → Elementos de texto |

---

## Paso 1 — Crear los Includes (SE38)

Crear **primero** los 5 includes, ya que el programa principal los referencia.

Para cada uno:
1. Ir a SE38
2. Escribir el nombre del include (ej. `ZFIR_UUID_CFDI_UPDATE_TOP`)
3. Pulsar **Crear**
4. Tipo: **Include**
5. Título: según la tabla de abajo
6. Pegar el código completo del archivo correspondiente
7. Asignar al **paquete** de desarrollo (ej. `ZDEV_ED2300_FI`)
8. **Activar**

| Include | Título |
|---------|--------|
| `ZFIR_UUID_CFDI_UPDATE_TOP` | Tipos, datos globales y pantalla selección |
| `ZFIR_UUID_CFDI_UPDATE_SEL00` | Lógica pantalla selección (F4 CSV) |
| `ZFIR_UUID_CFDI_UPDATE_FRM00` | Lectura y parseo CSV local |
| `ZFIR_UUID_CFDI_UPDATE_FRM01` | Localización documentos BKPF/BSEG |
| `ZFIR_UUID_CFDI_UPDATE_FRM02` | Grabación UUID y salida ALV |

---

## Paso 2 — Crear el Programa principal (SE38)

1. Ir a SE38
2. Escribir `ZFIR_UUID_CFDI_UPDATE`
3. Pulsar **Crear**
4. Tipo: **Programa ejecutable**
5. Título: `Actualización masiva UUID CFDI desde CSV`
6. Pegar el código del archivo `ZFIR_UUID_CFDI_UPDATE.abap`
7. Asignar al mismo paquete
8. **Activar**

---

## Paso 3 — Crear Text Elements y Selection Texts

En SE38 con el programa `ZFIR_UUID_CFDI_UPDATE` abierto:

### Text Elements (Ir a → Elementos de texto → Símbolos de texto)

| Símbolo | Texto |
|---------|-------|
| `B01` | `Archivo de entrada` |
| `B02` | `Filtros de selección` |

### Selection Texts (Ir a → Elementos de texto → Textos de selección)

| Nombre | Texto |
|--------|-------|
| `P_FILE` | `Archivo CSV` |
| `P_TEST` | `Modo simulación (no graba)` |
| `S_BUKRS` | `Sociedad` |
| `S_BLART` | `Clase de documento` |

**Activar** los elementos de texto.

---

## Paso 4 — Crear la Transacción (SE93)

1. Ir a SE93
2. Código de transacción: elegir uno disponible (ej. `Z272`)
3. Texto breve: `Actualización masiva UUID CFDI CSV`
4. Tipo: **Programa y dynpro (transacción de report)**
5. Programa: `ZFIR_UUID_CFDI_UPDATE`
6. Grabar y activar

---

## Paso 5 — Verificar dependencias del sistema

Antes de ejecutar, confirmar que existen en el sistema:

| Dependencia | Cómo verificar | Notas |
|-------------|---------------|-------|
| **Text ID `YUUD`** para objeto `BELEG` | SE75 → Objeto de texto `BELEG` → IDs de texto | Ya creado para ZFII_MEXICO_UIID |
| **Tabla `T001Z`** con `PARTY = MX_RFC` | SE16 → T001Z → PARTY = `MX_RFC` | Debe tener las 14 sociedades MX |
| **Proveedores con RFC** | SE16 → LFA1 → campo STCD1 | RFC de proveedores mexicanos |
| **Clientes con RFC** | SE16 → KNA1 → campo STCD1 | RFC de clientes mexicanos |
| **Autorización `F_BKPF_BUK`** | SU53 tras ejecutar | El usuario necesita actividad 10 |
| **Clase de mensajes `ZFI`** | SE91 → ZFI | Crear si no existe (vacía vale) |

---

## Paso 6 — Primera ejecución (prueba)

1. Ejecutar transacción o `SA38` → `ZFIR_UUID_CFDI_UPDATE`
2. Dejar marcado **Modo simulación** (viene por defecto)
3. Seleccionar un archivo CSV de prueba
4. Opcionalmente restringir con S_BUKRS / S_BLART
5. Ejecutar
6. Revisar el ALV de resultados:
   - **Verde**: Documento localizado, se actualizaría el UUID
   - **Amarillo**: Documento ya tiene UUID (no se sobrescribe)
   - **Rojo**: Error (documento no encontrado, no unívoco, etc.)
7. Si los resultados son correctos, desmarcar "Modo simulación" y ejecutar de nuevo

---

## Compatibilidad con ZFII_MEXICO_UIID (ZFI271)

Ambos programas usan **exactamente el mismo mecanismo** de almacenamiento:

```
SAVE_TEXT / READ_TEXT
  OBJECT  = 'BELEG'
  ID      = 'YUUD'
  LANGUAGE = 'S'
  NAME    = <BUKRS><BELNR><GJAHR>
```

Un UUID grabado por un programa es legible por el otro. No hay conflicto.

---

## Formato del CSV esperado

```
EmisorRFC;ReceptorRFC;Serie;Folio;FechaFacturacion;Total;TipoComprobante;UUID
```

- Separador: punto y coma (`;`)
- Primera línea: cabecera (se ignora)
- Codificación: UTF-8 (maneja BOM automáticamente)
- Serie y Folio pueden venir vacíos
- UUID debe ser de 36 caracteres con guiones

---

## Troubleshooting

| Problema | Causa probable | Solución |
|----------|---------------|----------|
| "RFC proveedor no encontrado en LFA1" | El RFC del emisor no está en LFA1-STCD1 | Verificar datos maestros del proveedor |
| "RFC sociedad no encontrado en T001Z" | Falta entrada en T001Z | Crear entrada PARTY=MX_RFC con el RFC |
| "No se encuentra documento compra/venta" | Folio no coincide con XBLNR | Revisar cómo se almacenó el folio en BKPF |
| "Documento no unívoco" | Varios documentos con el mismo folio | Añadir filtro por S_BLART para restringir |
| "No autorizado" | Falta autorización F_BKPF_BUK | Asignar perfil con actividad 10 para la sociedad |
| "UUID ya existente" | El documento ya fue procesado | Normal si se reejecutó el CSV. Es warning, no error |
