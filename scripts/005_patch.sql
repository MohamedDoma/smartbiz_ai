-- ==========================================
-- SmartBiz AI — Migration 005 PATCH
-- Applies SECTIONS 2–14 of 005_inventory_logistics.sql
-- Reason: Original migration 005 failed at SECTION 2 (CREATE TABLE inventory_movements)
--         due to syntax error: extra closing paren at line 256.
--         SECTION 1 (ALTER inventory_levels) was applied successfully.
--         This patch applies everything from SECTION 2 onward with the fix.
-- Fix: Lines 255-256 changed from ")\n    )," to just "),"
-- ==========================================

-- ==========================================
-- SECTION 2: Inventory Movements (NEW)
-- ==========================================

CREATE TABLE inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES inventory_batches(id) ON DELETE SET NULL,

    movement_type VARCHAR(50) NOT NULL CHECK (movement_type IN (
        'purchase_receipt',
        'sale_shipment',
        'return_restock',
        'return_dispose',
        'supplier_return',
        'adjustment_increase',
        'adjustment_decrease',
        'transfer_out',
        'transfer_in',
        'production_consume',
        'production_output',
        'opening_balance',
        'damage',
        'shrinkage',
        'expired'
    )),

    quantity_change DECIMAL(12, 4) NOT NULL CHECK (quantity_change <> 0),
    quantity_before DECIMAL(12, 4) NOT NULL,
    quantity_after DECIMAL(12, 4) NOT NULL,

    unit_cost DECIMAL(12, 4),
    total_cost DECIMAL(15, 2),

    reference_type VARCHAR(50)
        CHECK (reference_type IS NULL OR reference_type IN (
            'order', 'shipment', 'grn', 'return', 'transfer',
            'production_order', 'adjustment', 'opening'
        )),
    reference_id UUID,

    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    reason_code VARCHAR(100),
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (quantity_after = quantity_before + quantity_change),
    -- FIX: Merged the two CHECK constraints and removed the extra closing paren
    CHECK (
        (movement_type IN ('purchase_receipt', 'return_restock', 'adjustment_increase',
                           'transfer_in', 'production_output', 'opening_balance')
            AND quantity_change > 0)
        OR
        (movement_type IN ('sale_shipment', 'return_dispose', 'supplier_return',
                           'adjustment_decrease', 'transfer_out', 'production_consume',
                           'damage', 'shrinkage', 'expired')
            AND quantity_change < 0)
    ),
    CHECK (
        reference_type IS NULL
        OR (movement_type IN ('sale_shipment') AND reference_type = 'shipment')
        OR (movement_type IN ('purchase_receipt') AND reference_type = 'grn')
        OR (movement_type IN ('return_restock', 'return_dispose') AND reference_type = 'return')
        OR (movement_type IN ('supplier_return') AND reference_type = 'return')
        OR (movement_type IN ('transfer_out', 'transfer_in') AND reference_type = 'transfer')
        OR (movement_type IN ('production_consume', 'production_output') AND reference_type = 'production_order')
        OR (movement_type IN ('adjustment_increase', 'adjustment_decrease', 'damage', 'shrinkage', 'expired')
            AND reference_type = 'adjustment')
        OR (movement_type IN ('opening_balance') AND reference_type = 'opening')
    )
);

COMMENT ON TABLE inventory_movements IS
    'Immutable audit log of all stock quantity changes (BR-STK-005).';
COMMENT ON COLUMN inventory_movements.movement_type IS
    'Classification per BR-STK-005.';
COMMENT ON COLUMN inventory_movements.reference_type IS
    'Must match movement_type per FIX #2 CHECK constraint.';
COMMENT ON COLUMN inventory_movements.unit_cost IS
    'Cost per unit at time of movement. Used for COGS and inventory valuation.';


-- ==========================================
-- SECTION 3: Stock Reservations (NEW)
-- ==========================================

CREATE TABLE stock_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    reserved_quantity DECIMAL(12, 4) NOT NULL CHECK (reserved_quantity > 0),
    fulfilled_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (fulfilled_quantity >= 0),
    released_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (released_quantity >= 0),

    status VARCHAR(50) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'fulfilled', 'partially_fulfilled', 'released', 'expired')),

    reserved_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fulfilled_at TIMESTAMPTZ,
    released_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CHECK (fulfilled_quantity + released_quantity <= reserved_quantity),
    CHECK (status <> 'fulfilled' OR fulfilled_at IS NOT NULL),
    CHECK (status <> 'released' OR released_at IS NOT NULL),
    CHECK (NOT (status = 'released' AND fulfilled_quantity > 0 AND fulfilled_at > released_at)),
    CHECK (NOT (status = 'fulfilled' AND released_quantity > 0))
);

