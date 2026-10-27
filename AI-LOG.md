# AI-LOG — Bitácora de uso de IA

Última actualización: 2026-10-26 (hasta el commit `b75dc94`, Fase B). Este archivo se ampliará en cada fase.

## 1. Herramientas utilizadas

- **Claude Code** (extensión de VS Code; modelo Claude Sonnet 5.5): genera el código, ejecuta los scripts en el contenedor Docker local mediante `docker exec … sqlplus`, hace los commits y redacta la documentación.
- **DBeaver**: cliente SQL del candidato; allí ejecuta las pruebas y comparte capturas como evidencia.
- **Contexto entregado a la IA:** el archivo `context.md` (prompt maestro de desarrollo guiado, incluido en el repositorio por decisión del candidato como equivalente del `CLAUDE.md`) y el enunciado `Prueba_Tecnica_Oracle_Core_Bancario_v4.md`. No se proporcionó un `CLAUDE.md` de proyecto; el `CLAUDE.md` global del usuario solo contiene la configuración de otra herramienta (graphify) y no influye en este trabajo.
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
| Control transaccional de la transferencia (C) | El **invocador** hace `COMMIT`/`ROLLBACK`; `transferir` solo usa `SAVEPOINT sp_transferir` y `ROLLBACK TO` ante error | Evita confirmar sin querer trabajo ajeno del invocador. El rollback a savepoint deshace débito, acreditación e insert de esa llamada y libera sus bloqueos, sin tocar lo previo. |
| Bloqueo de cuentas (C) | Dos `SELECT … FOR UPDATE` separados, primero la cuenta con menor número | Un solo `SELECT … ORDER BY … FOR UPDATE` no garantiza el orden en que se bloquean las filas; con dos consultas el orden es explícito y evita deadlocks `A→B` / `B→A`. |
| Idempotencia (C) | Se consulta la referencia antes de bloquear y se traduce `DUP_VAL_ON_INDEX` en el insert | Rechazo limpio de la repetición y protección real ante la carrera entre sesiones. |
| Falla simulada (C) | Se lanza `-20208` entre el débito y la acreditación, antes de pedir el id a `SEQ_CORE_TRX` | La secuencia no se consume en ese camino; igualmente los valores de una secuencia nunca se revierten con `ROLLBACK`. |
| Códigos de la liquidación | -20200…-20209 negocio y -20901 técnico | Separados del rango del catálogo (-20100…-20107, -20900). |
| Carga masiva (A.5) | `FORALL ... SAVE EXCEPTIONS` para insertar; duplicados del lote con un arreglo asociativo (gana el menor `stg_id`); duplicados contra lo existente por la UK; cursor `FOR UPDATE NOWAIT` | La UK es la garantía real ante concurrencia; el arreglo da un motivo más claro dentro del lote y funciona entre bloques de `LIMIT`. Sin `COMMIT` dentro del bucle (un `COMMIT` invalidaría el cursor `FOR UPDATE`): decide el invocador. |
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
| 8 | «realiza el commit de los archivos y procede con la siguiente fase.» | Commit de la documentación y Fase C: `PKG_CORE_SETTLEMENT`, 16 casos automáticos, los 6 casos del enunciado y un script para restablecer datos. | El candidato verificó en DBeaver la prueba automática y los 6 casos (tras corregir el script automático, ver sección 5, punto 8). |
| 9 | «siguiente fase» (tras confirmar la Fase C en DBeaver) | Fase D: propuesta de mejora de 11 puntos en el README, apoyada en lo construido (`TYP_TTEM_ITEM`, `PKG_TTEM_CATALOG`, triggers de auditoría, eliminación lógica). | Pendiente de revisión por el candidato; plazos y metas son estimaciones de la IA. |
| 10 | Observaciones técnicas del candidato sobre la propuesta D: (1) la validación «en seco» con SAVEPOINT/ROLLBACK TO no es una simulación sin efectos (secuencias, triggers); (2) la auditoría debe registrar la solicitud origen con valores anteriores y nuevos, y la reversión debe ser un cambio compensatorio aprobado, sin modificar el historial. | La IA estuvo de acuerdo, añadió matices (revalidar al aplicar; comprobar que el valor actual sea el que dejó el cambio original; derivar «revertida» sin cambiar la solicitud original) y reescribió los puntos 3 a 7. | Propuesta D corregida: validaciones solo lectura expuestas por el package y reversión compensatoria con `TTEM_AUDIT_LOG` de solo inserción. |
| 11 | «siguiente fase» (tras el commit de la Fase D y los archivos de contexto) | Fase A.5 completa: `TTEM_LOAD_ERROR`, `PKG_TTEM_LOAD`, pruebas con `LIMIT 4` y `LIMIT 200`, carga real y restablecimiento, y prueba de concurrencia con dos sesiones. | El candidato verificó en DBeaver la prueba automática y el restablecimiento. Incidente de la prueba de concurrencia descrito en la sección 5, punto 9. |
| 12 | «Mantener registro real de participacion de IA. mantener el @oraclecore-BrianGallardo/context.md como contexto del agente, luego de verificar la propuesta D, me parece bien. realiza la prueba de la instalacion desde 0, para validar que todo esta correcto.» | La IA mantuvo la estimación de participación sin cambios, anotó la aprobación de la propuesta D y del `context.md`, y ejecutó la instalación completa en un contenedor nuevo siguiendo el README. | Resultado en `STATUS.md`. Dos fallos iniciales fueron del script de prueba de la IA (conversión de rutas de Windows al copiar archivos al contenedor), no del repositorio; se corrigió el script y se repitió desde un contenedor limpio. |

