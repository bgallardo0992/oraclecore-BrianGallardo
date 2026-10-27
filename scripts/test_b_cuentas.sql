-- =====================================================================
-- Seccion B - Prueba de las 5 cuentas (una sola consulta, resultado OK/FALLA en la grilla)
-- Ejecutar como CORE_DEV. Es la misma consulta de consulta_cliente_por_cuenta.sql con el
-- filtro cambiado a IN (...) para probar las 5 cuentas a la vez. No usa DBMS_OUTPUT.
-- Esperado: 5 filas, todas con resultado OK.
-- =====================================================================
WITH q AS (
  SELECT a.account_no, a.status AS account_status, c.customer_id,
         CASE c.person_type WHEN 'N' THEN 'Natural' WHEN 'J' THEN 'Jurídica' END AS person_type_desc,
         CASE c.person_type
           WHEN 'N' THEN INITCAP(TRIM(REGEXP_REPLACE(TRIM(c.first_name) || ' ' || TRIM(c.last_name), '\s+', ' ')))
           ELSE TRIM(REGEXP_REPLACE(c.business_name, '\s+', ' '))
         END AS customer_name,
         CASE c.person_type WHEN 'N' THEN c.birth_date ELSE c.incorporation_date END AS reference_date,
         CASE WHEN c.person_type = 'N' AND c.birth_date IS NOT NULL THEN 'Nacimiento'
              WHEN c.person_type = 'J' AND c.incorporation_date IS NOT NULL THEN 'Constitución'
              ELSE 'No registrada'
         END AS reference_date_type,
         o.olb_users
    FROM core_account a
    JOIN core_customer c ON c.customer_id = a.customer_id
    LEFT JOIN (SELECT u.customer_id,
                      LISTAGG(u.username || ' (' ||
                              CASE u.status WHEN 'A' THEN 'Activo' WHEN 'B' THEN 'Bloqueado' WHEN 'I' THEN 'Inactivo' END || ')',
                              ', ' ON OVERFLOW TRUNCATE '...' WITHOUT COUNT)
                        WITHIN GROUP (ORDER BY u.username) AS olb_users
                 FROM olb_user u
                GROUP BY u.customer_id) o ON o.customer_id = a.customer_id
   WHERE a.account_no IN ('1910001000011', '1910002000017', '1910003000013', '1910004000019', '9999999999999')
),
esperado AS (
  SELECT '1910001000011' AS account_no, 1 AS existe, 'Natural' AS tipo, 'Maria Fernanda Quispe Rojas' AS nombre,
         DATE '1988-04-12' AS fecha_ref, 'Nacimiento' AS tipo_fecha, 'mquispe (Activo)' AS usuarios, 'A' AS estado FROM dual
  UNION ALL
  SELECT '1910002000017', 1, 'Natural', 'Jose Luis Ramirez Torres', NULL, 'No registrada', NULL, 'A' FROM dual
  UNION ALL
  SELECT '1910003000013', 1, 'Jurídica', 'Inversiones Andinas S.A.C.', DATE '2010-08-03', 'Constitución',
         'invandinas.admin (Activo), invandinas.tesoreria (Bloqueado)', 'A' FROM dual
  UNION ALL
  SELECT '1910004000019', 1, 'Jurídica', 'Comercial Lima Norte E.I.R.L.', NULL, 'No registrada', NULL, 'B' FROM dual
  UNION ALL
  SELECT '9999999999999', 0, NULL, NULL, NULL, NULL, NULL, NULL FROM dual
),
conteo AS (
  SELECT account_no, COUNT(*) AS filas FROM q GROUP BY account_no
)
SELECT e.account_no,
       NVL(k.filas, 0) AS filas,
       q.customer_name,
       q.reference_date,
       q.reference_date_type,
       q.olb_users,
       CASE
         WHEN e.existe = 0 THEN CASE WHEN k.filas IS NULL THEN 'OK' ELSE 'FALLA' END
         WHEN k.filas = 1
              AND q.person_type_desc = e.tipo
              AND q.customer_name = e.nombre
              AND DECODE(q.reference_date, e.fecha_ref, 1, 0) = 1
              AND q.reference_date_type = e.tipo_fecha
              AND DECODE(q.olb_users, e.usuarios, 1, 0) = 1
              AND q.account_status = e.estado THEN 'OK'
         ELSE 'FALLA'
       END AS resultado
  FROM esperado e
  LEFT JOIN q ON q.account_no = e.account_no
  LEFT JOIN conteo k ON k.account_no = e.account_no
 ORDER BY e.account_no;