CREATE OR REPLACE FUNCTION guard_reservation_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'released' AND NEW.fulfilled_quantity > OLD.fulfilled_quantity THEN
        RAISE EXCEPTION 'Cannot fulfill reservation % after it has been fully released.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.status = 'fulfilled' AND NEW.released_quantity > OLD.released_quantity THEN
        RAISE EXCEPTION 'Cannot release reservation % after it has been fully fulfilled.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.fulfilled_quantity + NEW.released_quantity > NEW.reserved_quantity THEN
        RAISE EXCEPTION 'fulfilled (%) + released (%) exceeds reserved (%) for reservation %.',
            NEW.fulfilled_quantity, NEW.released_quantity, NEW.reserved_quantity, OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reservation_lifecycle_guard
    BEFORE UPDATE ON stock_reservations
    FOR EACH ROW EXECUTE FUNCTION guard_reservation_lifecycle();


-- ==========================================
-- SECTION 4: Purchase Orders (NEW)
-- ==========================================

CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    supplier_contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    po_number VARCHAR(50),
    reference VARCHAR(100),

    currency VARCHAR(10) NOT NULL DEFAULT 'LYD',
    exchange_rate DECIMAL(10, 4) NOT NULL DEFAULT 1.0000 CHECK (exchange_rate > 0),

    subtotal DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (subtotal >= 0),
    tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0),
    total_amount DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),

    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'submitted', 'approved', 'partially_received',
                          'received', 'invoiced', 'closed', 'cancelled', 'rejected')),

    expected_delivery_date DATE,
    submitted_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(workspace_id, po_number),
    CHECK (status <> 'approved' OR approved_at IS NOT NULL),
    CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

CREATE TABLE purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    po_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    unit_id UUID REFERENCES units_of_measure(id) ON DELETE SET NULL,

    ordered_quantity DECIMAL(12, 4) NOT NULL CHECK (ordered_quantity > 0),
    received_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),

    unit_cost DECIMAL(12, 4) NOT NULL CHECK (unit_cost >= 0),
    tax_rate DECIMAL(5, 2) DEFAULT 0.00 CHECK (tax_rate >= 0),
    subtotal DECIMAL(15, 2) NOT NULL CHECK (subtotal >= 0),

    product_name_snapshot VARCHAR(255),
    sku_snapshot VARCHAR(100),

    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CHECK (received_quantity <= ordered_quantity * 1.10)
);


-- ==========================================
-- SECTION 5: Goods Received Notes (NEW)
-- ==========================================

CREATE TABLE goods_received_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    po_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    received_by UUID REFERENCES users(id) ON DELETE SET NULL,

    grn_number VARCHAR(50),

    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'confirmed', 'cancelled')),

    received_date DATE NOT NULL DEFAULT CURRENT_DATE,
    confirmed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(workspace_id, grn_number),
    CHECK (status <> 'confirmed' OR confirmed_at IS NOT NULL),
    CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

CREATE TABLE grn_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    grn_id UUID NOT NULL REFERENCES goods_received_notes(id) ON DELETE CASCADE,
    po_item_id UUID NOT NULL REFERENCES purchase_order_items(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    quantity_received DECIMAL(12, 4) NOT NULL CHECK (quantity_received > 0),
    condition VARCHAR(50) NOT NULL DEFAULT 'good'
        CHECK (condition IN ('good', 'damaged', 'partial')),

    batch_number VARCHAR(100),
    expiry_date DATE,

    unit_cost DECIMAL(12, 4),

    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ==========================================
-- SECTION 6: ALTER shipments — Fulfillment FSM
-- ==========================================

ALTER TABLE shipments
    ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS return_id UUID,
    ADD COLUMN IF NOT EXISTS picked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS packed_at TIMESTAMPTZ;

ALTER TABLE shipments DROP CONSTRAINT IF EXISTS shipments_status_check;
ALTER TABLE shipments
    ADD CONSTRAINT chk_shipments_status
    CHECK (status IN (
        'pending', 'picking', 'packed', 'shipped', 'delivered', 'cancelled',
        'processing', 'picked_up', 'in_transit', 'out_for_delivery', 'returned'
    ));


-- ==========================================
-- SECTION 7: Shipment Items (NEW)
-- ==========================================

CREATE TABLE shipment_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    shipment_id UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(id) ON DELETE SET NULL,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,

    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),

    batch_id UUID REFERENCES inventory_batches(id) ON DELETE SET NULL,
    reservation_id UUID REFERENCES stock_reservations(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- ==========================================
-- SECTION 8: Returns & Return Items (NEW)
-- ==========================================

CREATE TABLE returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    return_type VARCHAR(50) NOT NULL DEFAULT 'customer'
        CHECK (return_type IN ('customer', 'supplier')),

    status VARCHAR(50) NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'approved', 'received', 'inspected',
                          'restocked', 'disposed', 'rejected', 'cancelled')),

    return_number VARCHAR(50),

    refund_amount DECIMAL(12, 2) CHECK (refund_amount IS NULL OR refund_amount >= 0),
    credit_note_id UUID,

    reason TEXT NOT NULL,

    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    inspected_at TIMESTAMPTZ,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(workspace_id, return_number),
    CHECK (status <> 'approved' OR approved_at IS NOT NULL)
);