Nota de transparencia (Fase C): para probar `casos_c_manual.sql` la IA lo ejecutó una vez en la base del candidato (con `COMMIT` del caso 1) y luego aplicó `restablecer_casos_c.sql`; los datos volvieron a 11 movimientos y saldos 5250,00 / 350,50. La secuencia `SEQ_CORE_TRX` ya no está en 1000 porque las secuencias no se revierten.

## 5. Código de IA rechazado o corregido

1. **Scripts del Anexo B con líneas en blanco dentro de las sentencias** (error de la IA al extraerlos del documento): SQL*Plus trata la línea en blanco como fin de sentencia y la carga falló con `ORA-00942`/`SP2-0734`. Se quitaron las líneas en blanco, se recreó el usuario y se repitió la carga; cantidades correctas.
2. **`ACCEPT … HIDE` del script `00_setup_usuario.sql`** no lee la contraseña sin terminal interactiva (`ORA-01741`). La IA creó el usuario con las mismas sentencias `CREATE USER`/`GRANT`. El README indica ejecutarlo con `docker exec -it`.
3. **`SET SERVEROUTPUT ON`, `SET DEFINE OFF` y `PROMPT` en scripts propios:** DBeaver los envía a Oracle y falla (`ORA-00922`). Se eliminaron de `ddl/` y `scripts/`.
4. **Línea `/` tras el bloque anónimo de pruebas:** produjo `ORA-00900` en DBeaver. Se quitó de los scripts de prueba (los `CREATE` de tipos, triggers y packages sí la llevan).
5. **Manejo de errores provisional de A.2:** `RAISE NO_DATA_FOUND` y errores de integridad crudos (`ORA-00001`). Se reemplazaron en A.3 por excepciones de negocio con código propio; la prueba P5 se actualizó.
6. **Prueba V13 mal planteada (A.3):** pasaba un valor de 250 caracteres a un atributo del Object Type de 200; el error saltaba al construir el objeto, no en el package. Se movió a `test_a3_error_tecnico.sql`, que fuerza una falla de entorno agotando `SEQ_TTEM_ITEM` y la restaura.
7. **Prueba J6 (A.4):** el parámetro `OUT` conservaba el JSON anterior porque Oracle no lo copia ante una excepción. La prueba ahora lo pone en nulo antes de llamar; el comportamiento queda documentado.
8. **`test_c_transferencias.sql` (Fase C) fallaba en DBeaver con `ORA-06550 / PLS-00103`:** la primera versión declaraba varias funciones y procedimientos locales (`foto`, `saldo`, `r`, `rechazo`); DBeaver cortó el bloque en la línea 39 (`END saldo;`) y envió un bloque incompleto, algo que SQL*Plus no hace y que la IA no había anticipado (solo se había probado en SQL*Plus). Se reescribió sin subprogramas locales: bucle sobre una tabla de casos y comprobaciones directas. Verificado de nuevo en SQL*Plus; pendiente de ejecutar en DBeaver. Lección: probar los scripts en el cliente real (DBeaver) antes de darlos por buenos.
9. **Prueba de concurrencia de A.5 mal armada (error de la IA):** la consulta de la sesión que debía retener los bloqueos usaba `FOR UPDATE` dentro de una subconsulta (`ORA-00907`), por lo que no bloqueó nada y la segunda sesión **cargó el lote de verdad**; SQL*Plus confirmó al salir. Los datos del candidato quedaron cargados (8 ítems, 7 errores). Se detectó de inmediato, se escribió `scripts/restablecer_a5.sql` (borra solo lo creado por el lote) y se dejó todo como al inicio (3 ítems, 0 errores, 12 pendientes); luego se repitió la prueba con la consulta correcta y `ROLLBACK` antes de salir: `ORA-20310` en la segunda sesión. Lección: en pruebas con SQL*Plus no automatizadas, terminar con `ROLLBACK` explícito, porque `EXIT` confirma.
10. **Patrones vigilados:** no se usa `WHEN OTHERS THEN NULL`; todos los `WHEN OTHERS` hacen rollback y relanzan; no hay SQL dinámico con datos del usuario (el único `EXECUTE IMMEDIATE`, en la prueba del error técnico, concatena un número leído del diccionario de datos y restaura la secuencia aunque falle).

## 6. Estimación de participación de la IA

Estimación aproximada, a confirmar por el candidato: **~95 % del código, las pruebas y la documentación fue generado por la IA**; **~5 % corresponde al candidato**, que dirigió el trabajo fase por fase, ejecutó y verificó las pruebas en DBeaver, detectó problemas de su entorno (salida del servidor, ORA-00922 / ORA-00900), decidió la regla de catálogo inactivo y pidió los commits. Cada bloque de código debe poder ser explicado por el candidato en la revisión técnica.

Registro de participación (se mantiene la estimación anterior, sin ajustarla): el candidato pidió conservar el registro real. Aportes del candidato verificables en esta bitácora: la regla de catálogo inactivo (`-20107`), las dos observaciones técnicas a la propuesta D (validación solo lectura y reversión compensatoria con auditoría de solo inserción), la revisión y aprobación de la propuesta D, la decisión de conservar `context.md` como contexto del agente, el diagnóstico de los problemas de DBeaver (salida del servidor, `SET`, `/`, bloques con funciones locales) y la ejecución y verificación de las pruebas de cada fase en su entorno. El código, las pruebas y los documentos los generó la IA.
