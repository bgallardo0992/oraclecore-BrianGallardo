# CoreCatalog & Settlement — Prueba técnica Oracle PL/SQL (Core Bancario)

Estado de avance: ver [STATUS.md](STATUS.md). Bitácora de uso de IA y decisiones: ver [AI-LOG.md](AI-LOG.md).

## Herramientas y versión

- **Base de datos:** Oracle Database 23ai Free `23.0.0.0.0` (versión `23.9.0.25.07`), en Docker con la imagen `gvenzl/oracle-free:23.9`. PDB: `FREEPDB1`.
- **Cliente SQL:** DBeaver (modo script, Alt+X) y SQL*Plus dentro del contenedor.
- No se usa ninguna característica exclusiva de 23ai (`JSON_OBJECT … RETURNING CLOB` y `LISTAGG … ON OVERFLOW` existen desde 12.2).

## Estructura del repositorio

```
setup/      scripts originales del Anexo B (sin modificar el contenido de las sentencias)
ddl/        tablas TTEM_*, triggers de auditoría, Object Types y datos iniciales
plsql/      PKG_TTEM_CATALOG (especificación .pks y cuerpo .pkb)
scripts/    consulta de la Sección B y pruebas de cada fase
STATUS.md  AI-LOG.md  README.md  connection.env.example
```

## Instalación (copiar y pegar)

Las contraseñas no se guardan en el repositorio: use `connection.env.example` como plantilla (`connection.env` está en `.gitignore`).

**1. Contenedor Oracle** (PowerShell; sustituya `<clave_admin>`):

```powershell
docker run -d --name oracle-core -p 1521:1521 -e ORACLE_PASSWORD=<clave_admin> gvenzl/oracle-free:23.9
docker logs -f oracle-core      # esperar "DATABASE IS READY TO USE!" y salir con Ctrl+C
```

**2. Usuario `CORE_DEV`** (como `SYSTEM`, con SQL*Plus en el contenedor; el script pide la contraseña con `ACCEPT … HIDE`, por lo que debe ejecutarse en una terminal interactiva):

```powershell
docker cp setup/00_setup_usuario.sql oracle-core:/tmp/
docker exec -it oracle-core sqlplus system@//localhost:1521/FREEPDB1
```
```
@/tmp/00_setup_usuario.sql
EXIT
```

**3. Modelo y datos del core** (como `CORE_DEV`, SQL*Plus en el contenedor; estos scripts usan `SET`/`PROMPT`, comandos de SQL*Plus):

```powershell
docker cp setup/01_core_ddl.sql oracle-core:/tmp/
docker cp setup/02_core_datos.sql oracle-core:/tmp/
docker exec -it oracle-core sqlplus core_dev@//localhost:1521/FREEPDB1
```
```
@/tmp/01_core_ddl.sql
@/tmp/02_core_datos.sql
EXIT
```
La consulta final de `02_core_datos.sql` debe mostrar: CORE_CUSTOMER 6, CORE_ACCOUNT 9, OLB_USER 4, CORE_TRX 11, TTEM_ITEM_STG 12.

**4. Catálogos y package** (como `CORE_DEV`; en DBeaver abrir cada archivo y ejecutar con **Alt+X**, conexión `localhost:1521`, *service name* `FREEPDB1`). Orden obligatorio:

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `ddl/01_ttem_tablas.sql` | Secuencias, `TTEM_CATALOG`, `TTEM_ITEM`, constraints |
| 2 | `ddl/02_ttem_triggers.sql` | Triggers de auditoría |
| 3 | `ddl/03_ttem_datos_iniciales.sql` | `MONEDA` (PEN, USD) y `TIPO_COMISION` (COM_MANT) |
| 4 | `ddl/04_ttem_tipos.sql` | `TYP_TTEM_ITEM`, `TYP_TTEM_ITEM_TAB` |
| 5 | `plsql/pkg_ttem_catalog.pks` | Especificación |
| 6 | `plsql/pkg_ttem_catalog.pkb` | Cuerpo |
| 7 | `plsql/pkg_core_settlement.pks` | Especificación de la liquidación (Sección C) |
| 8 | `plsql/pkg_core_settlement.pkb` | Cuerpo de la liquidación |
| 9 | `ddl/05_ttem_load_error.sql` | Tabla `TTEM_LOAD_ERROR` y su secuencia (opcional, solo A.5) |
| 10 | `plsql/pkg_ttem_load.pks` | Especificación de la carga masiva (A.5) |
| 11 | `plsql/pkg_ttem_load.pkb` | Cuerpo de la carga masiva |