CREATE TABLE return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    return_id UUID NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),

    reason_code VARCHAR(100) NOT NULL,
    reason_detail TEXT,

    condition VARCHAR(50)
        CHECK (condition IS NULL OR condition IN ('good', 'damaged', 'defective')),
    disposition VARCHAR(50)
        CHECK (disposition IS NULL OR disposition IN ('restock', 'dispose')),

    restocked_warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
    restocked_quantity DECIMAL(12, 4) DEFAULT 0 CHECK (restocked_quantity >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CHECK (restocked_quantity <= quantity),
    CHECK (disposition <> 'restock' OR restocked_warehouse_id IS NOT NULL),
    CHECK (disposition <> 'restock' OR restocked_quantity > 0)
);

ALTER TABLE shipments
    ADD CONSTRAINT fk_shipments_return FOREIGN KEY (return_id) REFERENCES returns(id) ON DELETE SET NULL;


-- ==========================================
-- SECTION 9: Triggers
-- ==========================================

CREATE OR REPLACE FUNCTION prevent_immutable_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'This table is immutable. Rows cannot be updated after insertion.'
        USING ERRCODE = 'check_violation';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_movements_no_update
    BEFORE UPDATE ON inventory_movements
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_update();

CREATE TRIGGER trg_stock_reservations_updated
    BEFORE UPDATE ON stock_reservations
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_purchase_orders_updated
    BEFORE UPDATE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_grn_updated
    BEFORE UPDATE ON goods_received_notes
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_shipments_updated
    BEFORE UPDATE ON shipments
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_returns_updated
    BEFORE UPDATE ON returns
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 10: Indexes
-- ==========================================

CREATE INDEX idx_inventory_levels_workspace ON inventory_levels(workspace_id)
    WHERE workspace_id IS NOT NULL;
CREATE INDEX idx_inventory_levels_low_stock ON inventory_levels(workspace_id, product_id)
    WHERE reorder_point IS NOT NULL AND available <= reorder_point;

CREATE INDEX idx_inventory_movements_workspace ON inventory_movements(workspace_id);
CREATE INDEX idx_inventory_movements_warehouse ON inventory_movements(warehouse_id);
CREATE INDEX idx_inventory_movements_product ON inventory_movements(product_id);
CREATE INDEX idx_inventory_movements_type ON inventory_movements(movement_type);
CREATE INDEX idx_inventory_movements_ref ON inventory_movements(reference_type, reference_id)
    WHERE reference_id IS NOT NULL;
CREATE INDEX idx_inventory_movements_created ON inventory_movements(workspace_id, created_at DESC);
CREATE INDEX idx_inventory_movements_batch ON inventory_movements(batch_id)
    WHERE batch_id IS NOT NULL;

CREATE INDEX idx_stock_reservations_workspace ON stock_reservations(workspace_id);
CREATE INDEX idx_stock_reservations_order ON stock_reservations(order_id);
CREATE INDEX idx_stock_reservations_order_item ON stock_reservations(order_item_id);
CREATE INDEX idx_stock_reservations_warehouse ON stock_reservations(warehouse_id);
CREATE INDEX idx_stock_reservations_product ON stock_reservations(product_id);
CREATE INDEX idx_stock_reservations_active ON stock_reservations(workspace_id, status)
    WHERE status = 'active';

