-- ==========================================
-- SmartBiz AI — Migration 005: Inventory / Logistics
-- Batch E from SQL Patch Execution Pack
-- ==========================================
--
-- Purpose:
--   Close all inventory/logistics schema gaps flagged in API contracts and
--   business rules. Creates: purchase_orders, purchase_order_items,
--   goods_received_notes, grn_items, shipment_items, stock_reservations,
--   returns, return_items. Alters: inventory_levels (reservation support,
--   reorder_point), shipments (order linkage, fulfillment FSM), inventory_logs
--   (movement_type enrichment).
--
-- Prerequisites:
--   Base schema + 001 through 004
--
-- Risk: MEDIUM — ALTERs inventory_levels (adds columns, no data loss).
--        ALTERs shipments (adds columns for fulfillment FSM).
--        Creates new tables; non-destructive.
--
-- ==========================================
-- INVENTORY CONSISTENCY MODEL
-- ==========================================
--
-- SmartBiz uses a RESERVATION-BASED inventory consistency model:
--
--   inventory_levels.quantity     = physical stock on hand
--   inventory_levels.reserved    = quantity reserved by confirmed orders
--   inventory_levels.available   = quantity - reserved (APPLICATION-MAINTAINED)
--
-- The lifecycle is:
--   1. ORDER CONFIRMED   → reservation created (reserved↑, available↓)    [BR-STK-001]
--   2. SHIPMENT SHIPPED  → physical deduction (quantity↓, reserved↓)      [BR-STK-003]
--   3. ORDER CANCELLED   → reservation released (reserved↓, available↑)   [BR-STK-002]
--   4. GRN RECEIVED      → physical increase (quantity↑, available↑)      [BR-PUR-003]
--   5. RETURN RESTOCKED  → physical increase (quantity↑, available↑)      [BR-RFD-004]
--
-- ==========================================
-- CONCURRENCY SAFETY MODEL (FIX #1)
-- ==========================================
--
-- All inventory_levels mutations MUST follow this strict locking protocol:
--
--   Step 1: BEGIN TRANSACTION with SERIALIZABLE or READ COMMITTED
--   Step 2: SELECT ... FROM inventory_levels
--           WHERE product_id = ? AND warehouse_id = ?
--           FOR UPDATE
--           (This acquires a row-level exclusive lock, blocking other writers)
--   Step 3: Read current quantity, reserved, available from the locked row
--   Step 4: Compute new values
--   Step 5: Validate: new quantity >= 0 (unless negative stock override)
--   Step 6: UPDATE inventory_levels SET quantity = ?, reserved = ?,
--           available = quantity - reserved WHERE id = ?
--   Step 7: INSERT INTO inventory_movements (...) (mandatory per BR-STK-005)
--   Step 8: COMMIT (or ROLLBACK on validation failure)
--
-- The FOR UPDATE lock is MANDATORY for ALL of:
--   - stock reservation (order confirmed)      [BR-STK-001]
--   - stock deduction (shipment shipped)        [BR-STK-003]
--   - reservation release (order cancelled)     [BR-STK-002]
--   - GRN receipt (goods received)              [BR-PUR-003]
--   - return restock                            [BR-RFD-004]
--   - stock adjustment                          [BR-STK-006]
--   - transfer out/in                           [BR-STK-008]
--   - production consume/output                 [BR-STK-005]
--
-- Without FOR UPDATE, concurrent operations WILL cause lost updates:
--   Thread A reads quantity=10, Thread B reads quantity=10,
--   both write quantity=5 → lost deduction.
--
-- For high-contention scenarios (flash sales, bulk GRN), consider:
--   - SELECT FOR UPDATE SKIP LOCKED for reservation fallback to other warehouses
--   - pg_advisory_xact_lock(product_id::bigint) for cross-warehouse product locks
--
-- This pattern is APP-ENFORCED. The DB provides CHECK constraints as safety nets
-- (chk_inventory_no_negative_stock, chk_inventory_reserved_consistency,
-- chk_inventory_available_consistency) but cannot enforce the transactional
-- ordering itself.
--
-- Negative stock:
--   Default: REJECTED. inventory_levels.quantity >= 0 is enforced by CHECK.
--   Workspace override: when allow_negative_stock = TRUE in workspace settings,
--   the application bypasses the CHECK by using a SET LOCAL role or deferred
--   constraint approach. This is APP-ENFORCED; the CHECK is the safety net.
--
-- Movement audit:
--   ALL quantity changes MUST create an inventory_movements record per BR-STK-005.
--   The inventory_movements table replaces/extends the existing inventory_logs.
--   inventory_movements is IMMUTABLE (enforced by trg_inventory_movements_no_update).
--
-- ==========================================


-- ==========================================
-- SECTION 1: ALTER inventory_levels — Reservation & Reorder Support
-- ==========================================
-- Adds reserved, available, and reorder_point columns per BR-STK-001/002/012.

ALTER TABLE inventory_levels
    ADD COLUMN IF NOT EXISTS reserved DECIMAL(12, 4) NOT NULL DEFAULT 0
        CHECK (reserved >= 0),
    ADD COLUMN IF NOT EXISTS available DECIMAL(12, 4),
    ADD COLUMN IF NOT EXISTS reorder_point DECIMAL(12, 4)
        CHECK (reorder_point IS NULL OR reorder_point >= 0),
    ADD COLUMN IF NOT EXISTS max_stock DECIMAL(12, 4)
        CHECK (max_stock IS NULL OR max_stock > 0),
    ADD COLUMN IF NOT EXISTS workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

-- Backfill available = quantity - reserved for existing rows
UPDATE inventory_levels SET available = quantity - reserved WHERE available IS NULL;
-- Backfill workspace_id from warehouse
UPDATE inventory_levels il SET workspace_id = w.workspace_id
    FROM warehouses w WHERE il.warehouse_id = w.id AND il.workspace_id IS NULL;
-- Backfill updated_at
UPDATE inventory_levels SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL;

-- Make available NOT NULL after backfill
ALTER TABLE inventory_levels ALTER COLUMN available SET NOT NULL;
ALTER TABLE inventory_levels ALTER COLUMN updated_at SET NOT NULL;

-- Add non-negative quantity CHECK (BR-STK-004 default enforcement)
-- This is the safety net; workspace negative-stock override bypasses at app layer.
ALTER TABLE inventory_levels
    ADD CONSTRAINT chk_inventory_no_negative_stock
    CHECK (quantity >= 0);

-- Sanity: reserved cannot exceed quantity
ALTER TABLE inventory_levels
    ADD CONSTRAINT chk_inventory_reserved_consistency
    CHECK (reserved <= quantity);

-- Sanity: available should equal quantity - reserved
-- This is a denormalized cache; the app MUST maintain consistency.
-- We add a CHECK as a safety net.
ALTER TABLE inventory_levels
    ADD CONSTRAINT chk_inventory_available_consistency
    CHECK (available = quantity - reserved);

-- FIX #4: Auto-sync available quantity on inventory_levels UPDATE.
-- This trigger ensures available is always recomputed as quantity - reserved,
-- providing a DB-level safety net even if the app sets it incorrectly.
CREATE OR REPLACE FUNCTION sync_inventory_available()
RETURNS TRIGGER AS $$
BEGIN
    NEW.available := NEW.quantity - NEW.reserved;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_levels_sync_available
    BEFORE INSERT OR UPDATE ON inventory_levels
    FOR EACH ROW EXECUTE FUNCTION sync_inventory_available();

COMMENT ON FUNCTION sync_inventory_available() IS
    'DB-ENFORCED trigger ensuring available = quantity - reserved on every INSERT/UPDATE. '
    'This makes the CHECK constraint chk_inventory_available_consistency always pass '
    'and provides a safety net against application bugs that set available incorrectly.';

COMMENT ON COLUMN inventory_levels.reserved IS
    'APPLICATION-MAINTAINED. Quantity reserved by confirmed orders. '
    'Increased on order confirmation (BR-STK-001), decreased on shipment or cancellation (BR-STK-002/003). '
    'MUST use SELECT FOR UPDATE for concurrency safety (see CONCURRENCY SAFETY MODEL in header).';
COMMENT ON COLUMN inventory_levels.available IS
    'DB-MAINTAINED via trg_inventory_levels_sync_available trigger: available = quantity - reserved. '
    'Also enforced by CHECK constraint chk_inventory_available_consistency. '
    'Used for fast stock availability queries without computing at read time.';
COMMENT ON COLUMN inventory_levels.reorder_point IS
    'When available drops to or below this value, a low_stock_alert notification is generated (BR-STK-012).';
COMMENT ON COLUMN inventory_levels.max_stock IS
    'Maximum desired stock level. Used for reorder quantity suggestions: reorder_qty = max_stock - available.';
COMMENT ON CONSTRAINT chk_inventory_no_negative_stock ON inventory_levels IS
    'Default negative-stock prevention (BR-STK-004). '
    'Workspace override for negative stock is APP-ENFORCED; '
    'privileged operations may bypass this CHECK when allow_negative_stock is enabled.';

-- updated_at trigger
CREATE TRIGGER trg_inventory_levels_updated
    BEFORE UPDATE ON inventory_levels
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 2: Inventory Movements (NEW — replaces inventory_logs for new code)
-- ==========================================
-- Implements BR-STK-005: all stock changes MUST create a movement record.
-- This is a new, richer replacement for the basic inventory_logs table.
-- The old inventory_logs table is preserved for migration-safe coexistence.

CREATE TABLE inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES inventory_batches(id) ON DELETE SET NULL,

    -- Movement classification
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

    -- Quantity change: positive = increase, negative = decrease
    quantity_change DECIMAL(12, 4) NOT NULL CHECK (quantity_change <> 0),
    quantity_before DECIMAL(12, 4) NOT NULL,
    quantity_after DECIMAL(12, 4) NOT NULL,

    -- Cost tracking
    unit_cost DECIMAL(12, 4),
    total_cost DECIMAL(15, 2),

    -- Source references (polymorphic — only one set populated per movement_type)
    reference_type VARCHAR(50)
        CHECK (reference_type IS NULL OR reference_type IN (
            'order', 'shipment', 'grn', 'return', 'transfer',
            'production_order', 'adjustment', 'opening'
        )),
    reference_id UUID,        -- FK to the source entity

    -- Actor
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Reason (for adjustments)
    reason_code VARCHAR(100),
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (quantity_after = quantity_before + quantity_change),
    -- Positive types must have positive quantity_change
    CHECK (
        (movement_type IN ('purchase_receipt', 'return_restock', 'adjustment_increase',
                           'transfer_in', 'production_output', 'opening_balance')
            AND quantity_change > 0)
        OR
        (movement_type IN ('sale_shipment', 'return_dispose', 'supplier_return',
                           'adjustment_decrease', 'transfer_out', 'production_consume',
                           'damage', 'shrinkage', 'expired')
            AND quantity_change < 0)
    )
    ),

    -- FIX #2: Movement-source reference linkage consistency.
    -- Ensure reference_type aligns with movement_type.
    -- This prevents, e.g., a sale_shipment movement referencing a 'grn' source.
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
    'Immutable audit log of all stock quantity changes (BR-STK-005). '
    'Every mutation to inventory_levels.quantity MUST create a corresponding movement record. '
    'Positive quantity_change = stock increase; negative = decrease. '
    'CHECK constraints enforce: (1) quantity_after = quantity_before + quantity_change, '
    '(2) sign aligns with movement_type, (3) reference_type matches movement_type (FIX #2). '
    'The existing inventory_logs table is preserved for backward compatibility; '
    'new code MUST use inventory_movements exclusively.';