Verificación de compilación: `SELECT * FROM user_errors;` debe devolver 0 filas.

**Nota sobre SQL*Plus:** los archivos de `ddl/`, `plsql/` y `scripts/` no usan comandos propios de SQL*Plus (DBeaver los rechaza). Para ejecutar los scripts de prueba en SQL*Plus escriba antes `SET SERVEROUTPUT ON` y una línea `/` tras el `END;` del bloque anónimo.

## Pruebas

Cada script termina con `ROLLBACK` y no deja datos (excepto donde se indique). En DBeaver, abrir el panel **Salida** para ver las líneas `OK`/`FALLA`.

| Script | Cubre | Resultado esperado |
|---|---|---|
| `scripts/test_a1_integridad.sql` | Constraints y auditoría | T1–T10 `OK`; 2 catálogos, 3 ítems |
| `scripts/test_a2_package.sql` | CRUD del package | P1–P5 `OK` |
| `scripts/test_a3_validaciones.sql` | Excepciones de negocio | V1–V12, V14–V17 `OK` |
| `scripts/test_a3_error_tecnico.sql` | Error técnico `-20900` | T-TEC `OK`. Hace `ALTER SEQUENCE` (commit implícito): ejecutar sin trabajo pendiente |
| `scripts/test_a4_json.sql` | JSON por `ItemId` | J1–J6 `OK` |
| `scripts/test_b_cuentas.sql` | Consulta de la Sección B | 5 filas con `RESULTADO = OK` (grilla, sin `DBMS_OUTPUT`) |
| `scripts/test_c_transferencias.sql` | Transferencias: 16 casos, atomicidad, savepoint | Todas las líneas `OK`; termina con `ROLLBACK` y restablece el estado inicial |
| `scripts/casos_c_manual.sql` | Los 6 casos del enunciado, con verificación de saldos y `CORE_TRX` | Ver tabla de la Sección C. **Modifica datos** (caso 1 con `COMMIT`) |
| `scripts/restablecer_casos_c.sql` | Deshace los datos del script manual | 11 movimientos; saldos 5250 y 350.50 |
| `scripts/test_a5_carga.sql` | Carga del lote con `LIMIT 4` y `LIMIT 200`, idempotencia, errores | Todas `OK`; 5 cargados y 7 rechazados; termina con `ROLLBACK`. Requiere el lote sin procesar |
| `scripts/cargar_lote_a5.sql` | Carga **real** del lote (con `COMMIT`) y consultas de verificación | `cargados=5 rechazados=7`. **Modifica datos** |
| `scripts/restablecer_a5.sql` | Deshace la carga real | 3 ítems, 0 errores, 12 pendientes |

## Ejemplo: consulta JSON por ItemId (A.4)

```sql
DECLARE
  l_json CLOB;
BEGIN
  pkg_ttem_catalog.obtener_item_json(2, l_json);   -- 2 = item_id de USD en esta instalación
  DBMS_OUTPUT.PUT_LINE(l_json);
END;
```

Salida real (el `itemId` depende de su carga; consulte `SELECT item_id FROM ttem_item WHERE item_code = 'USD'`):

```json
{"itemId":2,"catalogId":1,"catalogCode":"MONEDA","itemCode":"USD","name":"Dolar estadounidense","value":"USD","status":"A","validFrom":"2026-01-01","validTo":null}
```

Las fechas salen como `YYYY-MM-DD` y los valores nulos como `null` (la clave no se omite). Con un ítem inexistente el procedimiento lanza `ORA-20101`.

## Códigos de error propios (A.3)

Rango propio: **-20100 a -20199** errores de negocio del catálogo, **-20900** error técnico. La liquidación (Sección C) usa -20200 a -20299 y -20901 (ver más abajo).

| Código | Excepción | Significado | Lo generan |
|---|---|---|---|
| -20100 | `e_catalogo_no_existe` | El catálogo no existe | `insertar_item`, `listar_items` |
| -20101 | `e_item_no_existe` | El ítem no existe | `actualizar_item`, `eliminar_item`, `obtener_item_json` |
| -20102 | `e_item_duplicado` | El código ya existe dentro del catálogo | `insertar_item` |
| -20103 | `e_nombre_obligatorio` | Nombre nulo o solo espacios | `insertar_item`, `actualizar_item` |
| -20104 | `e_codigo_obligatorio` | Código nulo o solo espacios | `insertar_item` |
| -20105 | `e_vigencia_invalida` | Falta «desde» al insertar, o «hasta» es anterior a «desde» | `insertar_item`, `actualizar_item` |
| -20106 | `e_estado_invalido` | Estado distinto de `A` / `I` | `insertar_item`, `actualizar_item` |
| -20107 | `e_catalogo_inactivo` | El catálogo está inactivo: no admite ítems nuevos | `insertar_item` |
| -20900 | `e_error_tecnico` | Error inesperado, envuelto conservando el error Oracle original en el mensaje | `insertar_item`, `actualizar_item`, `eliminar_item` |