CREATE INDEX idx_purchase_orders_workspace ON purchase_orders(workspace_id);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders(supplier_contact_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders(status);
CREATE INDEX idx_purchase_orders_created ON purchase_orders(workspace_id, created_at DESC);

CREATE INDEX idx_po_items_po ON purchase_order_items(po_id);
CREATE INDEX idx_po_items_product ON purchase_order_items(product_id);

CREATE INDEX idx_grn_workspace ON goods_received_notes(workspace_id);
CREATE INDEX idx_grn_po ON goods_received_notes(po_id);
CREATE INDEX idx_grn_warehouse ON goods_received_notes(warehouse_id);
CREATE INDEX idx_grn_status ON goods_received_notes(status);

CREATE INDEX idx_grn_items_grn ON grn_items(grn_id);
CREATE INDEX idx_grn_items_po_item ON grn_items(po_item_id);
CREATE INDEX idx_grn_items_product ON grn_items(product_id);

CREATE INDEX idx_shipments_order ON shipments(order_id)
    WHERE order_id IS NOT NULL;
CREATE INDEX idx_shipments_warehouse ON shipments(warehouse_id)
    WHERE warehouse_id IS NOT NULL;
CREATE INDEX idx_shipments_return ON shipments(return_id)
    WHERE return_id IS NOT NULL;

CREATE INDEX idx_shipment_items_workspace ON shipment_items(workspace_id);
CREATE INDEX idx_shipment_items_shipment ON shipment_items(shipment_id);
CREATE INDEX idx_shipment_items_order_item ON shipment_items(order_item_id)
    WHERE order_item_id IS NOT NULL;
CREATE INDEX idx_shipment_items_product ON shipment_items(product_id);
CREATE INDEX idx_shipment_items_reservation ON shipment_items(reservation_id)
    WHERE reservation_id IS NOT NULL;

CREATE INDEX idx_returns_workspace ON returns(workspace_id);
CREATE INDEX idx_returns_order ON returns(order_id)
    WHERE order_id IS NOT NULL;
CREATE INDEX idx_returns_contact ON returns(contact_id);
CREATE INDEX idx_returns_status ON returns(status);
CREATE INDEX idx_returns_type ON returns(return_type);

CREATE INDEX idx_return_items_return ON return_items(return_id);
CREATE INDEX idx_return_items_product ON return_items(product_id);


-- ==========================================
-- SECTION 11: Composite Unique Constraints
-- ==========================================

ALTER TABLE inventory_movements ADD CONSTRAINT uq_inventory_movements_ws_id UNIQUE (workspace_id, id);
ALTER TABLE stock_reservations ADD CONSTRAINT uq_stock_reservations_ws_id UNIQUE (workspace_id, id);
ALTER TABLE purchase_orders ADD CONSTRAINT uq_purchase_orders_ws_id UNIQUE (workspace_id, id);
ALTER TABLE purchase_order_items ADD CONSTRAINT uq_po_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE goods_received_notes ADD CONSTRAINT uq_grn_ws_id UNIQUE (workspace_id, id);
ALTER TABLE grn_items ADD CONSTRAINT uq_grn_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE shipment_items ADD CONSTRAINT uq_shipment_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE returns ADD CONSTRAINT uq_returns_ws_id UNIQUE (workspace_id, id);
ALTER TABLE return_items ADD CONSTRAINT uq_return_items_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 12: Workspace FK Isolation Triggers
-- ==========================================

CREATE TRIGGER trg_inventory_movements_ws_check
    BEFORE INSERT OR UPDATE ON inventory_movements
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'warehouse_id:warehouses,product_id:products,created_by:users'
    );

CREATE TRIGGER trg_stock_reservations_ws_check
    BEFORE INSERT OR UPDATE ON stock_reservations
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'order_id:orders,warehouse_id:warehouses,product_id:products'
    );

CREATE TRIGGER trg_purchase_orders_ws_check
    BEFORE INSERT OR UPDATE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'supplier_contact_id:contacts,branch_id:branches,created_by:users,approved_by:users'
    );

CREATE TRIGGER trg_po_items_ws_check
    BEFORE INSERT OR UPDATE ON purchase_order_items
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'po_id:purchase_orders,product_id:products'
    );

CREATE TRIGGER trg_grn_ws_check
    BEFORE INSERT OR UPDATE ON goods_received_notes
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'po_id:purchase_orders,warehouse_id:warehouses,received_by:users'
    );

CREATE TRIGGER trg_grn_items_ws_check
    BEFORE INSERT OR UPDATE ON grn_items
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'grn_id:goods_received_notes,po_item_id:purchase_order_items,product_id:products'
    );

CREATE TRIGGER trg_shipment_items_ws_check
    BEFORE INSERT OR UPDATE ON shipment_items
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'shipment_id:shipments,product_id:products,warehouse_id:warehouses'
    );

CREATE TRIGGER trg_returns_ws_check
    BEFORE INSERT OR UPDATE ON returns
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'contact_id:contacts,created_by:users,approved_by:users'
    );

CREATE TRIGGER trg_return_items_ws_check
    BEFORE INSERT OR UPDATE ON return_items
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'return_id:returns,product_id:products'
    );


-- ==========================================
-- SECTION 13: Row Level Security (RLS)
-- ==========================================

ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inventory_movements ON inventory_movements
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE stock_reservations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_stock_reservations ON stock_reservations
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_purchase_orders ON purchase_orders
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_po_items ON purchase_order_items
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE goods_received_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_grn ON goods_received_notes
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE grn_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_grn_items ON grn_items
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE shipment_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_shipment_items ON shipment_items
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_returns ON returns
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE return_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_return_items ON return_items
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE inventory_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inventory_levels ON inventory_levels
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- ==========================================
-- END OF 005 PATCH
-- ==========================================