COMMENT ON COLUMN inventory_movements.movement_type IS
    'Classification per BR-STK-005. '
    'Positive: purchase_receipt, return_restock, adjustment_increase, transfer_in, production_output, opening_balance. '
    'Negative: sale_shipment, return_dispose, supplier_return, adjustment_decrease, transfer_out, production_consume, damage, shrinkage, expired.';
COMMENT ON COLUMN inventory_movements.reference_type IS
    'Must match movement_type per FIX #2 CHECK constraint. '
    'sale_shipment→shipment, purchase_receipt→grn, return_*→return, transfer_*→transfer, '
    'production_*→production_order, adjustment/damage/shrinkage/expired→adjustment, opening_balance→opening.';
COMMENT ON COLUMN inventory_movements.unit_cost IS
    'Cost per unit at time of movement. Used for COGS and inventory valuation.';


-- ==========================================
-- SECTION 3: Stock Reservations (NEW)
-- ==========================================
-- Implements BR-STK-001/002: order-based stock reservations.
-- Each reservation ties a confirmed order line to a specific warehouse stock.

CREATE TABLE stock_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    -- Reservation quantities
    reserved_quantity DECIMAL(12, 4) NOT NULL CHECK (reserved_quantity > 0),
    fulfilled_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (fulfilled_quantity >= 0),
    released_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (released_quantity >= 0),

    -- Status
    status VARCHAR(50) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'fulfilled', 'partially_fulfilled', 'released', 'expired')),

    -- Lifecycle
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fulfilled_at TIMESTAMPTZ,
    released_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    -- fulfilled + released cannot exceed reserved
    CHECK (fulfilled_quantity + released_quantity <= reserved_quantity),
    -- Status consistency
    CHECK (status <> 'fulfilled' OR fulfilled_at IS NOT NULL),
    CHECK (status <> 'released' OR released_at IS NOT NULL),
    -- FIX #3: Cannot fulfill a released reservation
    CHECK (NOT (status = 'released' AND fulfilled_quantity > 0 AND fulfilled_at > released_at)),
    -- Cannot release a fully fulfilled reservation
    CHECK (NOT (status = 'fulfilled' AND released_quantity > 0))
);

