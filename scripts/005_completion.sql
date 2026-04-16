-- ==========================================
-- 005 completion patch: Sections 9b through 13
-- Picks up from where the first patch stopped (trg_shipments_updated conflict)
-- ==========================================

-- Section 9b: Fix the duplicate trigger (DROP IF EXISTS then CREATE)
DROP TRIGGER IF EXISTS trg_shipments_updated ON shipments;
CREATE TRIGGER trg_shipments_updated
    BEFORE UPDATE ON shipments
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_returns_updated
    BEFORE UPDATE ON returns
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Section 10: Indexes
CREATE INDEX IF NOT EXISTS idx_inventory_levels_workspace ON inventory_levels(workspace_id)
    WHERE workspace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_levels_low_stock ON inventory_levels(workspace_id, product_id)
    WHERE reorder_point IS NOT NULL AND available <= reorder_point;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_workspace ON inventory_movements(workspace_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_warehouse ON inventory_movements(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_product ON inventory_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_type ON inventory_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_ref ON inventory_movements(reference_type, reference_id)
    WHERE reference_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_movements_created ON inventory_movements(workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_batch ON inventory_movements(batch_id)
    WHERE batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stock_reservations_workspace ON stock_reservations(workspace_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_order ON stock_reservations(order_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_order_item ON stock_reservations(order_item_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_warehouse ON stock_reservations(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_product ON stock_reservations(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_reservations_active ON stock_reservations(workspace_id, status)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_purchase_orders_workspace ON purchase_orders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders(supplier_contact_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_created ON purchase_orders(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_po_items_po ON purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS idx_po_items_product ON purchase_order_items(product_id);

CREATE INDEX IF NOT EXISTS idx_grn_workspace ON goods_received_notes(workspace_id);
CREATE INDEX IF NOT EXISTS idx_grn_po ON goods_received_notes(po_id);
CREATE INDEX IF NOT EXISTS idx_grn_warehouse ON goods_received_notes(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_grn_status ON goods_received_notes(status);

CREATE INDEX IF NOT EXISTS idx_grn_items_grn ON grn_items(grn_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_po_item ON grn_items(po_item_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_product ON grn_items(product_id);

CREATE INDEX IF NOT EXISTS idx_shipments_order ON shipments(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shipments_warehouse ON shipments(warehouse_id) WHERE warehouse_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shipments_return ON shipments(return_id) WHERE return_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_shipment_items_workspace ON shipment_items(workspace_id);
CREATE INDEX IF NOT EXISTS idx_shipment_items_shipment ON shipment_items(shipment_id);
CREATE INDEX IF NOT EXISTS idx_shipment_items_order_item ON shipment_items(order_item_id) WHERE order_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shipment_items_product ON shipment_items(product_id);
CREATE INDEX IF NOT EXISTS idx_shipment_items_reservation ON shipment_items(reservation_id) WHERE reservation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_returns_workspace ON returns(workspace_id);
CREATE INDEX IF NOT EXISTS idx_returns_order ON returns(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_returns_contact ON returns(contact_id);
CREATE INDEX IF NOT EXISTS idx_returns_status ON returns(status);
CREATE INDEX IF NOT EXISTS idx_returns_type ON returns(return_type);

CREATE INDEX IF NOT EXISTS idx_return_items_return ON return_items(return_id);
CREATE INDEX IF NOT EXISTS idx_return_items_product ON return_items(product_id);

-- Section 11: Composite Unique Constraints
ALTER TABLE inventory_movements ADD CONSTRAINT uq_inventory_movements_ws_id UNIQUE (workspace_id, id);
ALTER TABLE stock_reservations ADD CONSTRAINT uq_stock_reservations_ws_id UNIQUE (workspace_id, id);
ALTER TABLE purchase_orders ADD CONSTRAINT uq_purchase_orders_ws_id UNIQUE (workspace_id, id);
ALTER TABLE purchase_order_items ADD CONSTRAINT uq_po_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE goods_received_notes ADD CONSTRAINT uq_grn_ws_id UNIQUE (workspace_id, id);
ALTER TABLE grn_items ADD CONSTRAINT uq_grn_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE shipment_items ADD CONSTRAINT uq_shipment_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE returns ADD CONSTRAINT uq_returns_ws_id UNIQUE (workspace_id, id);
ALTER TABLE return_items ADD CONSTRAINT uq_return_items_ws_id UNIQUE (workspace_id, id);

-- Section 12: Workspace FK Isolation Triggers
CREATE TRIGGER trg_inventory_movements_ws_check BEFORE INSERT OR UPDATE ON inventory_movements FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('warehouse_id:warehouses,product_id:products,created_by:users');
CREATE TRIGGER trg_stock_reservations_ws_check BEFORE INSERT OR UPDATE ON stock_reservations FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('order_id:orders,warehouse_id:warehouses,product_id:products');
CREATE TRIGGER trg_purchase_orders_ws_check BEFORE INSERT OR UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('supplier_contact_id:contacts,branch_id:branches,created_by:users,approved_by:users');
CREATE TRIGGER trg_po_items_ws_check BEFORE INSERT OR UPDATE ON purchase_order_items FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('po_id:purchase_orders,product_id:products');
CREATE TRIGGER trg_grn_ws_check BEFORE INSERT OR UPDATE ON goods_received_notes FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('po_id:purchase_orders,warehouse_id:warehouses,received_by:users');
CREATE TRIGGER trg_grn_items_ws_check BEFORE INSERT OR UPDATE ON grn_items FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('grn_id:goods_received_notes,po_item_id:purchase_order_items,product_id:products');
CREATE TRIGGER trg_shipment_items_ws_check BEFORE INSERT OR UPDATE ON shipment_items FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('shipment_id:shipments,product_id:products,warehouse_id:warehouses');
CREATE TRIGGER trg_returns_ws_check BEFORE INSERT OR UPDATE ON returns FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('contact_id:contacts,created_by:users,approved_by:users');
CREATE TRIGGER trg_return_items_ws_check BEFORE INSERT OR UPDATE ON return_items FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('return_id:returns,product_id:products');

-- Section 13: RLS
ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inventory_movements ON inventory_movements USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE stock_reservations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_stock_reservations ON stock_reservations USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_purchase_orders ON purchase_orders USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_po_items ON purchase_order_items USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE goods_received_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_grn ON goods_received_notes USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE grn_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_grn_items ON grn_items USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE shipment_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_shipment_items ON shipment_items USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_returns ON returns USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE return_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_return_items ON return_items USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE inventory_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inventory_levels ON inventory_levels USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- ==========================================
-- END
-- ==========================================
