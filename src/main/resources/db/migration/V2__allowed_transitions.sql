-- Máquina de estados (docs/diseno.md, sección 4)
INSERT INTO allowed_transitions (from_status, to_status) VALUES
  ('CREATED',          'PICKED_UP'),
  ('CREATED',          'CANCELLED'),
  ('PICKED_UP',        'IN_TRANSIT'),
  ('PICKED_UP',        'INCIDENT'),
  ('IN_TRANSIT',       'OUT_FOR_DELIVERY'),
  ('IN_TRANSIT',       'INCIDENT'),
  ('OUT_FOR_DELIVERY', 'DELIVERED'),
  ('OUT_FOR_DELIVERY', 'INCIDENT'),
  ('INCIDENT',         'IN_TRANSIT'),
  ('INCIDENT',         'OUT_FOR_DELIVERY'),
  ('INCIDENT',         'RETURNED');
