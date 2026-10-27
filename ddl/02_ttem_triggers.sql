-- =====================================================================
-- A.1 - Auditoria automatica mediante triggers BEFORE INSERT OR UPDATE
-- Ejecutar como CORE_DEV, despues de 01_ttem_tablas.sql.
-- Cada bloque termina con "/" en linea aparte (sin lineas en blanco dentro).
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_ttem_catalog_aud
BEFORE INSERT OR UPDATE ON ttem_catalog
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    :NEW.created_by := SYS_CONTEXT('USERENV', 'SESSION_USER');
    :NEW.created_at := SYSDATE;
    :NEW.updated_by := :NEW.created_by;
    :NEW.updated_at := :NEW.created_at;
  ELSE
    :NEW.created_by := :OLD.created_by;
    :NEW.created_at := :OLD.created_at;
    :NEW.updated_by := SYS_CONTEXT('USERENV', 'SESSION_USER');
    :NEW.updated_at := SYSDATE;
  END IF;
END trg_ttem_catalog_aud;
/
CREATE OR REPLACE TRIGGER trg_ttem_item_aud
BEFORE INSERT OR UPDATE ON ttem_item
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    :NEW.created_by := SYS_CONTEXT('USERENV', 'SESSION_USER');
    :NEW.created_at := SYSDATE;
    :NEW.updated_by := :NEW.created_by;
    :NEW.updated_at := :NEW.created_at;
  ELSE
    :NEW.created_by := :OLD.created_by;
    :NEW.created_at := :OLD.created_at;
    :NEW.updated_by := SYS_CONTEXT('USERENV', 'SESSION_USER');
    :NEW.updated_at := SYSDATE;
  END IF;
END trg_ttem_item_aud;
/
SELECT object_name, status FROM user_objects WHERE object_type = 'TRIGGER' ORDER BY object_name;
