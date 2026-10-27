-- =====================================================================
-- Seccion B - Consulta de cliente por numero de cuenta
-- Ejecutar como CORE_DEV. Recibe la cuenta en la bind variable :account_no
-- (DBeaver pide el valor al ejecutar con Ctrl+Enter; en SQL*Plus: VARIABLE account_no VARCHAR2(20)
--  y EXEC :account_no := '1910001000011').
-- Devuelve UNA fila por cuenta. Cuenta inexistente: CERO filas (no lanza error).
-- Archivo en UTF-8 (contiene tildes en las etiquetas).
-- =====================================================================
SELECT a.account_no,
       a.product_type,
       a.currency,
       a.balance,
       a.status AS account_status,
       CASE a.status WHEN 'A' THEN 'Activa' WHEN 'B' THEN 'Bloqueada' WHEN 'C' THEN 'Cancelada' END AS account_status_desc,
       c.customer_id,
       CASE c.person_type WHEN 'N' THEN 'Natural' WHEN 'J' THEN 'Jurídica' END AS person_type_desc,
       c.doc_type,
       c.doc_number,
       -- Natural: nombres + apellidos; Juridica: razon social. Sin espacios sobrantes ni dobles.
       CASE c.person_type
         WHEN 'N' THEN INITCAP(TRIM(REGEXP_REPLACE(TRIM(c.first_name) || ' ' || TRIM(c.last_name), '\s+', ' ')))
         ELSE TRIM(REGEXP_REPLACE(c.business_name, '\s+', ' '))
       END AS customer_name,
       -- Fecha de referencia segun el tipo de persona (puede ser NULL)
       CASE c.person_type WHEN 'N' THEN c.birth_date ELSE c.incorporation_date END AS reference_date,
       CASE WHEN c.person_type = 'N' AND c.birth_date IS NOT NULL THEN 'Nacimiento'
            WHEN c.person_type = 'J' AND c.incorporation_date IS NOT NULL THEN 'Constitución'
            ELSE 'No registrada'
       END AS reference_date_type,
       -- Usuarios de Banca en Linea consolidados; NULL si el cliente no tiene
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
 WHERE a.account_no = :account_no;
