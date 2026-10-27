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

Pendiente. Ver [STATUS.md](STATUS.md).