Control transaccional del package: **no hace `COMMIT`**. Cada operación de escritura abre su propio `SAVEPOINT`; ante un error hace `ROLLBACK` solo hasta ese savepoint (no revierte el trabajo previo del invocador) y relanza el error. El invocador decide `COMMIT` o `ROLLBACK`.

## A.5: carga masiva desde staging (opcional, P2)

`PKG_TTEM_LOAD.cargar_lote(p_load_batch, p_limit DEFAULT 200, p_cargados OUT, p_rechazados OUT)` procesa los registros con `processed_flag = 'N'` del lote (por ejemplo `LOTE-2026-10`) con `BULK COLLECT … LIMIT` y `FORALL … SAVE EXCEPTIONS`. Requiere `ddl/05_ttem_load_error.sql`. Necesita Oracle 12.2 o superior (`TO_DATE … DEFAULT NULL ON CONVERSION ERROR`); no usa nada exclusivo de 23ai.

- **Normalización:** `TRIM` en todos los campos y `UPPER` en los códigos de catálogo e ítem. Las fechas deben ser `YYYY-MM-DD` estrictas; una fecha imposible como `2026-13-01` se rechaza.
- **Duplicados:** dentro del lote gana la primera fila (menor `stg_id`) y las demás se rechazan (`DUPLICADO_LOTE`); contra los ítems existentes los detiene la clave única de `TTEM_ITEM` en el `FORALL` (`DUPLICADO_EXISTENTE`). Nunca se actualiza un ítem existente.
- **Errores por registro:** cada rechazo se guarda en `TTEM_LOAD_ERROR` (`stg_id`, `error_code`, `error_message`) y el registro de staging queda en `E`; los aceptados quedan en `S`. `processed_at` se informa en ambos. Un registro inválido no detiene a los demás.
- **Concurrencia:** el cursor es `FOR UPDATE NOWAIT`: una segunda sesión sobre el mismo lote recibe `ORA-20310` de inmediato; una vez confirmado el primero, no quedan pendientes y devuelve 0 / 0.
- **Transacción:** igual que el resto: no hace `COMMIT`; el invocador decide. `SAVEPOINT` propio (`sp_cargar_lote`).

Resultado de control verificado con el modelo mínimo (`LOTE-2026-10`): **5 cargados** (EUR, GBP, COM_ATM, COM_TRF_INT con valor 7.00, CHF normalizado) y **7 rechazados**:

| `stg_id` | Registro | Motivo (`error_code`) |
|---|---|---|
| 5 | `COM_TRF_INT` repetido (7.50) | `DUPLICADO_LOTE` |
| 6 | catálogo `TIPO_SEGURO` | `CATALOGO_INEXISTENTE` |
| 7 | código vacío | `CODIGO_VACIO` |
| 8 | nombre vacío (`COM_SOB`) | `NOMBRE_VACIO` |
| 9 | fecha `2026-13-01` (`JPY`) | `FECHA_DESDE_INVALIDA` |
| 10 | hasta `2026-06-30` anterior a desde `2026-12-01` (`COM_EXT`) | `VIGENCIA_INCOHERENTE` |
| 12 | `PEN` ya existe | `DUPLICADO_EXISTENTE` |

Otros motivos posibles: `CATALOGO_VACIO`, `CATALOGO_INACTIVO`, `FECHA_HASTA_INVALIDA`, `ERROR_INSERCION`.

| Código | Excepción | Significado |
|---|---|---|
| -20310 | `e_lote_en_proceso` | Otra sesión tiene bloqueadas las filas pendientes del lote |
| -20311 | `e_lote_no_existe` | No hay registros de staging con ese lote |
| -20312 | `e_limite_invalido` | `p_limit` nulo o menor que 1 |
| -20902 | `e_error_tecnico_carga` | Error inesperado envuelto, con el error Oracle original |

## Sección B: consulta de cliente por cuenta

Archivo: `scripts/consulta_cliente_por_cuenta.sql` (bind variable `:account_no`; DBeaver pide el valor al ejecutar con Ctrl+Enter). Devuelve una fila por cuenta.

