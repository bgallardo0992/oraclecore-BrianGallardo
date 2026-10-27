# AI-LOG — Bitácora de uso de IA

Última actualización: 2026-10-26 (hasta el commit `b75dc94`, Fase B). Este archivo se ampliará en cada fase.

## 1. Herramientas utilizadas

- **Claude Code** (extensión de VS Code; modelo Claude Sonnet 5.5): genera el código, ejecuta los scripts en el contenedor Docker local mediante `docker exec … sqlplus`, hace los commits y redacta la documentación.
- **DBeaver**: cliente SQL del candidato; allí ejecuta las pruebas y comparte capturas como evidencia.
- **Contexto entregado a la IA:** el archivo `context.md` (prompt maestro de desarrollo guiado, fuera del repositorio) y el enunciado `Prueba_Tecnica_Oracle_Core_Bancario_v4.md`. No se proporcionó un `CLAUDE.md` de proyecto; el `CLAUDE.md` global del usuario solo contiene la configuración de otra herramienta (graphify) y no influye en este trabajo.
- `instrucciones.md` (fuera del repositorio): guía paso a paso con tiempos que la IA mantuvo durante el desarrollo.

## 2. Cómo trabajamos

1. **Una fase por vez**, como exige el prompt maestro: Fase 0 (entorno) → A.1 → A.2 → A.3 → A.4 → B. La IA no avanza a la siguiente fase sin que el candidato comparta resultados.
2. **Doble verificación:** la IA primero ejecuta el código en SQL*Plus dentro del contenedor y revisa la salida; después el candidato lo ejecuta en DBeaver y comparte capturas. Lo que solo se verificó en SQL*Plus se declara así en `STATUS.md`.
3. **Esqueleto primero:** el package se compiló con cuerpos vacíos (`-20999 no implementado`) antes de implementar el CRUD.
4. **Un commit por fase**, con mensaje descriptivo; el candidato pide el commit cuando considera correcta la fase.
5. **Sin secretos en el repositorio:** se revisó con `grep` que ninguna contraseña estuviera en los archivos antes de cada commit inicial y al redactar este registro.
6. La IA ejecutó comandos sobre el Docker local del candidato (crear usuario, cargar datos, compilar, correr pruebas) siguiendo el pedido «ejecuta las instrucciones».

## 3. Decisiones técnicas y justificación

| Decisión | Elección | Justificación |
|---|---|---|
| Auditoría | Triggers `TRG_TTEM_CATALOG_AUD` / `TRG_TTEM_ITEM_AUD` (BEFORE INSERT OR UPDATE) | Una modificación directa por SQL (el problema de la Sección D) también queda auditada y no se puede alterar `created_*`. Limitación: sin valores anteriores (`TTEM_AUDIT_LOG` no implementada). |
| Claves e índices | Secuencias `SEQ_TTEM_CATALOG` / `SEQ_TTEM_ITEM`; sin índice extra sobre `catalog_id` | `UK_TTEM_ITEM_CATALOG_CODE (catalog_id, item_code)` ya cubre la FK. |
| Códigos | CHECK `codigo = UPPER(TRIM(codigo))` | La base rechaza códigos sin normalizar; coherente con la carga A.5. |
| Eliminación | **Lógica** (`status = 'I'`), idempotente | Conserva trazabilidad y es reversible; implica que un código eliminado no se puede reinsertar. |
| Excepciones | Rango -20100…-20199 negocio y -20900 técnico; tabla en el README | Permite distinguir un error de negocio (ítem inexistente) de uno técnico. |
| `WHEN OTHERS` | Solo en las 3 operaciones de escritura; siempre `ROLLBACK TO` el savepoint y relanzar (`RAISE`, o `-20900` con `keep_errors = TRUE`) | Cumple la regla del enunciado: nunca oculta el error. |
| Duplicados | Se captura `DUP_VAL_ON_INDEX` de la UK; no hay `SELECT` previo | La UK es la única garantía correcta ante concurrencia. |
| Control transaccional del package | No hace `COMMIT`; savepoint propio por operación | El invocador decide la transacción. Para la Sección C se mantendrá el mismo criterio (pendiente de implementar). |
| JSON | `JSON_OBJECT … NULL ON NULL RETURNING CLOB` | Función nativa, escapa caracteres especiales, mantiene las claves con valor `null`. |
| Cuenta inexistente (B) | 0 filas, sin error | Comportamiento natural de un `SELECT`. |
| Nombre normalizado (B) | `INITCAP` solo en personas naturales; la razón social solo se limpia | Respeta `S.A.C.` / `E.I.R.L.`. Limitación: `De`/`Del` quedan en mayúscula. |
| Regla de catálogo inactivo | **Decisión del candidato:** no admite ítems nuevos (`-20107`) | La IA había propuesto dejarlo permitido por no estar en el enunciado; el candidato pidió convertirlo en regla. |
| Supuestos de datos | `valid_from` obligatorio; `COM_MANT = '12.50'` | El enunciado no los define; ver `STATUS.md`. |