-- FIX #3: Reservation lifecycle guard trigger.
-- Prevents invalid transitions: no fulfillment after full release, no release after full fulfillment.
CREATE OR REPLACE FUNCTION guard_reservation_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
    -- Cannot fulfill after full release
    IF OLD.status = 'released' AND NEW.fulfilled_quantity > OLD.fulfilled_quantity THEN
        RAISE EXCEPTION 'Cannot fulfill reservation % after it has been fully released.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;

    -- Cannot release after full fulfillment
    IF OLD.status = 'fulfilled' AND NEW.released_quantity > OLD.released_quantity THEN
        RAISE EXCEPTION 'Cannot release reservation % after it has been fully fulfilled.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;

    -- Cannot exceed reserved_quantity (belt+suspenders with CHECK)
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

COMMENT ON FUNCTION guard_reservation_lifecycle() IS
    'FIX #3: DB-ENFORCED guard preventing invalid reservation transitions. '
    'No fulfillment after full release. No release after full fulfillment. '
    'Belt+suspenders with the table-level CHECK constraints.';

COMMENT ON TABLE stock_reservations IS
    'Order-based stock reservations (BR-STK-001/002). '
    'Created when order transitions to confirmed. Released on cancellation. '
    'Fulfilled when shipment is shipped (stock deducted from inventory_levels). '
    'fulfilled_quantity + released_quantity <= reserved_quantity is DB-ENFORCED (CHECK + trigger). '
    'Lifecycle guard: no fulfill-after-release, no release-after-fulfill (DB-ENFORCED by trigger). '
    'Concurrency: MUST use SELECT FOR UPDATE on inventory_levels before creating reservation.';
COMMENT ON COLUMN stock_reservations.reserved_quantity IS 'Original quantity reserved at confirmation time. Immutable after creation.';
COMMENT ON COLUMN stock_reservations.fulfilled_quantity IS 'Quantity fulfilled by shipments. Incremented when shipment ships. Cannot increase after full release.';
COMMENT ON COLUMN stock_reservations.released_quantity IS 'Quantity released by cancellation. Incremented when order/line cancelled. Cannot increase after full fulfillment.';


-- ==========================================
-- SECTION 4: Purchase Orders (NEW)
-- ==========================================
--
-- FIX #5: PURCHASE ORDER vs GENERIC ORDER COEXISTENCE MODEL
--
-- The base schema defines a generic `orders` table with order_type IN
-- ('quote','sale_order','purchase_order','dine_in','takeaway'). This works for
-- simple PO creation, but the purchasing lifecycle (BR-PUR-001 through BR-PUR-010)
-- requires richer semantics that the generic orders table cannot support:
--
--   1. SUPPLIER LINKAGE: PO requires supplier_contact_id with RESTRICT delete.
--      Generic orders use contact_id with customer semantics.
--   2. RECEIPT TRACKING: PO items need received_quantity, over-receipt cap (110%),
--      and GRN linkage. Generic order_items lack these fields.
--   3. FSM: PO FSM (draft→submitted→approved→partially_received→received→invoiced→closed)
--      differs from sales order FSM (draft→confirmed→processing→fulfilled→closed).
--   4. 3-WAY MATCHING: BR-PUR-005 requires PO↔GRN↔supplier invoice matching,
--      which is procurement-specific and cannot be modeled on generic orders.
--   5. CURRENCY: POs support multi-currency with exchange_rate (BR-PUR-009).
--   6. PRICE LOCK: PO prices are locked on submission (BR-PUR-008).
--
-- COEXISTENCE STRATEGY:
--   - Existing generic orders with order_type='purchase_order' remain valid for
--     basic PO records created before this migration.
--   - New PO operations use the dedicated purchase_orders table exclusively.
--   - The application layer routes PO endpoints (§22) to purchase_orders,
--     and sales endpoints (§14) to the generic orders table.
--   - No FK linkage between purchase_orders and orders; they are parallel models.
--   - Migration of legacy PO data from orders to purchase_orders is OPTIONAL
--     and handled by a separate data-migration script if needed.
--

CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    supplier_contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Document
    po_number VARCHAR(50),
    reference VARCHAR(100),

    -- Currency
    currency VARCHAR(10) NOT NULL DEFAULT 'LYD',
    exchange_rate DECIMAL(10, 4) NOT NULL DEFAULT 1.0000 CHECK (exchange_rate > 0),

    -- Amounts (populated on calculation)
    subtotal DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (subtotal >= 0),
    tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0),
    total_amount DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),

    -- Status FSM per business rules §10.2
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'submitted', 'approved', 'partially_received',
                          'received', 'invoiced', 'closed', 'cancelled', 'rejected')),

    -- Dates
    expected_delivery_date DATE,
    submitted_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    -- Notes
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    UNIQUE(workspace_id, po_number),
    CHECK (status <> 'approved' OR approved_at IS NOT NULL),
    CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

COMMENT ON TABLE purchase_orders IS
    'Dedicated purchase order table (BR-PUR-001 through BR-PUR-010). '
    'FSM: draft → submitted → approved → partially_received → received → invoiced → closed. '
    'Cancellation: only if no GRN exists (BR-PUR-006). '
    'FSM transitions and maker-checker are APP-ENFORCED. '
    'Prices locked on submission (BR-PUR-008). '
    'See FIX #5 comments above for coexistence with generic orders table.';

CREATE TABLE purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    po_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    unit_id UUID REFERENCES units_of_measure(id) ON DELETE SET NULL,

    -- Quantities
    ordered_quantity DECIMAL(12, 4) NOT NULL CHECK (ordered_quantity > 0),
    received_quantity DECIMAL(12, 4) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),

    -- Pricing (locked on submission per BR-PUR-008)
    unit_cost DECIMAL(12, 4) NOT NULL CHECK (unit_cost >= 0),
    tax_rate DECIMAL(5, 2) DEFAULT 0.00 CHECK (tax_rate >= 0),
    subtotal DECIMAL(15, 2) NOT NULL CHECK (subtotal >= 0),

    -- Snapshots
    product_name_snapshot VARCHAR(255),
    sku_snapshot VARCHAR(100),

    -- Line status
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    -- Over-receipt prevention (BR-PUR-004): received cannot exceed ordered
    -- Tolerance is workspace-configurable, so strict enforcement is at app layer.
    -- DB enforces basic: received_quantity <= ordered_quantity * 1.10 (10% hard cap)
    CHECK (received_quantity <= ordered_quantity * 1.10)
);

COMMENT ON TABLE purchase_order_items IS
    'PO line items (BR-PUR-001). Price locked on submission (BR-PUR-008). '
    'Over-receipt hard cap: received_quantity <= ordered_quantity * 1.10 (DB-ENFORCED). '
    'Workspace-configurable tolerance (default 0%) is APP-ENFORCED.';
COMMENT ON COLUMN purchase_order_items.received_quantity IS
    'Cumulative quantity received via GRN. Incremented per GRN item. '
    'Hard cap at 110% of ordered_quantity (DB-ENFORCED). '
    'Workspace tolerance (0% default) is APP-ENFORCED at GRN creation.';


-- ==========================================
-- SECTION 5: Goods Received Notes (NEW)
-- ==========================================
-- Implements BR-PUR-003: GRN links PO to physical receipt.

CREATE TABLE goods_received_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    po_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE RESTRICT,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    received_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Document
    grn_number VARCHAR(50),

    -- Status
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'confirmed', 'cancelled')),

    -- Dates
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

COMMENT ON TABLE goods_received_notes IS
    'Goods receipt tracking (BR-PUR-003). Links PO to physical warehouse receipt. '
    'On confirmation: inventory_levels.quantity increased, inventory_movement created. '
    'purchase_order_items.received_quantity incremented per GRN item. '
    'PO status transitions to partially_received or received.';

CREATE TABLE grn_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    grn_id UUID NOT NULL REFERENCES goods_received_notes(id) ON DELETE CASCADE,
    po_item_id UUID NOT NULL REFERENCES purchase_order_items(id) ON DELETE RESTRICT,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    -- Received details
    quantity_received DECIMAL(12, 4) NOT NULL CHECK (quantity_received > 0),
    condition VARCHAR(50) NOT NULL DEFAULT 'good'
        CHECK (condition IN ('good', 'damaged', 'partial')),

    -- Batch tracking (optional per BR-STK-007)
    batch_number VARCHAR(100),
    expiry_date DATE,

    -- Cost
    unit_cost DECIMAL(12, 4),

    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE grn_items IS
    'GRN line items. Each item links to a PO item and records received quantity. '
    'Batch tracking fields are optional (BR-STK-007). '
    'On GRN confirmation, inventory_movements are created per item.';