**Cuenta inexistente (`9999999999999`): la consulta devuelve 0 filas, sin error.** Es el comportamiento natural de un `SELECT`; quien consume el resultado decide cómo tratar «sin resultados».

Resultados verificados para las cuentas de prueba:

| Cuenta | Nombre | Fecha referencia | Tipo | Usuarios OLB |
|---|---|---|---|---|
| `1910001000011` | Maria Fernanda Quispe Rojas | 1988-04-12 | Nacimiento | `mquispe (Activo)` |
| `1910002000017` | Jose Luis Ramirez Torres | (vacía) | No registrada | (vacío) |
| `1910003000013` | Inversiones Andinas S.A.C. | 2010-08-03 | Constitución | `invandinas.admin (Activo), invandinas.tesoreria (Bloqueado)` |
| `1910004000019` | Comercial Lima Norte E.I.R.L. | (vacía) | No registrada | (vacío); cuenta bloqueada |
| `9999999999999` | — | — | — | 0 filas |

## Sección C: transferencia bancaria

`PKG_CORE_SETTLEMENT.transferir(p_cuenta_origen, p_cuenta_destino, p_monto, p_moneda, p_referencia, p_descripcion, p_simular_falla, p_trx_id OUT)` (firma sugerida por el enunciado; está en un package propio porque la liquidación trabaja sobre las tablas del core y la Sección A sobre los catálogos `TTEM_*`).

**Quién controla la transacción: el invocador.** El procedimiento **no hace `COMMIT`**. Abre el `SAVEPOINT sp_transferir` y, ante cualquier error, hace `ROLLBACK TO sp_transferir`: deshace el débito, la acreditación y el insert de **esa** llamada (y libera sus bloqueos) sin tocar lo que el invocador hizo antes, y relanza el error. Si la operación termina bien, el cambio queda pendiente hasta que el invocador confirme. Los valores de `SEQ_CORE_TRX` no se revierten con el rollback (pueden quedar huecos de numeración).

**Bloqueo:** `SELECT … FOR UPDATE` de ambas cuentas en orden ascendente de número de cuenta, para que `A→B` y `B→A` simultáneas no provoquen un deadlock. **Idempotencia:** la referencia repetida se rechaza antes de tocar las cuentas; la restricción única `UK_CORE_TRX_REFERENCE` cubre la carrera entre sesiones.

| Código | Excepción | Significado |
|---|---|---|
| -20200 | `e_monto_invalido` | Monto nulo, ≤ 0 o con más de 2 decimales |
| -20201 | `e_cuenta_no_existe` | La cuenta de origen o de destino no existe |
| -20202 | `e_cuentas_iguales` | Origen y destino son la misma cuenta |
| -20203 | `e_cuenta_no_activa` | Origen o destino no está en estado `A` |
| -20204 | `e_moneda_distinta` | La moneda no coincide con la de ambas cuentas |
| -20205 | `e_saldo_insuficiente` | Saldo de origen menor que el monto |
| -20206 | `e_referencia_duplicada` | Ya existe un movimiento con esa referencia |
| -20207 | `e_referencia_obligatoria` | Referencia nula o vacía |
| -20208 | `e_falla_simulada` | Falla provocada con `p_simular_falla = 'S'` después del débito y antes de la acreditación |
| -20209 | `e_parametro_invalido` | Cuenta o moneda nula, o `p_simular_falla` distinto de `S`/`N` |
| -20901 | `e_error_tecnico_liq` | Error inesperado envuelto, con el error Oracle original en el mensaje |

### Casos de prueba del enunciado (`scripts/casos_c_manual.sql`)

Ejecutar en orden. Saldos iniciales: `1910001000011` = 5250,00 y `1910002000017` = 350,50.

| # | Operación | Resultado verificado | Saldos tras el caso | `CORE_TRX` |
|---|---|---|---|---|
| 1 | `1910001000011`→`1910002000017`, 100,00 PEN, `REF-T001` | Éxito (`trx_id` generado por `SEQ_CORE_TRX`) | 5150,00 / 450,50 | 1 fila nueva (TRF, Debe origen, Haber destino, flag `N`) |
| 2 | Repetir con `REF-T001` | `ORA-20206` | sin cambios | sigue 1 fila `REF-T001` |
| 3 | `1910002000017`→`1910001000011`, 5 000,00 PEN | `ORA-20205` (saldo 450,5) | sin cambios | sin fila |
| 4 | `1910001000011`→`1910001000029`, 10,00 PEN | `ORA-20204` (destino USD) | sin cambios | sin fila |
| 5 | `1910003000013`→`1910004000019`, 50,00 PEN | `ORA-20203` (destino bloqueada, estado `B`) | sin cambios | sin fila |
| 6 | `1910001000011`→`1910002000017`, 100,00 PEN, `REF-T002`, falla simulada | `ORA-20208` | sin cambios (5150,00 / 450,50) | ninguna fila `REF-T002` |

