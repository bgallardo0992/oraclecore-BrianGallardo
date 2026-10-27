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

Rango propio: **-20100 a -20199** errores de negocio del catálogo, **-20900** error técnico. Se reserva -20200 a -20299 para la liquidación (Sección C, aún no implementada).

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

Pendiente. Ver [STATUS.md](STATUS.md).

## Sección D: propuesta de mejora

Pendiente. Ver [STATUS.md](STATUS.md).