-- FIX #8: BATCH / LOT / EXPIRY TRACKING RULES
--
-- Batch tracking is OPTIONAL per product. Products with batch tracking enabled
-- (products.track_batches = TRUE or workspace-level setting) MUST:
--
--   1. RECEIPT: Every GRN item for a batch-tracked product MUST specify
--      batch_number (via grn_items.batch_number). If expiry tracking is enabled,
--      expiry_date MUST also be specified. On GRN confirmation, an inventory_batches
--      record is created or updated with the received quantity.
--      APP-ENFORCED: the service layer validates batch_number presence for
--      batch-tracked products on GRN creation.
--
--   2. SHIPMENT: Stock deduction for batch-tracked products MUST specify
--      shipment_items.batch_id. The deduction follows the workspace-configured
--      strategy: FIFO (first-in-first-out by manufacturing_date) or
--      FEFO (first-expiry-first-out by expiry_date).
--      APP-ENFORCED: the service layer selects batches in strategy order.
--
--   3. EXPIRY: Batches with expiry_date < CURRENT_DATE MUST be flagged:
--      inventory_batches.status = 'expired'. Expired batches are excluded from
--      available stock queries. A scheduled job updates batch status.
--      APP-ENFORCED: background job runs daily to flag expired batches.
--
--   4. MOVEMENT LINKAGE: All inventory_movements for batch-tracked products
--      MUST include batch_id. This enables per-batch movement audit trail.
--      APP-ENFORCED: the service layer sets batch_id on movement insert.
--
--   5. SERIAL NUMBERS: Products with serial tracking have unique serial_number
--      per batch (inventory_batches.serial_number, UNIQUE per workspace).
--      Each serial number represents quantity=1.
--      APP-ENFORCED: service layer validates serial uniqueness.
--
-- These rules are APP-ENFORCED because the batch-tracking flag is a product
-- attribute, and cross-table validation (product → batch requirement) cannot
-- be expressed as a single-table CHECK constraint.


-- ==========================================
-- SECTION 6: ALTER shipments — Fulfillment FSM
-- ==========================================
-- Enriches shipments with order linkage, fulfillment FSM, and warehouse reference.
-- API contract §23 requires: order_id, warehouse_id, fulfillment status.

ALTER TABLE shipments
    ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS return_id UUID,    -- FK added after returns table creation
    ADD COLUMN IF NOT EXISTS picked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS packed_at TIMESTAMPTZ;

-- Update status CHECK to include fulfillment FSM states
-- The base schema has: processing, picked_up, in_transit, out_for_delivery, delivered, returned
-- The API contract (§12.1) defines: pending, picking, packed, shipped, delivered, cancelled
-- We merge both: keep existing values, add new ones for the full FSM.
-- Cannot ALTER CHECK directly; add the new constraint as a replacement.
-- Since we can't drop inline CHECK, we add a broader named CHECK.
ALTER TABLE shipments DROP CONSTRAINT IF EXISTS shipments_status_check;
ALTER TABLE shipments
    ADD CONSTRAINT chk_shipments_status
    CHECK (status IN (
        -- Fulfillment FSM (API contract)
        'pending', 'picking', 'packed', 'shipped', 'delivered', 'cancelled',
        -- Legacy values (base schema)
        'processing', 'picked_up', 'in_transit', 'out_for_delivery', 'returned'
    ));

COMMENT ON COLUMN shipments.order_id IS 'FK to the confirmed order being fulfilled (BR-STK-009).';
COMMENT ON COLUMN shipments.warehouse_id IS 'Source warehouse for this shipment.';
COMMENT ON COLUMN shipments.picked_at IS 'Timestamp when picking started.';
COMMENT ON COLUMN shipments.packed_at IS 'Timestamp when packing completed.';


-- ==========================================
-- SECTION 7: Shipment Items (NEW)
-- ==========================================
-- Per-line fulfillment detail for shipments.

CREATE TABLE shipment_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    shipment_id UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(id) ON DELETE SET NULL,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,

    -- Quantities
    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),

    -- Batch tracking (optional)
    batch_id UUID REFERENCES inventory_batches(id) ON DELETE SET NULL,

    -- Reservation linkage
    reservation_id UUID REFERENCES stock_reservations(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE shipment_items IS
    'Per-line fulfillment for shipments (BR-STK-009). '
    'Each item specifies product, quantity, and source warehouse. '
    'On shipment status → shipped: inventory_movement created per item (BR-STK-003). '
    'Stock reservation is fulfilled per item (reservation.fulfilled_quantity incremented).';

-- FIX #6: SHIPMENT QUANTITY INTEGRITY
--
-- Shipment item quantities are subject to the following constraints:
--
--   1. CANNOT EXCEED ORDER LINE QUANTITY:
--      For a given order_item_id, the SUM of shipment_items.quantity across all
--      non-cancelled shipments MUST NOT exceed order_items.quantity.
--      APP-ENFORCED: service layer computes cumulative shipped qty before inserting.
--      This is a cross-row aggregate constraint and cannot be a simple CHECK.
--
--   2. CANNOT EXCEED AVAILABLE STOCK:
--      Before shipping, shipment_items.quantity for each (product_id, warehouse_id)
--      MUST NOT exceed inventory_levels.available (or .quantity for reserved items).
--      APP-ENFORCED: service layer checks stock via SELECT FOR UPDATE before deduction.
--
--   3. CANNOT EXCEED RESERVATION:
--      If reservation_id is set, shipment_items.quantity MUST NOT exceed
--      reservation.reserved_quantity - reservation.fulfilled_quantity.
--      APP-ENFORCED: service layer validates and increments fulfilled_quantity.
--
--   4. PARTIAL SHIPMENT:
--      Partial shipment is allowed (BR-STK-009). When a shipment contains fewer
--      items than the order, the remaining items form a back-order. The order
--      transitions to 'partially_fulfilled' until all lines are shipped.
--      APP-ENFORCED.
--
-- The DB enforces: shipment_items.quantity > 0 (via table CHECK).
-- The aggregate constraints above are APP-ENFORCED because they span multiple rows.
-- The application MUST validate before INSERT into shipment_items.


-- ==========================================
-- SECTION 8: Returns & Return Items (NEW)
-- ==========================================
-- Implements BR-RFD-002 through BR-RFD-008.

CREATE TABLE returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Return type
    return_type VARCHAR(50) NOT NULL DEFAULT 'customer'
        CHECK (return_type IN ('customer', 'supplier')),

    -- Status FSM per §12
    status VARCHAR(50) NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'approved', 'received', 'inspected',
                          'restocked', 'disposed', 'rejected', 'cancelled')),

    -- Document
    return_number VARCHAR(50),

    -- Refund tracking
    refund_amount DECIMAL(12, 2) CHECK (refund_amount IS NULL OR refund_amount >= 0),
    credit_note_id UUID,    -- FK to credit_notes (created in 003)

    -- Reason
    reason TEXT NOT NULL,

    -- Dates
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