Después, `scripts/restablecer_casos_c.sql` devuelve los datos al estado original.

## Sección D: propuesta de mejora

**Escenario:** hoy las altas y modificaciones de ítems de catálogo se piden por correo y un desarrollador las ejecuta a mano en producción, con incidentes de vigencias mal configuradas y cambios sin trazabilidad de quién los aprobó.

1. **Qué automatizar primero:** el alta y la modificación de ítems `TTEM_*` mediante una **solicitud formal en la base de datos**, en lugar de correo más script manual. Ataca las dos causas de los incidentes: vigencias mal configuradas y falta de constancia de quién aprobó.
2. **Componentes:** una tabla nueva `TTEM_CHANGE_REQUEST` (ítem propuesto como `TYP_TTEM_ITEM`, motivo, ticket, solicitante, aprobador, estado PENDIENTE / APROBADA / RECHAZADA / APLICADA / REVERTIDA) y un package `PKG_TTEM_CHANGE` que **reutiliza** `PKG_TTEM_CATALOG`.
3. **Paso 1, solicitud y validación:** el solicitante la registra y se valida con **procedimientos de validación que solo leen** (los `validar_*` de `PKG_TTEM_CATALOG`, hoy privados, expuestos en su especificación: catálogo activo, código único, vigencia coherente, estado válido) y devuelven los errores sin tocar datos. No se simula con savepoint y rollback: las secuencias no se revierten y los triggers podrían tener efectos fuera de la transacción.
4. **Paso 2, aprobación:** un segundo responsable revisa el cambio (valores nuevos frente a los vigentes) **después** de pasar la validación; un `CHECK` impide que aprobador y solicitante sean la misma persona y solo el rol aprobador puede aprobar.
5. **Paso 3, aplicación:** el package **revalida** (entre la aprobación y la aplicación los datos pueden haber cambiado; las restricciones de la tabla siguen siendo la garantía final) y aplica llamando a `PKG_TTEM_CATALOG` en una sola transacción; en producción nadie tiene `INSERT`/`UPDATE` directo sobre `TTEM_*`, solo `EXECUTE` sobre el package.
6. **Auditoría:** `TTEM_AUDIT_LOG`, de **solo inserción**, guarda por cada cambio la solicitud que lo originó (`request_id`), los valores anteriores y nuevos, el usuario y la fecha; los triggers actuales siguen marcando usuario y fecha en la propia fila. Responde quién lo pidió, quién lo aprobó, cuándo y qué cambió.
7. **Reversión compensatoria:** una nueva solicitud de tipo REVERSA que referencia a la original, con su propia validación y aprobación, aplica el cambio inverso (restaurar los valores anteriores o inactivar el ítem creado, pues la eliminación ya es lógica) y genera sus propios registros de auditoría. La solicitud y la auditoría originales **no se modifican**: «revertida» se deduce de que exista la compensación. Antes de aplicar se comprueba que el valor actual sea el que dejó el cambio original; si hubo cambios posteriores, se rechaza o se envía a revisión.
8. **Riesgos:** aprobaciones de trámite sin revisar (mitigar mostrando la diferencia), cuentas compartidas que anulan la separación de funciones (exigir usuarios nominales) y cambios urgentes fuera del flujo (vía de emergencia con aprobación posterior y alerta).
9. **Dependencias y apoyo:** DBA (retirar el DML directo y otorgar solo `EXECUTE`), Seguridad (roles solicitante/aprobador y usuarios nominales), Negocio (quién aprueba cada catálogo) y Mesa de servicios (número de ticket).
10. **Esfuerzo aproximado:** unas 3 semanas con un desarrollador PL/SQL y apoyo parcial de QA (semana 1: tabla, package y pruebas; semana 2: auditoría y reversa; semana 3: piloto con `TIPO_COMISION`). La integración con la herramienta de tickets queda como fase aparte. Son estimaciones iniciales a confirmar con el equipo.
11. **Cómo medirlo:** incidentes por vigencia mal configurada (meta 0 por trimestre); cambios con solicitante, aprobador y valor anterior registrados (meta 100 %); cambios directos sobre `TTEM_*` fuera del flujo (meta 0); tiempo de solicitud a aplicación y tiempo de reversión (meta menos de 15 minutos); solicitudes rechazadas por validación antes de llegar a producción.
