-- Un envío solo puede tener un evento inicial (from_status NULL).
-- Como D2: la BD lo impide aunque el código tenga un bug o se reintente una petición.
CREATE UNIQUE INDEX uq_events_initial ON shipment_events (shipment_id) WHERE from_status IS NULL;