COMMENT ON TABLE returns IS
    'Customer and supplier return tracking (BR-RFD-002 through BR-RFD-008). '
    'FSM: requested → approved → received → inspected → restocked|disposed. '
    'Refund processing creates credit_note and/or payment reversal. '
    'Self-approval prevented: approved_by != created_by (APP-ENFORCED per BR-RFD-008). '
    'FSM transitions are APP-ENFORCED.';

-- FIX #7: RETURN → FINANCE INTEGRATION
--
-- Returns interact with the financial system through two paths:
--
-- PATH A: CUSTOMER RETURN → CREDIT NOTE → REFUND
--   1. Return requested (returns.status = 'requested')
--   2. Return approved (returns.status = 'approved')
--   3. Goods received (returns.status = 'received')
--   4. Inspection completed (returns.status = 'inspected')
--      → For each return_item, set condition and disposition
--   5a. If disposition = 'restock':
--      → Create inventory_movement (type=return_restock, quantity_change > 0)
--      → Increment inventory_levels.quantity and .available
--      → Set return_items.restocked_warehouse_id and .restocked_quantity
--   5b. If disposition = 'dispose':
--      → Create inventory_movement (type=return_dispose, quantity_change < 0)
--      → NO stock change (already deducted on original shipment)
--      → Write-off journal entry if item has value
--   6. Credit note created (BR-RFD-001):
--      → Insert into credit_notes (from 003_financial_controls.sql)
--      → Set returns.credit_note_id
--      → Credit note amount = SUM of return_items value
--   7. Refund if applicable (BR-RFD-005):
--      → Payment reversal OR customer credit application
--      → Returns.refund_amount set
--      → Refund approval required for amount > threshold (BR-RFD-006)
--
-- PATH B: SUPPLIER RETURN
--   1. Return requested against PO/GRN (return_type = 'supplier')
--   2. Approved → goods shipped back to supplier
--   3. Inventory deducted (movement type=supplier_return)
--   4. Supplier credit note or replacement negotiated (app-layer)
--
-- ALL PATHS ARE APP-ENFORCED. The DB provides:
--   - returns.credit_note_id FK to link to credit_notes
--   - returns.refund_amount for tracking
--   - return_items.disposition for restock/dispose decision
--   - return_items.restocked_quantity <= quantity CHECK
--   - Inventory movement type enforcement via inventory_movements CHECK
--
-- The service layer orchestrates: return inspection → inventory movement →
-- credit note creation → refund processing, all within a transaction.

CREATE TABLE return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    return_id UUID NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,

    -- Quantities
    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),

    -- Reason per item
    reason_code VARCHAR(100) NOT NULL,
    reason_detail TEXT,

    -- Inspection result (filled during inspection)
    condition VARCHAR(50)
        CHECK (condition IS NULL OR condition IN ('good', 'damaged', 'defective')),
    disposition VARCHAR(50)
        CHECK (disposition IS NULL OR disposition IN ('restock', 'dispose')),

    -- Restocking
    restocked_warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
    restocked_quantity DECIMAL(12, 4) DEFAULT 0 CHECK (restocked_quantity >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (restocked_quantity <= quantity),
    -- Disposition consistency: if restocked, must have warehouse
    CHECK (disposition <> 'restock' OR restocked_warehouse_id IS NOT NULL),
    -- If restocked, restocked_quantity must be > 0
    CHECK (disposition <> 'restock' OR restocked_quantity > 0)
);

COMMENT ON TABLE return_items IS
    'Return line items (BR-RFD-002). '
    'Inspection fills condition + disposition (BR-RFD-004). '
    'On restock: inventory_movement created with type return_restock; '
    'restocked_warehouse_id MUST be set (DB-ENFORCED CHECK). '
    'On dispose: inventory_movement created with type return_dispose. '
    'See FIX #7 comments above for full return→finance integration path.';

-- Now add the FK from shipments.return_id to returns
ALTER TABLE shipments
    ADD CONSTRAINT fk_shipments_return FOREIGN KEY (return_id) REFERENCES returns(id) ON DELETE SET NULL;


-- ==========================================
-- SECTION 9: updated_at Triggers
-- ==========================================

CREATE TRIGGER trg_inventory_movements_no_update
    BEFORE UPDATE ON inventory_movements
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_update();

-- ⚠️ We need a simple immutability guard function if it doesn't exist yet.
-- If prevent_immutable_update doesn't exist, we create it here.
CREATE OR REPLACE FUNCTION prevent_immutable_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'This table is immutable. Rows cannot be updated after insertion.'
        USING ERRCODE = 'check_violation';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Re-create the trigger (in case function was just created)