## 4. Prompts representativos

Texto exacto de los mensajes del candidato, qué devolvió la herramienta y qué se hizo con ello.

| # | Prompt del candidato | Respuesta de la IA | Qué se hizo |
|---|---|---|---|
| 1 | «vamos a iniciar el desarrollo del @context.md paso a paso segun se indica. tener presente que para las pruebas voy a usar DBeawer.  creame un archivo(instrucciones.md) y me vas indicando que debo hacer. paso a paso. segun la etapa en la que estamos. marca con tiempo cada instruccion.» | Análisis de la Fase 0, estructura de carpetas, extracción de los scripts del Anexo B a `setup/` y `instrucciones.md` con tiempos estimados. | Se adoptó el flujo por fases. |
| 2 | «ejecuta las  @instrucciones.md» | Ejecutó los pasos 0.2–0.9 en el Docker local; detectó dos problemas (ver sección 5). | Entorno listo con las cantidades esperadas. |
| 3 | «pasamos a la siguiente fase. @context.md» | Fase A.1: tablas, triggers, datos iniciales y 10 pruebas de integridad. | El candidato verificó T1–T10 en DBeaver. |
| 4 | «valida la estructura del proyecto, de qui en adelante trabajamos sobre la estructura actual en oraclecore-BrianGallardo.» (con captura de `ORA-00922`) | Validó la estructura y quitó los comandos de SQL*Plus de los scripts propios. | Trabajo continuado dentro de `oraclecore-BrianGallardo/`. |
| 5 | «un catálogo inactivo no impide insertar ítems, porque el enunciado no lo pide. crear una regla. Realizar commit de A.3» | Nuevo código `-20107`, `validar_catalogo_activo`, pruebas V16/V17 y commit de A.3. | Decisión de negocio del candidato incorporada. |
| 6 | «no me esta escribiendo nada en la vista de salida.» | Diagnóstico paso a paso del panel de salida de DBeaver. | El candidato activó la salida del servidor y las pruebas J1–J6 se vieron en DBeaver. |
| 7 | «escribe los archivos faltantes y anota el registro de como estamos trabajando, en cada archivo correspondiente.» | README, STATUS, AI-LOG y `connection.env.example`. | Este archivo. |

## 5. Código de IA rechazado o corregido

1. **Scripts del Anexo B con líneas en blanco dentro de las sentencias** (error de la IA al extraerlos del documento): SQL*Plus trata la línea en blanco como fin de sentencia y la carga falló con `ORA-00942`/`SP2-0734`. Se quitaron las líneas en blanco, se recreó el usuario y se repitió la carga; cantidades correctas.
2. **`ACCEPT … HIDE` del script `00_setup_usuario.sql`** no lee la contraseña sin terminal interactiva (`ORA-01741`). La IA creó el usuario con las mismas sentencias `CREATE USER`/`GRANT`. El README indica ejecutarlo con `docker exec -it`.
3. **`SET SERVEROUTPUT ON`, `SET DEFINE OFF` y `PROMPT` en scripts propios:** DBeaver los envía a Oracle y falla (`ORA-00922`). Se eliminaron de `ddl/` y `scripts/`.
4. **Línea `/` tras el bloque anónimo de pruebas:** produjo `ORA-00900` en DBeaver. Se quitó de los scripts de prueba (los `CREATE` de tipos, triggers y packages sí la llevan).
5. **Manejo de errores provisional de A.2:** `RAISE NO_DATA_FOUND` y errores de integridad crudos (`ORA-00001`). Se reemplazaron en A.3 por excepciones de negocio con código propio; la prueba P5 se actualizó.
6. **Prueba V13 mal planteada (A.3):** pasaba un valor de 250 caracteres a un atributo del Object Type de 200; el error saltaba al construir el objeto, no en el package. Se movió a `test_a3_error_tecnico.sql`, que fuerza una falla de entorno agotando `SEQ_TTEM_ITEM` y la restaura.
7. **Prueba J6 (A.4):** el parámetro `OUT` conservaba el JSON anterior porque Oracle no lo copia ante una excepción. La prueba ahora lo pone en nulo antes de llamar; el comportamiento queda documentado.
8. **Patrones vigilados:** no se usa `WHEN OTHERS THEN NULL`; todos los `WHEN OTHERS` hacen rollback y relanzan; no hay SQL dinámico con datos del usuario (el único `EXECUTE IMMEDIATE`, en la prueba del error técnico, concatena un número leído del diccionario de datos y restaura la secuencia aunque falle).

## 6. Estimación de participación de la IA

Estimación aproximada, a confirmar por el candidato: **~95 % del código, las pruebas y la documentación fue generado por la IA**; **~5 % corresponde al candidato**, que dirigió el trabajo fase por fase, ejecutó y verificó las pruebas en DBeaver, detectó problemas de su entorno (salida del servidor, ORA-00922 / ORA-00900), decidió la regla de catálogo inactivo y pidió los commits. Cada bloque de código debe poder ser explicado por el candidato en la revisión técnica.