DROP TRIGGER IF EXISTS trg_inventory_movements_no_update ON inventory_movements;
CREATE TRIGGER trg_inventory_movements_no_update
    BEFORE UPDATE ON inventory_movements
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_update();

COMMENT ON FUNCTION prevent_immutable_update() IS
    'Guard function preventing any UPDATE on immutable audit tables. '
    'Used on inventory_movements to enforce immutability (BR-STK-005).';

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

-- Inventory levels (new columns)
CREATE INDEX idx_inventory_levels_workspace ON inventory_levels(workspace_id)
    WHERE workspace_id IS NOT NULL;
CREATE INDEX idx_inventory_levels_low_stock ON inventory_levels(workspace_id, product_id)
    WHERE reorder_point IS NOT NULL AND available <= reorder_point;

-- Inventory movements
CREATE INDEX idx_inventory_movements_workspace ON inventory_movements(workspace_id);
CREATE INDEX idx_inventory_movements_warehouse ON inventory_movements(warehouse_id);
CREATE INDEX idx_inventory_movements_product ON inventory_movements(product_id);
CREATE INDEX idx_inventory_movements_type ON inventory_movements(movement_type);
CREATE INDEX idx_inventory_movements_ref ON inventory_movements(reference_type, reference_id)
    WHERE reference_id IS NOT NULL;
CREATE INDEX idx_inventory_movements_created ON inventory_movements(workspace_id, created_at DESC);
CREATE INDEX idx_inventory_movements_batch ON inventory_movements(batch_id)
    WHERE batch_id IS NOT NULL;

-- Stock reservations
CREATE INDEX idx_stock_reservations_workspace ON stock_reservations(workspace_id);
CREATE INDEX idx_stock_reservations_order ON stock_reservations(order_id);
CREATE INDEX idx_stock_reservations_order_item ON stock_reservations(order_item_id);
CREATE INDEX idx_stock_reservations_warehouse ON stock_reservations(warehouse_id);
CREATE INDEX idx_stock_reservations_product ON stock_reservations(product_id);
CREATE INDEX idx_stock_reservations_active ON stock_reservations(workspace_id, status)
    WHERE status = 'active';

-- Purchase orders
CREATE INDEX idx_purchase_orders_workspace ON purchase_orders(workspace_id);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders(supplier_contact_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders(status);
CREATE INDEX idx_purchase_orders_created ON purchase_orders(workspace_id, created_at DESC);

-- Purchase order items
CREATE INDEX idx_po_items_po ON purchase_order_items(po_id);
CREATE INDEX idx_po_items_product ON purchase_order_items(product_id);

-- GRN
CREATE INDEX idx_grn_workspace ON goods_received_notes(workspace_id);
CREATE INDEX idx_grn_po ON goods_received_notes(po_id);
CREATE INDEX idx_grn_warehouse ON goods_received_notes(warehouse_id);
CREATE INDEX idx_grn_status ON goods_received_notes(status);

-- GRN items
CREATE INDEX idx_grn_items_grn ON grn_items(grn_id);
CREATE INDEX idx_grn_items_po_item ON grn_items(po_item_id);
CREATE INDEX idx_grn_items_product ON grn_items(product_id);

-- Shipments (new columns)
CREATE INDEX idx_shipments_order ON shipments(order_id)
    WHERE order_id IS NOT NULL;
CREATE INDEX idx_shipments_warehouse ON shipments(warehouse_id)
    WHERE warehouse_id IS NOT NULL;
CREATE INDEX idx_shipments_return ON shipments(return_id)
    WHERE return_id IS NOT NULL;

-- Shipment items
CREATE INDEX idx_shipment_items_workspace ON shipment_items(workspace_id);
CREATE INDEX idx_shipment_items_shipment ON shipment_items(shipment_id);
CREATE INDEX idx_shipment_items_order_item ON shipment_items(order_item_id)
    WHERE order_item_id IS NOT NULL;
CREATE INDEX idx_shipment_items_product ON shipment_items(product_id);
CREATE INDEX idx_shipment_items_reservation ON shipment_items(reservation_id)
    WHERE reservation_id IS NOT NULL;

-- Returns
CREATE INDEX idx_returns_workspace ON returns(workspace_id);
CREATE INDEX idx_returns_order ON returns(order_id)
    WHERE order_id IS NOT NULL;
CREATE INDEX idx_returns_contact ON returns(contact_id);
CREATE INDEX idx_returns_status ON returns(status);
CREATE INDEX idx_returns_type ON returns(return_type);

-- Return items
CREATE INDEX idx_return_items_return ON return_items(return_id);
CREATE INDEX idx_return_items_product ON return_items(product_id);


-- ==========================================
-- SECTION 11: Composite Unique Constraints (workspace FK validation)
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

-- inventory_levels: RLS not previously enabled (no workspace_id in base schema).
-- Now that workspace_id is added, enable RLS.
ALTER TABLE inventory_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inventory_levels ON inventory_levels
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);


-- ==========================================
-- SECTION 14: APPLICATION-LAYER INVARIANTS DOCUMENTATION
-- ==========================================

-- ⚠️ APPLICATION-LAYER INVARIANTS for inventory operations:
--
--   1. CONCURRENCY (all tables):
--      All inventory_levels mutations MUST use SELECT FOR UPDATE on the target row
--      before computing new values. This includes: reservation, shipment, GRN receipt,
--      return restock, adjustment, transfer. Without FOR UPDATE, concurrent operations
--      will cause lost-update race conditions.
--
--   2. STOCK RESERVATION LIFECYCLE:
--      - On order.confirmed: create stock_reservation, increment inventory_levels.reserved,
--        decrement inventory_levels.available. APP-ENFORCED.
--      - On shipment.shipped: increment reservation.fulfilled_quantity, decrement
--        inventory_levels.quantity and inventory_levels.reserved. APP-ENFORCED.
--      - On order.cancelled: increment reservation.released_quantity, decrement
--        inventory_levels.reserved, increment inventory_levels.available. APP-ENFORCED.
--
--   3. GRN → INVENTORY:
--      On GRN confirmation: for each grn_item, increment inventory_levels.quantity and
--      inventory_levels.available. Create inventory_movement with type=purchase_receipt.
--      Increment purchase_order_items.received_quantity. APP-ENFORCED.
--
--   4. RETURN → INVENTORY:
--      On return inspection: for items with disposition=restock, increment
--      inventory_levels.quantity and available. Create movement type=return_restock.
--      For disposition=dispose, create movement type=return_dispose (no stock change).
--      APP-ENFORCED.
--
--   5. TRANSFER → INVENTORY (existing stock_transfers table):
--      On transfer.approved (dispatch): decrement source warehouse quantity/available.
--      Create movement type=transfer_out. APP-ENFORCED.
--      On transfer.received: increment destination warehouse quantity/available.
--      Create movement type=transfer_in. APP-ENFORCED.
--
--   6. NEGATIVE STOCK OVERRIDE:
--      Default: chk_inventory_no_negative_stock CHECK prevents quantity < 0.
--      When workspace has allow_negative_stock enabled, the application uses a
--      privileged DB role that bypasses CHECK constraints, or uses a deferred
--      constraint approach. APP-ENFORCED override decision.
--
--   7. MOVEMENT AUDIT (BR-STK-005):
--      EVERY change to inventory_levels.quantity MUST create a corresponding
--      inventory_movements row. inventory_movements is IMMUTABLE (enforced by
--      trg_inventory_movements_no_update trigger). No exceptions.
--
--   8. PO CANCELLATION (BR-PUR-006):
--      PO may be cancelled ONLY IF no GRN exists. Partially received POs
--      cannot be cancelled; individual unreceived lines may be marked cancelled.
--      APP-ENFORCED.
--
--   9. OVER-RECEIPT (BR-PUR-004):
--      Hard cap: 110% of ordered_quantity (DB-ENFORCED by CHECK on po_items).
--      Workspace-configurable tolerance (default 0%) is APP-ENFORCED.
--
--  10. SELF-APPROVAL PREVENTION (BR-RFD-008):
--      returns.approved_by MUST NOT equal returns.created_by. APP-ENFORCED.


-- ==========================================
-- END OF MIGRATION 005
-- ==========================================
-- Validation checklist:
--   [ ] inventory_levels ALTERed with reserved, available, reorder_point, max_stock, workspace_id
--   [ ] inventory_levels has chk_inventory_no_negative_stock CHECK
--   [ ] inventory_levels has chk_inventory_reserved_consistency CHECK (reserved <= quantity)
--   [ ] inventory_levels has chk_inventory_available_consistency CHECK (available = quantity - reserved)
--   [ ] inventory_levels has trg_inventory_levels_sync_available trigger (FIX #4)
--   [ ] inventory_levels.reserved documented as APPLICATION-MAINTAINED
--   [ ] inventory_levels.available documented as DB-MAINTAINED (trigger sync)
--   [ ] Concurrency safety model documented with full locking protocol (FIX #1)
--   [ ] inventory_movements table exists with 15 movement_type values and sign enforcement
--   [ ] inventory_movements has reference_type ↔ movement_type consistency CHECK (FIX #2)
--   [ ] inventory_movements is IMMUTABLE (trg_inventory_movements_no_update trigger)
--   [ ] stock_reservations table exists with fulfilled/released tracking
--   [ ] stock_reservations has CHECK: fulfilled + released <= reserved
--   [ ] stock_reservations has guard_reservation_lifecycle() trigger (FIX #3)
--   [ ] stock_reservations prevents fulfill-after-release and release-after-fulfill
--   [ ] purchase_orders table exists with full PO lifecycle FSM
--   [ ] purchase_orders vs generic orders coexistence documented (FIX #5)
--   [ ] purchase_order_items table exists with over-receipt hard cap (110%)
--   [ ] goods_received_notes table exists with PO linkage
--   [ ] grn_items table exists with batch tracking support
--   [ ] Batch/lot/expiry tracking rules documented (FIX #8)
--   [ ] shipments ALTERed with order_id, warehouse_id, fulfillment FSM dates
--   [ ] shipments status CHECK includes both fulfillment and legacy values
--   [ ] shipment_items table exists with per-line fulfillment and reservation linkage
--   [ ] Shipment quantity integrity documented (FIX #6)
--   [ ] returns table exists with customer/supplier support and FSM
--   [ ] return_items table exists with inspection/disposition tracking
--   [ ] return_items has restock warehouse and quantity consistency CHECKs
--   [ ] Return → finance integration path documented (FIX #7)
--   [ ] All new tables have updated_at triggers
--   [ ] All new tables have workspace FK isolation triggers
--   [ ] All new tables have RLS policies
--   [ ] inventory_levels now has RLS (workspace_id added)
--   [ ] All new tables have composite UQ (workspace_id, id)
--   [ ] Indexes: inventory_movements (7), stock_reservations (6), purchase_orders (4),
--       po_items (2), GRN (4), grn_items (3), shipments (3), shipment_items (5),
--       returns (5), return_items (2), inventory_levels (2)
--   [ ] 10+ application-layer invariants documented
--   [ ] Inventory consistency model + concurrency safety documented in header
--   [ ] prevent_immutable_update() function exists for immutable tables
--   [ ] sync_inventory_available() function exists for available sync
--   [ ] guard_reservation_lifecycle() function exists for reservation lifecycle
-- ==========================================
