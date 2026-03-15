-- ==========================================
-- SmartBiz AI - Ultimate Database Schema (Production Ready)
-- Database: PostgreSQL
-- ==========================================

-- تفعيل الإضافات المطلوبة (مطلوب لـ gen_random_uuid في PostgreSQL < 13)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. جدول الشركات (مساحات العمل - محدث لتصنيف الذكاء الاصطناعي والاشتراكات)
CREATE TABLE workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    industry_type VARCHAR(100), -- (مثال: retail, manufacturing, services)
    business_size VARCHAR(50), -- (micro, small, medium, enterprise)
    onboarding_data JSONB, -- (لتخزين إجابات العميل للذكاء الاصطناعي)
    invite_code VARCHAR(50) UNIQUE,
    ui_configuration JSONB, 
    subscription_status VARCHAR(50) DEFAULT 'freemium' CHECK (subscription_status IN ('freemium', 'trial', 'active', 'suspended', 'cancelled')),
    max_users INT DEFAULT 1, 
    subscription_end_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- 2. جدول الفروع (مختلف عن المخازن)
CREATE TABLE branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    location TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);

-- 3. جدول الأقسام
CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    manager_id UUID, -- (ستُربط لاحقاً)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);

-- 4. جدول ورديات العمل
CREATE TABLE shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    grace_period_minutes INT DEFAULT 15,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. جدول الأدوار (Roles) التفصيلي
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    permissions JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);

-- 6. جدول المستخدمين (المديرين والموظفين)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    manager_id UUID REFERENCES users(id) ON DELETE SET NULL,
    shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    role_id UUID REFERENCES roles(id) ON DELETE SET NULL,
    full_name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    permissions JSONB, -- (صلاحيات استثنائية للمستخدم غير دورة)
    hire_date DATE DEFAULT CURRENT_DATE,
    base_salary DECIMAL(10, 2) DEFAULT 0.00,
    annual_leave_balance INT DEFAULT 21, 
    approval_status VARCHAR(50) DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT FALSE,
    UNIQUE(workspace_id, phone_number)
);

-- إضافة المفتاح الأجنبي لمدير القسم
ALTER TABLE departments ADD CONSTRAINT fk_department_manager FOREIGN KEY (manager_id) REFERENCES users(id) ON DELETE SET NULL;

-- 7. جدول جهات الاتصال (العملاء والموردين)
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('customer', 'supplier', 'both')),
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    tax_number VARCHAR(50), -- (الرقم الضريبي)
    balance DECIMAL(12, 2) DEFAULT 0.00, -- ⚠️ CACHED ONLY - source of truth: invoices + payments. Updated async by app.
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 8. جدول شرائح الضرائب
CREATE TABLE taxes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    rate DECIMAL(5, 2) NOT NULL CHECK (rate >= 0),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);

-- 9. جدول تصنيفات المنتجات (Categories)
CREATE TABLE product_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    parent_id UUID REFERENCES product_categories(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, parent_id, name)
);

-- 10. جدول المنتجات / الخدمات
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    category_id UUID REFERENCES product_categories(id) ON DELETE SET NULL,
    type VARCHAR(50) DEFAULT 'physical' CHECK (type IN ('physical', 'service', 'digital', 'subscription')),
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100), 
    unit_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول units_of_measure)
    base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
    cost_price DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (cost_price >= 0),
    tax_id UUID REFERENCES taxes(id) ON DELETE SET NULL,
    min_stock_alert INT DEFAULT 5,
    dynamic_attributes JSONB, 
    is_deleted BOOLEAN DEFAULT FALSE, 
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, sku)
);

-- 11. جدول المخازن
CREATE TABLE warehouses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL, -- (المخزن تابع لأي فرع)
    name VARCHAR(255) NOT NULL,
    location TEXT,
    UNIQUE(workspace_id, name)
);

-- 12. جدول كميات المنتجات داخل كل مخزن
CREATE TABLE inventory_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id UUID NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول product_variants)
    quantity DECIMAL(12, 4) NOT NULL DEFAULT 0
);

-- فهارس جزئية لحل مشكلة UNIQUE مع القيم الفارغة (NULL)
CREATE UNIQUE INDEX uq_inventory_no_variant
ON inventory_levels(warehouse_id, product_id)
WHERE variant_id IS NULL;

CREATE UNIQUE INDEX uq_inventory_with_variant
ON inventory_levels(warehouse_id, product_id, variant_id)
WHERE variant_id IS NOT NULL;

-- 13. جدول سجل حركة المخزون
CREATE TABLE inventory_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    warehouse_id UUID REFERENCES warehouses(id),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    change_type VARCHAR(50) NOT NULL,
    quantity_changed DECIMAL(12, 4) NOT NULL,
    new_quantity DECIMAL(12, 4) NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 14. جدول أوامر الشغل
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    dining_table_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول dining_tables - للمطاعم)
    created_by UUID REFERENCES users(id),
    contact_id UUID REFERENCES contacts(id),
    order_type VARCHAR(50) NOT NULL CHECK (order_type IN ('quote', 'sale_order', 'purchase_order', 'dine_in', 'takeaway')),
    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'confirmed', 'processing', 'completed', 'cancelled')),
    currency VARCHAR(10) DEFAULT 'LYD',
    exchange_rate DECIMAL(10, 4) DEFAULT 1.0000,
    total_amount DECIMAL(12, 2) NOT NULL,
    valid_until DATE,
    order_number VARCHAR(50), -- (رقم الطلب التسلسلي من document_sequences)
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, order_number)
);

-- 15. جدول تفاصيل أوامر الشغل
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id),
    variant_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول product_variants)
    unit_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول units_of_measure)
    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal DECIMAL(12, 2) NOT NULL CHECK (subtotal >= 0),
    product_name_snapshot VARCHAR(255), -- (اسم المنتج وقت الطلب)
    sku_snapshot VARCHAR(100) -- (رمز SKU وقت الطلب)
);

-- 16. جدول الفواتير
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    dining_table_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول dining_tables - للمطاعم)
    created_by UUID REFERENCES users(id),
    contact_id UUID REFERENCES contacts(id),
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    parent_invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    invoice_type VARCHAR(50) DEFAULT 'sale' CHECK (invoice_type IN ('sale', 'purchase', 'return', 'refund')),
    return_reason TEXT,
    currency VARCHAR(10) DEFAULT 'LYD',
    exchange_rate DECIMAL(10, 4) DEFAULT 1.0000,
    total_amount DECIMAL(12, 2) NOT NULL,
    discount_amount DECIMAL(12, 2) DEFAULT 0.00,
    net_amount DECIMAL(12, 2) NOT NULL,
    payment_status VARCHAR(50) DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'partial', 'paid', 'overdue', 'refunded')),
    tax_amount DECIMAL(12, 2) DEFAULT 0.00,
    due_date DATE,
    invoice_number VARCHAR(50), -- (رقم الفاتورة التسلسلي من document_sequences)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, invoice_number)
);

-- 17. جدول تفاصيل الفاتورة
CREATE TABLE invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES invoices(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id),
    variant_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول product_variants)
    unit_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول units_of_measure)
    warehouse_id UUID REFERENCES warehouses(id),
    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    discount_amount DECIMAL(12, 2) DEFAULT 0.00 CHECK (discount_amount >= 0),
    tax_amount DECIMAL(12, 2) DEFAULT 0.00 CHECK (tax_amount >= 0),
    subtotal DECIMAL(12, 2) NOT NULL CHECK (subtotal >= 0),
    product_name_snapshot VARCHAR(255), -- (اسم المنتج وقت الفاتورة)
    sku_snapshot VARCHAR(100), -- (رمز SKU وقت الفاتورة)
    tax_rate_snapshot DECIMAL(5, 2) -- (نسبة الضريبة وقت الفاتورة)
);

-- 18. جدول شجرة الحسابات (Chart of Accounts)
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    parent_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
    balance DECIMAL(15, 2) DEFAULT 0.00, -- ⚠️ CACHED ONLY - source of truth: SUM from journal_lines. Updated async by app/trigger.
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, code)
);

-- 19. جدول قيود اليومية (Journal Entries)
CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    reference VARCHAR(100),
    description TEXT NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 20. جدول تفاصيل القيود (مدين ودائن)
CREATE TABLE journal_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id),
    debit DECIMAL(15, 2) DEFAULT 0.00,
    credit DECIMAL(15, 2) DEFAULT 0.00,
    description TEXT,
    CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);

-- 21. جدول المدفوعات (لربط الدفعات المتعددة بفاتورة واحدة)
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    invoice_id UUID REFERENCES invoices(id) ON DELETE CASCADE,
    account_id UUID REFERENCES accounts(id),
    amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(50) NOT NULL CHECK (payment_method IN ('cash', 'bank_transfer', 'check', 'card', 'mobile_payment')),
    reference_number VARCHAR(100),
    payment_date DATE DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES users(id),
    payment_number VARCHAR(50), -- (رقم الدفعة التسلسلي من document_sequences)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, payment_number)
);

-- 22. جدول المعاملات المالية (للمصروفات الحرة والإيرادات غير المرتبطة بفاتورة)
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id),
    contact_id UUID REFERENCES contacts(id),
    account_id UUID REFERENCES accounts(id), -- (للمصروفات والإيرادات)
    from_account_id UUID REFERENCES accounts(id), -- (للتحويلات: من حساب)
    to_account_id UUID REFERENCES accounts(id), -- (للتحويلات: إلى حساب)
    transaction_type VARCHAR(50) NOT NULL CHECK (transaction_type IN ('income', 'expense', 'transfer')),
    amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(50) DEFAULT 'cash' CHECK (payment_method IN ('cash', 'bank_transfer', 'check', 'card', 'mobile_payment')),
    notes TEXT,
    transaction_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        (transaction_type IN ('income', 'expense') AND account_id IS NOT NULL)
        OR
        (transaction_type = 'transfer' AND from_account_id IS NOT NULL AND to_account_id IS NOT NULL AND from_account_id <> to_account_id)
    )
);

-- 23. جدول الأصول الثابتة
CREATE TABLE fixed_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    purchase_date DATE NOT NULL,
    purchase_price DECIMAL(12, 2) NOT NULL,
    current_value DECIMAL(12, 2) NOT NULL,
    depreciation_rate DECIMAL(5, 2) DEFAULT 0.00,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'disposed', 'under_maintenance')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 24. جدول المصاريف المتكررة
CREATE TABLE recurring_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    category VARCHAR(100) NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    frequency VARCHAR(50) DEFAULT 'monthly' CHECK (frequency IN ('daily', 'weekly', 'monthly', 'quarterly', 'semi_annual', 'annual')),
    next_due_date DATE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 25. جدول الحضور والانصراف
CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    check_in TIMESTAMPTZ,
    check_out TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'present' CHECK (status IN ('present', 'absent', 'late', 'half_day', 'remote')),
    notes TEXT,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE(workspace_id, user_id, date),
    CHECK (check_out IS NULL OR check_in IS NULL OR check_out >= check_in)
);

-- 26. جدول طلبات الإجازات
CREATE TABLE leaves (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    leave_type VARCHAR(50) NOT NULL CHECK (leave_type IN ('annual', 'sick', 'unpaid', 'maternity', 'paternity', 'emergency')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    reason TEXT,
    CHECK (end_date >= start_date)
);

-- 27. جدول الرواتب الشهري
CREATE TABLE payroll (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    month INT NOT NULL CHECK (month BETWEEN 1 AND 12),
    year INT NOT NULL CHECK (year >= 2000),
    base_salary DECIMAL(10, 2) NOT NULL,
    bonuses DECIMAL(10, 2) DEFAULT 0.00,
    deductions DECIMAL(10, 2) DEFAULT 0.00,
    net_salary DECIMAL(10, 2) GENERATED ALWAYS AS (base_salary + bonuses - deductions) STORED,
    payment_status VARCHAR(50) DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'partial')),
    processed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, user_id, month, year)
);

-- 28. جدول الشحنات
CREATE TABLE shipments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    invoice_id UUID REFERENCES invoices(id),
    contact_id UUID REFERENCES contacts(id),
    delivery_driver_id UUID REFERENCES users(id) ON DELETE SET NULL, -- (السائق/المندوب المسؤول عن التوصيل)
    tracking_number VARCHAR(100),
    shipping_provider VARCHAR(100),
    origin TEXT NOT NULL,
    destination TEXT NOT NULL,
    weight DECIMAL(10, 2),
    customs_fees DECIMAL(12, 2) DEFAULT 0.00,
    shipping_cost DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(50) DEFAULT 'processing' CHECK (status IN ('processing', 'picked_up', 'in_transit', 'out_for_delivery', 'delivered', 'returned')),
    estimated_delivery_date DATE,
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    shipment_number VARCHAR(50), -- (رقم الشحنة التسلسلي من document_sequences)
    UNIQUE(workspace_id, tracking_number),
    UNIQUE(workspace_id, shipment_number),
    CHECK (delivered_at IS NULL OR shipped_at IS NULL OR delivered_at >= shipped_at)
);

-- 29. جدول سجل المراقبة الصارم
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID NOT NULL,
    old_values JSONB,
    new_values JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 30. جدول المشاريع
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    manager_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'planning' CHECK (status IN ('planning', 'in_progress', 'on_hold', 'completed', 'cancelled')),
    budget DECIMAL(12, 2) DEFAULT 0.00,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_date IS NULL OR end_date >= start_date)
);

-- 31. جدول المهام
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE, -- (مضاف للـ RLS والفلترة المباشرة)
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'review', 'done', 'cancelled')),
    due_date DATE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 32. جدول مكونات المنتجات (BOM)
CREATE TABLE bill_of_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    final_product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    raw_material_id UUID REFERENCES products(id) ON DELETE CASCADE,
    unit_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول units_of_measure - وحدة قياس المادة الخام)
    quantity_required DECIMAL(10, 4) NOT NULL,
    UNIQUE(final_product_id, raw_material_id)
);

-- 33. أوامر الإنتاج والتصنيع
CREATE TABLE production_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    work_center_id UUID, -- (يُربط لاحقاً بعد إنشاء جدول work_centers)
    target_quantity DECIMAL(12, 4) NOT NULL CHECK (target_quantity > 0),
    status VARCHAR(50) DEFAULT 'planned' CHECK (status IN ('planned', 'in_progress', 'done', 'cancelled')),
    warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,
    production_order_number VARCHAR(50), -- (رقم أمر الإنتاج التسلسلي)
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 34. جدول المرفقات والملفات (Attachments)
CREATE TABLE attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    entity_type VARCHAR(100) NOT NULL, -- (مثال: invoices, projects, contacts)
    entity_id UUID NOT NULL, -- (رقم الفاتورة أو المشروع اللي الملف مربوط بيه)
    file_name VARCHAR(255) NOT NULL,
    file_url TEXT NOT NULL, -- (رابط الملف على AWS S3 أو Cloud Storage)
    file_type VARCHAR(50), -- (pdf, image/png)
    file_size INT, -- (حجم الملف بالبايت)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 35. جدول الإشعارات (Notifications)
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- (لمن موجه الإشعار؟)
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'info' CHECK (type IN ('info', 'warning', 'alert', 'success')),
    is_read BOOLEAN DEFAULT FALSE,
    link_url TEXT, -- (رابط داخلي يودي العميل للفاتورة أو الطلب)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- الوحدات الإضافية (Modular Extensions)
-- ==========================================

-- 36. جدول متغيرات المنتجات (Product Variants - للألوان والمقاسات وغيرها)
CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    sku VARCHAR(100), -- (رمز SKU فريد للمتغير داخل المنتج)
    name VARCHAR(255) NOT NULL,
    price_override DECIMAL(10, 2),
    cost_override DECIMAL(10, 2),
    attributes JSONB NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, sku)
);

-- ربط المفاتيح الأجنبية لمتغيرات المنتجات في الجداول السابقة
ALTER TABLE inventory_levels ADD CONSTRAINT fk_inventory_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL;
ALTER TABLE order_items ADD CONSTRAINT fk_order_item_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL;
ALTER TABLE invoice_items ADD CONSTRAINT fk_invoice_item_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL;

-- 37. جدول تتبع الدفعات وتواريخ الصلاحية (Inventory Batches)
CREATE TABLE inventory_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    warehouse_id UUID REFERENCES warehouses(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    batch_number VARCHAR(100), -- (رقم التشغيلة / Lot Number)
    serial_number VARCHAR(100),
    expiry_date DATE,
    manufacturing_date DATE,
    quantity DECIMAL(12, 4) NOT NULL DEFAULT 0, -- (تغيّر من INT لدعم الكميات الكسرية)
    cost_per_unit DECIMAL(10, 2),
    status VARCHAR(50) DEFAULT 'available' CHECK (status IN ('available', 'expired', 'recalled', 'consumed')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, serial_number)
);

-- 38. جدول الحجوزات والمواعيد (Bookings & Appointments)
CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL, -- (العميل صاحب الحجز)
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL, -- (الموظف/مقدم الخدمة)
    product_id UUID REFERENCES products(id) ON DELETE SET NULL, -- (الخدمة المحجوزة)
    booking_type VARCHAR(50) DEFAULT 'appointment' CHECK (booking_type IN ('appointment', 'reservation', 'session')),
    title VARCHAR(255),
    start_datetime TIMESTAMPTZ NOT NULL,
    end_datetime TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
    reminder_sent BOOLEAN DEFAULT FALSE,
    notes TEXT,
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_datetime > start_datetime)
);

-- 39. جدول أجهزة نقاط البيع (POS Terminals)
CREATE TABLE pos_terminals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL, -- (مثال: "كاشير 1 - الفرع الرئيسي")
    terminal_code VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, terminal_code)
);

-- 40. جدول جلسات نقاط البيع (POS Sessions - ورديات الكاشير)
CREATE TABLE pos_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    terminal_id UUID REFERENCES pos_terminals(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- (الكاشير)
    opening_balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00, -- (العهدة الافتتاحية)
    closing_balance DECIMAL(12, 2), -- (المبلغ الفعلي في الدرج عند الإغلاق)
    expected_balance DECIMAL(12, 2), -- (المبلغ المتوقع حسب المبيعات)
    total_cash_sales DECIMAL(12, 2) DEFAULT 0.00,
    total_card_sales DECIMAL(12, 2) DEFAULT 0.00,
    total_refunds DECIMAL(12, 2) DEFAULT 0.00,
    difference DECIMAL(12, 2) DEFAULT 0.00, -- (الفرق: عجز أو زيادة)
    status VARCHAR(50) DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    opened_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMPTZ,
    notes TEXT,
    CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

-- 41. جدول العملاء المحتملين (CRM - Leads)
CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL, -- (مندوب المبيعات المسؤول)
    name VARCHAR(255) NOT NULL,
    company_name VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    source VARCHAR(100), -- (website, referral, social_media, cold_call, exhibition)
    status VARCHAR(50) DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'qualified', 'unqualified', 'converted')),
    converted_contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 42. جدول الفرص البيعية (CRM - Opportunities / Sales Pipeline)
CREATE TABLE opportunities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    lead_id UUID REFERENCES leads(id) ON DELETE SET NULL,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    stage VARCHAR(50) DEFAULT 'prospecting' CHECK (stage IN ('prospecting', 'proposal', 'negotiation', 'closed_won', 'closed_lost')),
    expected_amount DECIMAL(12, 2) DEFAULT 0.00,
    probability INT DEFAULT 0 CHECK (probability >= 0 AND probability <= 100),
    expected_close_date DATE,
    actual_close_date DATE,
    lost_reason TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 43. جدول أنشطة إدارة العلاقات (CRM - Activities)
CREATE TABLE crm_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- (من قام بالنشاط)
    lead_id UUID REFERENCES leads(id) ON DELETE CASCADE,
    opportunity_id UUID REFERENCES opportunities(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    activity_type VARCHAR(50) NOT NULL CHECK (activity_type IN ('call', 'email', 'meeting', 'note', 'whatsapp')),
    subject VARCHAR(255),
    description TEXT,
    scheduled_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'planned' CHECK (status IN ('planned', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 44. جدول اشتراكات العملاء المتكررة (Customer Subscriptions)
CREATE TABLE customer_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE CASCADE, -- (العميل المشترك)
    product_id UUID REFERENCES products(id) ON DELETE SET NULL, -- (الخدمة/المنتج المشترك فيه)
    plan_name VARCHAR(255) NOT NULL, -- (مثال: "اشتراك شهري - باقة ذهبية")
    billing_cycle VARCHAR(50) DEFAULT 'monthly' CHECK (billing_cycle IN ('weekly', 'monthly', 'quarterly', 'semi_annual', 'annual')),
    amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    start_date DATE NOT NULL,
    end_date DATE,
    next_billing_date DATE NOT NULL,
    auto_renew BOOLEAN DEFAULT TRUE,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'paused', 'cancelled', 'expired')),
    cancellation_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 45. جدول طاولات المطاعم (Dining Tables - للمطاعم والكافيهات)
CREATE TABLE dining_tables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    table_number VARCHAR(50) NOT NULL, -- (مثال: "T-01", "VIP-3")
    capacity INT DEFAULT 4, -- (عدد المقاعد)
    location_zone VARCHAR(100), -- (مثال: "outdoor", "indoor", "vip_room")
    status VARCHAR(50) DEFAULT 'available' CHECK (status IN ('available', 'occupied', 'reserved', 'maintenance')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(branch_id, table_number)
);

-- ربط الطاولات بالأوامر والفواتير
ALTER TABLE orders ADD CONSTRAINT fk_order_dining_table FOREIGN KEY (dining_table_id) REFERENCES dining_tables(id) ON DELETE SET NULL;
ALTER TABLE invoices ADD CONSTRAINT fk_invoice_dining_table FOREIGN KEY (dining_table_id) REFERENCES dining_tables(id) ON DELETE SET NULL;

-- 46. جدول مراكز العمل (Work Centers - للمصانع ومحطات التشغيل)
CREATE TABLE work_centers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL, -- (مثال: "خط التجميع 1", "محطة المطبخ الساخن")
    code VARCHAR(50), -- (رمز مختصر)
    capacity_per_hour DECIMAL(10, 2), -- (الطاقة الإنتاجية بالساعة)
    cost_per_hour DECIMAL(10, 2) DEFAULT 0.00, -- (تكلفة التشغيل بالساعة)
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, code)
);

-- ربط مراكز العمل بأوامر الإنتاج
ALTER TABLE production_orders ADD CONSTRAINT fk_production_work_center FOREIGN KEY (work_center_id) REFERENCES work_centers(id) ON DELETE SET NULL;

-- 47. جدول وحدات القياس (Units of Measure)
CREATE TABLE units_of_measure (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL, -- (مثال: "كيلوجرام", "لتر", "قطعة", "متر")
    symbol VARCHAR(20) NOT NULL, -- (مثال: "kg", "L", "pcs", "m")
    category VARCHAR(50), -- (weight, volume, length, area, unit, time)
    base_unit_id UUID REFERENCES units_of_measure(id) ON DELETE SET NULL, -- (الوحدة الأساسية للتحويل)
    conversion_factor DECIMAL(15, 6) DEFAULT 1.000000, -- (مثال: 1 كيلو = 1000 جرام، فالجرام factor = 0.001)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, symbol)
);

-- ربط وحدات القياس بالجداول السابقة
ALTER TABLE products ADD CONSTRAINT fk_product_unit FOREIGN KEY (unit_id) REFERENCES units_of_measure(id) ON DELETE SET NULL;
ALTER TABLE order_items ADD CONSTRAINT fk_order_item_unit FOREIGN KEY (unit_id) REFERENCES units_of_measure(id) ON DELETE SET NULL;
ALTER TABLE invoice_items ADD CONSTRAINT fk_invoice_item_unit FOREIGN KEY (unit_id) REFERENCES units_of_measure(id) ON DELETE SET NULL;
ALTER TABLE bill_of_materials ADD CONSTRAINT fk_bom_unit FOREIGN KEY (unit_id) REFERENCES units_of_measure(id) ON DELETE SET NULL;

-- 48. جدول قوائم الأسعار (Price Lists)
CREATE TABLE price_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL, -- (مثال: "سعر الجملة", "سعر التجزئة", "عملاء VIP")
    currency VARCHAR(10) DEFAULT 'LYD',
    type VARCHAR(50) DEFAULT 'sale' CHECK (type IN ('sale', 'purchase')),
    is_default BOOLEAN DEFAULT FALSE, -- (قائمة الأسعار الافتراضية)
    start_date DATE, -- (صلاحية القائمة من)
    end_date DATE, -- (صلاحية القائمة إلى)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 49. جدول تفاصيل قائمة الأسعار (Price List Items)
CREATE TABLE price_list_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price_list_id UUID REFERENCES price_lists(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    min_quantity DECIMAL(12, 4) DEFAULT 1 CHECK (min_quantity > 0)
);

-- فهارس جزئية لحل مشكلة UNIQUE مع القيم الفارغة في price_list_items
CREATE UNIQUE INDEX uq_price_list_no_variant
ON price_list_items(price_list_id, product_id)
WHERE variant_id IS NULL;

CREATE UNIQUE INDEX uq_price_list_with_variant
ON price_list_items(price_list_id, product_id, variant_id)
WHERE variant_id IS NOT NULL;

-- 50. جدول العروض الترويجية والخصومات (Promotions)
CREATE TABLE promotions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL, -- (مثال: "عرض رمضان", "خصم نهاية السنة")
    type VARCHAR(50) NOT NULL CHECK (type IN ('percentage', 'fixed_amount', 'buy_x_get_y', 'free_shipping')),
    value DECIMAL(10, 2), -- (مثال: 20 لخصم 20%، أو 50 لخصم 50 دينار)
    buy_quantity INT, -- (اشترِ X - لعروض buy_x_get_y)
    get_quantity INT, -- (واحصل على Y مجاناً)
    min_order_amount DECIMAL(12, 2), -- (الحد الأدنى لقيمة الطلب لتطبيق العرض)
    max_discount_amount DECIMAL(12, 2), -- (الحد الأقصى للخصم)
    applicable_products JSONB, -- (قائمة product_ids المشمولة، أو null للكل)
    applicable_categories JSONB, -- (قائمة category_ids المشمولة)
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_date >= start_date)
);

-- 51. جدول كوبونات الخصم (Coupons)
CREATE TABLE coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    promotion_id UUID REFERENCES promotions(id) ON DELETE CASCADE, -- (مربوط بعرض ترويجي)
    code VARCHAR(50) NOT NULL, -- (مثال: "SAVE10", "WELCOME20")
    max_uses INT, -- (الحد الأقصى لعدد الاستخدامات، null = غير محدود)
    used_count INT DEFAULT 0 CHECK (used_count >= 0),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (max_uses IS NULL OR max_uses > 0),
    UNIQUE(workspace_id, code)
);

-- 52. جدول تحويلات المخزون بين المخازن (Stock Transfers)
CREATE TABLE stock_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    from_warehouse_id UUID REFERENCES warehouses(id) ON DELETE CASCADE,
    to_warehouse_id UUID REFERENCES warehouses(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id),
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'pending_approval', 'approved', 'in_transit', 'received', 'cancelled')),
    reference VARCHAR(100),
    transfer_number VARCHAR(50), -- (رقم التحويل التسلسلي من document_sequences)
    notes TEXT,
    transfer_date DATE DEFAULT CURRENT_DATE,
    received_date DATE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (from_warehouse_id <> to_warehouse_id)
);

-- 53. جدول تفاصيل تحويلات المخزون (Stock Transfer Items)
CREATE TABLE stock_transfer_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id UUID REFERENCES stock_transfers(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    quantity DECIMAL(12, 4) NOT NULL,
    received_quantity DECIMAL(12, 4) DEFAULT 0, -- (الكمية المستلمة فعلياً)
    notes TEXT
);

-- 54. جدول تسلسل الأرقام التلقائي (Document Sequences)
CREATE TABLE document_sequences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN ('invoice', 'order', 'payment', 'shipment', 'production_order', 'stock_transfer')),
    prefix VARCHAR(20) DEFAULT '', -- (مثال: "INV-", "PO-")
    suffix VARCHAR(20) DEFAULT '', -- (لاحقة اختيارية)
    next_number INT NOT NULL DEFAULT 1, -- (الرقم التالي في التسلسل)
    padding INT DEFAULT 4, -- (عدد الأصفار: 4 = 0001)
    reset_period VARCHAR(20) CHECK (reset_period IS NULL OR reset_period IN ('yearly', 'monthly', 'never')),
    last_reset_date DATE, -- (تاريخ آخر إعادة تعيين)
    include_year BOOLEAN DEFAULT TRUE, -- (مثال: INV-2026-0001)
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, document_type)
);

-- 55. جدول طلبات الموافقات (Approval Requests)
CREATE TABLE approval_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL, -- (invoice, order, payment, leave, stock_transfer, production_order)
    entity_id UUID NOT NULL, -- (رقم الكيان المطلوب الموافقة عليه)
    requested_by UUID REFERENCES users(id) ON DELETE CASCADE, -- (من قدّم الطلب)
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL, -- (من المسؤول عن الموافقة)
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'escalated')),
    priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    decision_note TEXT,
    requested_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- INDEXES (الفهارس لتسريع استرجاع البيانات)
-- ==========================================

-- فهارس الجداول الأساسية
CREATE INDEX idx_products_workspace ON products(workspace_id);
CREATE INDEX idx_invoices_workspace ON invoices(workspace_id);
CREATE INDEX idx_invoices_branch ON invoices(branch_id);
CREATE INDEX idx_invoices_parent ON invoices(parent_invoice_id);
CREATE INDEX idx_users_workspace ON users(workspace_id);
CREATE INDEX idx_contacts_workspace ON contacts(workspace_id);
CREATE INDEX idx_transactions_workspace ON transactions(workspace_id);
CREATE INDEX idx_inventory_levels_warehouse ON inventory_levels(warehouse_id);
CREATE INDEX idx_shipments_workspace ON shipments(workspace_id);
CREATE INDEX idx_payroll_workspace ON payroll(workspace_id);
CREATE INDEX idx_departments_workspace ON departments(workspace_id);
CREATE INDEX idx_taxes_workspace ON taxes(workspace_id);
CREATE INDEX idx_orders_workspace ON orders(workspace_id);
CREATE INDEX idx_orders_branch ON orders(branch_id);
CREATE INDEX idx_audit_logs_workspace ON audit_logs(workspace_id);
CREATE INDEX idx_shifts_workspace ON shifts(workspace_id);
CREATE INDEX idx_fixed_assets_workspace ON fixed_assets(workspace_id);
CREATE INDEX idx_recurring_expenses_workspace ON recurring_expenses(workspace_id);
CREATE INDEX idx_bill_of_materials_workspace ON bill_of_materials(workspace_id);
CREATE INDEX idx_production_orders_workspace ON production_orders(workspace_id);
CREATE INDEX idx_projects_workspace ON projects(workspace_id);
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_workspace ON tasks(workspace_id);
CREATE INDEX idx_branches_workspace ON branches(workspace_id);
CREATE INDEX idx_roles_workspace ON roles(workspace_id);
CREATE INDEX idx_product_categories_workspace ON product_categories(workspace_id);
CREATE INDEX idx_accounts_workspace ON accounts(workspace_id);
CREATE INDEX idx_journal_entries_workspace ON journal_entries(workspace_id);
CREATE INDEX idx_payments_workspace ON payments(workspace_id);
CREATE INDEX idx_attachments_workspace ON attachments(workspace_id);
CREATE INDEX idx_notifications_workspace ON notifications(workspace_id);
CREATE INDEX idx_notifications_user ON notifications(user_id);

-- فهارس جدول متغيرات المنتجات
CREATE INDEX idx_product_variants_product ON product_variants(product_id);

-- فهارس جدول تتبع الدفعات
CREATE INDEX idx_inventory_batches_workspace ON inventory_batches(workspace_id);
CREATE INDEX idx_inventory_batches_warehouse_product ON inventory_batches(warehouse_id, product_id);
CREATE INDEX idx_inventory_batches_expiry ON inventory_batches(expiry_date);
CREATE INDEX idx_inventory_batches_batch_number ON inventory_batches(batch_number);

-- فهارس جدول الحجوزات
CREATE INDEX idx_bookings_workspace ON bookings(workspace_id);
CREATE INDEX idx_bookings_contact ON bookings(contact_id);
CREATE INDEX idx_bookings_assigned ON bookings(assigned_to);
CREATE INDEX idx_bookings_datetime ON bookings(start_datetime, end_datetime);

-- فهارس نقاط البيع
CREATE INDEX idx_pos_terminals_workspace ON pos_terminals(workspace_id);
CREATE INDEX idx_pos_terminals_branch ON pos_terminals(branch_id);
CREATE INDEX idx_pos_sessions_workspace ON pos_sessions(workspace_id);
CREATE INDEX idx_pos_sessions_terminal ON pos_sessions(terminal_id);
CREATE INDEX idx_pos_sessions_user ON pos_sessions(user_id);

-- فهارس إدارة علاقات العملاء (CRM)
CREATE INDEX idx_leads_workspace ON leads(workspace_id);
CREATE INDEX idx_leads_assigned ON leads(assigned_to);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_opportunities_workspace ON opportunities(workspace_id);
CREATE INDEX idx_opportunities_stage ON opportunities(stage);
CREATE INDEX idx_opportunities_assigned ON opportunities(assigned_to);
CREATE INDEX idx_crm_activities_workspace ON crm_activities(workspace_id);
CREATE INDEX idx_crm_activities_lead ON crm_activities(lead_id);
CREATE INDEX idx_crm_activities_opportunity ON crm_activities(opportunity_id);

-- فهارس اشتراكات العملاء
CREATE INDEX idx_customer_subscriptions_workspace ON customer_subscriptions(workspace_id);
CREATE INDEX idx_customer_subscriptions_contact ON customer_subscriptions(contact_id);
CREATE INDEX idx_customer_subscriptions_status ON customer_subscriptions(status);
CREATE INDEX idx_customer_subscriptions_next_billing ON customer_subscriptions(next_billing_date);

-- فهارس طاولات المطاعم
CREATE INDEX idx_dining_tables_workspace ON dining_tables(workspace_id);
CREATE INDEX idx_dining_tables_branch ON dining_tables(branch_id);
CREATE INDEX idx_dining_tables_status ON dining_tables(status);

-- فهارس مراكز العمل
CREATE INDEX idx_work_centers_workspace ON work_centers(workspace_id);

-- فهارس إضافية للجداول المعدلة
CREATE INDEX idx_shipments_driver ON shipments(delivery_driver_id);
CREATE INDEX idx_orders_dining_table ON orders(dining_table_id);
CREATE INDEX idx_production_orders_work_center ON production_orders(work_center_id);

-- فهارس وحدات القياس
CREATE INDEX idx_units_of_measure_workspace ON units_of_measure(workspace_id);

-- فهارس قوائم الأسعار
CREATE INDEX idx_price_lists_workspace ON price_lists(workspace_id);
CREATE INDEX idx_price_list_items_list ON price_list_items(price_list_id);
CREATE INDEX idx_price_list_items_product ON price_list_items(product_id);

-- فهارس العروض والكوبونات
CREATE INDEX idx_promotions_workspace ON promotions(workspace_id);
CREATE INDEX idx_promotions_active_dates ON promotions(start_date, end_date);
CREATE INDEX idx_coupons_workspace ON coupons(workspace_id);
CREATE INDEX idx_coupons_code ON coupons(code);

-- فهارس تحويلات المخزون
CREATE INDEX idx_stock_transfers_workspace ON stock_transfers(workspace_id);
CREATE INDEX idx_stock_transfers_from ON stock_transfers(from_warehouse_id);
CREATE INDEX idx_stock_transfers_to ON stock_transfers(to_warehouse_id);
CREATE INDEX idx_stock_transfer_items_transfer ON stock_transfer_items(transfer_id);

-- فهارس تسلسل الأرقام
CREATE INDEX idx_document_sequences_workspace ON document_sequences(workspace_id);

-- فهارس طلبات الموافقات
CREATE INDEX idx_approval_requests_workspace ON approval_requests(workspace_id);
CREATE INDEX idx_approval_requests_assigned ON approval_requests(assigned_to);
CREATE INDEX idx_approval_requests_status ON approval_requests(status);
CREATE INDEX idx_approval_requests_entity ON approval_requests(entity_type, entity_id);

-- فهارس إضافية للعلاقات المهمة
CREATE INDEX idx_payments_invoice ON payments(invoice_id);
CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_journal_lines_entry ON journal_lines(entry_id);
CREATE INDEX idx_journal_lines_account ON journal_lines(account_id);
CREATE INDEX idx_inventory_logs_product ON inventory_logs(product_id);
CREATE INDEX idx_inventory_logs_created ON inventory_logs(created_at);
CREATE INDEX idx_tasks_assigned ON tasks(assigned_to);
CREATE INDEX idx_projects_manager ON projects(manager_id);
CREATE INDEX idx_warehouses_branch ON warehouses(branch_id);

-- ==========================================
-- TRIGGERS (المشغلات التلقائية)
-- ==========================================

-- 1. دالة تحديث updated_at تلقائياً عند أي تعديل
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- تطبيق trigger تحديث updated_at على جميع الجداول التي تحتوي على هذا العمود
CREATE TRIGGER trg_workspaces_updated BEFORE UPDATE ON workspaces FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_branches_updated BEFORE UPDATE ON branches FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_roles_updated BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_contacts_updated BEFORE UPDATE ON contacts FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_taxes_updated BEFORE UPDATE ON taxes FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_product_categories_updated BEFORE UPDATE ON product_categories FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_invoices_updated BEFORE UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_payments_updated BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_fixed_assets_updated BEFORE UPDATE ON fixed_assets FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_recurring_expenses_updated BEFORE UPDATE ON recurring_expenses FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_shipments_updated BEFORE UPDATE ON shipments FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_projects_updated BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_production_orders_updated BEFORE UPDATE ON production_orders FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_product_variants_updated BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_inventory_batches_updated BEFORE UPDATE ON inventory_batches FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_bookings_updated BEFORE UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_pos_terminals_updated BEFORE UPDATE ON pos_terminals FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_leads_updated BEFORE UPDATE ON leads FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_opportunities_updated BEFORE UPDATE ON opportunities FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_customer_subscriptions_updated BEFORE UPDATE ON customer_subscriptions FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_promotions_updated BEFORE UPDATE ON promotions FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_coupons_updated BEFORE UPDATE ON coupons FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_stock_transfers_updated BEFORE UPDATE ON stock_transfers FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_document_sequences_updated BEFORE UPDATE ON document_sequences FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_approval_requests_updated BEFORE UPDATE ON approval_requests FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- 2. دالة التحقق من توازن القيد المحاسبي (مجموع المدين = مجموع الدائن)
CREATE OR REPLACE FUNCTION check_journal_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_entry_id UUID;
    total_debit DECIMAL(15, 2);
    total_credit DECIMAL(15, 2);
BEGIN
    -- استخدام COALESCE للتعامل مع DELETE حيث NEW غير موجود
    v_entry_id := COALESCE(NEW.entry_id, OLD.entry_id);

    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO total_debit, total_credit
    FROM journal_lines
    WHERE entry_id = v_entry_id;

    IF total_debit <> total_credit THEN
        RAISE EXCEPTION 'القيد المحاسبي غير متوازن: المدين (%) لا يساوي الدائن (%)', total_debit, total_credit;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- تطبيق trigger التوازن المحاسبي
CREATE CONSTRAINT TRIGGER trg_check_journal_balance
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_journal_balance();

-- ==========================================
-- CROSS-WORKSPACE INTEGRITY (Tenant Isolation)
-- ==========================================

-- 1. إضافة UNIQUE(workspace_id, id) لكل الجداول الأب لتمكين composite FK referencing
ALTER TABLE branches ADD CONSTRAINT uq_branches_ws_id UNIQUE (workspace_id, id);
ALTER TABLE departments ADD CONSTRAINT uq_departments_ws_id UNIQUE (workspace_id, id);
ALTER TABLE shifts ADD CONSTRAINT uq_shifts_ws_id UNIQUE (workspace_id, id);
ALTER TABLE roles ADD CONSTRAINT uq_roles_ws_id UNIQUE (workspace_id, id);
ALTER TABLE users ADD CONSTRAINT uq_users_ws_id UNIQUE (workspace_id, id);
ALTER TABLE contacts ADD CONSTRAINT uq_contacts_ws_id UNIQUE (workspace_id, id);
ALTER TABLE taxes ADD CONSTRAINT uq_taxes_ws_id UNIQUE (workspace_id, id);
ALTER TABLE product_categories ADD CONSTRAINT uq_categories_ws_id UNIQUE (workspace_id, id);
ALTER TABLE products ADD CONSTRAINT uq_products_ws_id UNIQUE (workspace_id, id);
ALTER TABLE warehouses ADD CONSTRAINT uq_warehouses_ws_id UNIQUE (workspace_id, id);
ALTER TABLE orders ADD CONSTRAINT uq_orders_ws_id UNIQUE (workspace_id, id);
ALTER TABLE invoices ADD CONSTRAINT uq_invoices_ws_id UNIQUE (workspace_id, id);
ALTER TABLE accounts ADD CONSTRAINT uq_accounts_ws_id UNIQUE (workspace_id, id);
ALTER TABLE journal_entries ADD CONSTRAINT uq_journal_entries_ws_id UNIQUE (workspace_id, id);
ALTER TABLE projects ADD CONSTRAINT uq_projects_ws_id UNIQUE (workspace_id, id);
ALTER TABLE leads ADD CONSTRAINT uq_leads_ws_id UNIQUE (workspace_id, id);
ALTER TABLE opportunities ADD CONSTRAINT uq_opportunities_ws_id UNIQUE (workspace_id, id);
ALTER TABLE promotions ADD CONSTRAINT uq_promotions_ws_id UNIQUE (workspace_id, id);
ALTER TABLE price_lists ADD CONSTRAINT uq_price_lists_ws_id UNIQUE (workspace_id, id);
ALTER TABLE pos_terminals ADD CONSTRAINT uq_pos_terminals_ws_id UNIQUE (workspace_id, id);
ALTER TABLE work_centers ADD CONSTRAINT uq_work_centers_ws_id UNIQUE (workspace_id, id);
ALTER TABLE units_of_measure ADD CONSTRAINT uq_units_ws_id UNIQUE (workspace_id, id);
ALTER TABLE dining_tables ADD CONSTRAINT uq_dining_tables_ws_id UNIQUE (workspace_id, id);
ALTER TABLE stock_transfers ADD CONSTRAINT uq_stock_transfers_ws_id UNIQUE (workspace_id, id);

-- 2. دالة التحقق من عزل الـ workspace (تمنع ربط سجلات من workspaces مختلفة)
CREATE OR REPLACE FUNCTION validate_workspace_fk()
RETURNS TRIGGER AS $$
DECLARE
    ref_ws UUID;
    col_name TEXT;
    ref_table TEXT;
    fk_value UUID;
    query TEXT;
BEGIN
    -- يقرأ الأعمدة المطلوب التحقق منها من TG_ARGV
    -- TG_ARGV[0] = 'column1:table1,column2:table2,...'
    FOR col_name, ref_table IN
        SELECT split_part(pair, ':', 1), split_part(pair, ':', 2)
        FROM unnest(string_to_array(TG_ARGV[0], ',')) AS pair
    LOOP
        EXECUTE format('SELECT ($1).%I', col_name) INTO fk_value USING NEW;
        IF fk_value IS NOT NULL THEN
            EXECUTE format('SELECT workspace_id FROM %I WHERE id = $1', ref_table) INTO ref_ws USING fk_value;
            IF ref_ws IS DISTINCT FROM NEW.workspace_id THEN
                RAISE EXCEPTION 'خرق عزل الـ workspace: %.% يشير إلى سجل في workspace مختلف (% بدل %)',
                    TG_TABLE_NAME, col_name, ref_ws, NEW.workspace_id;
            END IF;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. تطبيق triggers التحقق من عزل الـ workspace على الجداول الأساسية
-- كل trigger يتحقق أن الأعمدة FK تشير لسجلات في نفس الـ workspace

CREATE TRIGGER trg_users_ws_check BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches,department_id:departments,shift_id:shifts,role_id:roles,manager_id:users');

CREATE TRIGGER trg_products_ws_check BEFORE INSERT OR UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('category_id:product_categories,tax_id:taxes');

CREATE TRIGGER trg_warehouses_ws_check BEFORE INSERT OR UPDATE ON warehouses
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches');

CREATE TRIGGER trg_orders_ws_check BEFORE INSERT OR UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches,created_by:users,contact_id:contacts');

CREATE TRIGGER trg_invoices_ws_check BEFORE INSERT OR UPDATE ON invoices
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches,created_by:users,contact_id:contacts,order_id:orders');

CREATE TRIGGER trg_payments_ws_check BEFORE INSERT OR UPDATE ON payments
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('invoice_id:invoices,account_id:accounts,created_by:users');

CREATE TRIGGER trg_transactions_ws_check BEFORE INSERT OR UPDATE ON transactions
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('contact_id:contacts,account_id:accounts,from_account_id:accounts,to_account_id:accounts,created_by:users');

CREATE TRIGGER trg_shipments_ws_check BEFORE INSERT OR UPDATE ON shipments
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('invoice_id:invoices,contact_id:contacts,delivery_driver_id:users');

CREATE TRIGGER trg_projects_ws_check BEFORE INSERT OR UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('contact_id:contacts,manager_id:users');

CREATE TRIGGER trg_tasks_ws_check BEFORE INSERT OR UPDATE ON tasks
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('project_id:projects,assigned_to:users');

CREATE TRIGGER trg_production_orders_ws_check BEFORE INSERT OR UPDATE ON production_orders
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('created_by:users,product_id:products,warehouse_id:warehouses,work_center_id:work_centers');

CREATE TRIGGER trg_bookings_ws_check BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches,contact_id:contacts,assigned_to:users,product_id:products,invoice_id:invoices');

CREATE TRIGGER trg_pos_terminals_ws_check BEFORE INSERT OR UPDATE ON pos_terminals
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches');

CREATE TRIGGER trg_pos_sessions_ws_check BEFORE INSERT OR UPDATE ON pos_sessions
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('terminal_id:pos_terminals,user_id:users');

CREATE TRIGGER trg_leads_ws_check BEFORE INSERT OR UPDATE ON leads
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('assigned_to:users,converted_contact_id:contacts');

CREATE TRIGGER trg_opportunities_ws_check BEFORE INSERT OR UPDATE ON opportunities
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('lead_id:leads,contact_id:contacts,assigned_to:users');

CREATE TRIGGER trg_crm_activities_ws_check BEFORE INSERT OR UPDATE ON crm_activities
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users,lead_id:leads,opportunity_id:opportunities,contact_id:contacts');

CREATE TRIGGER trg_subscriptions_ws_check BEFORE INSERT OR UPDATE ON customer_subscriptions
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('contact_id:contacts,product_id:products');

CREATE TRIGGER trg_inventory_logs_ws_check BEFORE INSERT OR UPDATE ON inventory_logs
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('warehouse_id:warehouses,product_id:products,user_id:users');

CREATE TRIGGER trg_stock_transfers_ws_check BEFORE INSERT OR UPDATE ON stock_transfers
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('from_warehouse_id:warehouses,to_warehouse_id:warehouses,created_by:users,approved_by:users');

CREATE TRIGGER trg_approval_requests_ws_check BEFORE INSERT OR UPDATE ON approval_requests
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('requested_by:users,assigned_to:users');

CREATE TRIGGER trg_attendance_ws_check BEFORE INSERT OR UPDATE ON attendance
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users');

CREATE TRIGGER trg_leaves_ws_check BEFORE INSERT OR UPDATE ON leaves
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users');

CREATE TRIGGER trg_payroll_ws_check BEFORE INSERT OR UPDATE ON payroll
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users');

CREATE TRIGGER trg_coupons_ws_check BEFORE INSERT OR UPDATE ON coupons
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('promotion_id:promotions');

CREATE TRIGGER trg_dining_tables_ws_check BEFORE INSERT OR UPDATE ON dining_tables
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('branch_id:branches');

CREATE TRIGGER trg_batches_ws_check BEFORE INSERT OR UPDATE ON inventory_batches
FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('warehouse_id:warehouses,product_id:products');

-- ==========================================
-- ROW LEVEL SECURITY (العزل التام للبيانات)
-- ==========================================

-- تفعيل RLS على جميع الجداول المرتبطة بـ workspace
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE taxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixed_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE leaves ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_of_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_terminals ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE dining_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE units_of_measure ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY;

-- سياسات RLS: كل مستخدم يرى فقط بيانات الـ workspace الخاص به
-- التطبيق يضبط: SET app.workspace_id = 'uuid-here' عند كل اتصال
CREATE POLICY ws_branches ON branches USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_departments ON departments USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_shifts ON shifts USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_roles ON roles USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_users ON users USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_contacts ON contacts USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_taxes ON taxes USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_categories ON product_categories USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_products ON products USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_warehouses ON warehouses USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_inv_logs ON inventory_logs USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_orders ON orders USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_invoices ON invoices USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_accounts ON accounts USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_journal ON journal_entries USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_payments ON payments USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_transactions ON transactions USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_assets ON fixed_assets USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_recurring ON recurring_expenses USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_attendance ON attendance USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_leaves ON leaves USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_payroll ON payroll USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_shipments ON shipments USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_audit ON audit_logs USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_projects ON projects USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_tasks ON tasks USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_bom ON bill_of_materials USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_production ON production_orders USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_attachments ON attachments USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_notifications ON notifications USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_batches ON inventory_batches USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_bookings ON bookings USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_pos_terminals ON pos_terminals USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_pos_sessions ON pos_sessions USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_leads ON leads USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_opportunities ON opportunities USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_crm ON crm_activities USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_subscriptions ON customer_subscriptions USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_tables ON dining_tables USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_work_centers ON work_centers USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_units ON units_of_measure USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_price_lists ON price_lists USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_promotions ON promotions USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_coupons ON coupons USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_transfers ON stock_transfers USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_sequences ON document_sequences USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);
CREATE POLICY ws_approvals ON approval_requests USING (workspace_id = current_setting('app.workspace_id', true)::UUID) WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- ==========================================
-- PLATFORM ADMIN TABLES (Global — Not Workspace-Scoped)
-- ==========================================

-- P1. مستخدمو المنصة (فريق SmartBiz AI)
CREATE TABLE platform_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('platform_owner', 'platform_admin', 'platform_support', 'platform_operations')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- P2. طلبات الميزات المجمعة (Feature Requests)
CREATE TABLE platform_feature_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    normalized_key VARCHAR(255) NOT NULL UNIQUE, -- مفتاح موحد للتجميع
    category VARCHAR(100), -- (module, page, workflow, integration, etc.)
    description TEXT,
    status VARCHAR(50) DEFAULT 'new' CHECK (status IN ('new', 'under_review', 'planned', 'in_progress', 'released', 'rejected', 'duplicate')),
    priority VARCHAR(50) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    request_count INT DEFAULT 1 CHECK (request_count >= 0),
    workspace_count INT DEFAULT 1 CHECK (workspace_count >= 0),
    platform_note TEXT,
    first_requested_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, -- أول طلب
    last_requested_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, -- آخر طلب
    released_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- P3. أصوات طلبات الميزات (ربط المستخدمين/الشركات بالطلبات)
CREATE TABLE platform_feature_request_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_request_id UUID NOT NULL REFERENCES platform_feature_requests(id) ON DELETE CASCADE,
    workspace_id UUID, -- مرجع وليس FK (قد يُحذف الـ workspace)
    user_id UUID, -- مرجع وليس FK
    source_type VARCHAR(50) NOT NULL CHECK (source_type IN ('ai_unsupported', 'user_submission', 'support_submission', 'internal')),
    request_text TEXT, -- النص الأصلي للطلب
    industry_type VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(feature_request_id, workspace_id, user_id)
);

-- P4. البث العام (Broadcasts)
CREATE TABLE platform_broadcasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'info' CHECK (type IN ('info', 'release', 'warning', 'maintenance', 'survey', 'product_tip')),
    audience_definition JSONB NOT NULL DEFAULT '{"target": "all"}', -- {"target":"all"} أو {"industries":["retail"]} أو {"workspace_ids":["..."]}
    delivery_channels JSONB DEFAULT '["in_app"]', -- ["in_app", "push", "email"]
    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'sending', 'sent', 'cancelled', 'archived')),
    scheduled_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    targeted_count INT DEFAULT 0,
    delivered_count INT DEFAULT 0,
    opened_count INT DEFAULT 0,
    created_by UUID REFERENCES platform_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- P5. الاستبيانات (Surveys)
CREATE TABLE platform_surveys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    audience_definition JSONB NOT NULL DEFAULT '{"target": "all"}',
    questions JSONB NOT NULL, -- [{type, text, options?, required?}, ...]
    status VARCHAR(50) DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'active', 'closed', 'archived')),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    invites_sent INT DEFAULT 0,
    responses_received INT DEFAULT 0,
    created_by UUID REFERENCES platform_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

-- P6. إجابات الاستبيانات
CREATE TABLE platform_survey_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    survey_id UUID NOT NULL REFERENCES platform_surveys(id) ON DELETE CASCADE,
    workspace_id UUID, -- مرجع وليس FK
    user_id UUID, -- مرجع وليس FK
    answers JSONB NOT NULL, -- [{question_index, answer}, ...]
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(survey_id, workspace_id, user_id)
);

-- P7. أحداث المنصة العامة (Platform Events / Telemetry)
CREATE TABLE platform_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(100) NOT NULL, -- workspace_created, ai_change_requested, sync_failed, etc.
    severity VARCHAR(50) DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'error', 'critical')),
    workspace_id UUID, -- مرجع (قد يكون NULL لأحداث عامة)
    user_id UUID,
    actor_type VARCHAR(50) CHECK (actor_type IN ('user', 'system', 'ai', 'platform_admin')),
    entity_type VARCHAR(100), -- invoice, payment, workspace, etc.
    entity_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- P8. سجل طلبات الذكاء الاصطناعي
CREATE TABLE ai_request_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID, -- مرجع وليس FK
    user_id UUID,
    request_type VARCHAR(50) NOT NULL CHECK (request_type IN ('onboarding', 'change_request', 'advisory', 'analytics', 'unsupported')),
    ai_model VARCHAR(100), -- (اسم النموذج: gpt-4o, claude-3.5, etc.)
    request_text TEXT,
    response_text TEXT,
    structured_output JSONB, -- الناتج المهيكل إن وُجد
    tokens_used INT DEFAULT 0 CHECK (tokens_used >= 0), -- إجمالي التوكنز
    prompt_tokens INT DEFAULT 0 CHECK (prompt_tokens >= 0), -- توكنز الإدخال
    completion_tokens INT DEFAULT 0 CHECK (completion_tokens >= 0), -- توكنز الاستجابة
    latency_ms INT, -- زمن الاستجابة بالميلي ثانية
    status VARCHAR(50) DEFAULT 'success' CHECK (status IN ('success', 'failed', 'rejected', 'timeout')),
    error_message TEXT,
    feature_request_id UUID REFERENCES platform_feature_requests(id) ON DELETE SET NULL, -- ربط بطلب ميزة إن كان unsupported
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- PLATFORM INDEXES
-- ==========================================

CREATE INDEX idx_feature_requests_status ON platform_feature_requests(status);
CREATE INDEX idx_feature_requests_category ON platform_feature_requests(category);
CREATE INDEX idx_feature_requests_normalized ON platform_feature_requests(normalized_key);
CREATE INDEX idx_feature_votes_request ON platform_feature_request_votes(feature_request_id);
CREATE INDEX idx_feature_votes_workspace ON platform_feature_request_votes(workspace_id);
CREATE INDEX idx_broadcasts_status ON platform_broadcasts(status);
CREATE INDEX idx_broadcasts_type ON platform_broadcasts(type);
CREATE INDEX idx_broadcasts_scheduled ON platform_broadcasts(scheduled_at) WHERE status = 'scheduled';
CREATE INDEX idx_surveys_status ON platform_surveys(status);
CREATE INDEX idx_survey_responses_survey ON platform_survey_responses(survey_id);
CREATE INDEX idx_events_type ON platform_events(event_type);
CREATE INDEX idx_events_severity ON platform_events(severity);
CREATE INDEX idx_events_workspace ON platform_events(workspace_id);
CREATE INDEX idx_events_created ON platform_events(created_at);
CREATE INDEX idx_ai_logs_workspace ON ai_request_logs(workspace_id);
CREATE INDEX idx_ai_logs_type ON ai_request_logs(request_type);
CREATE INDEX idx_ai_logs_created ON ai_request_logs(created_at);
CREATE INDEX idx_ai_logs_status ON ai_request_logs(status);
CREATE INDEX idx_ai_logs_feature_req ON ai_request_logs(feature_request_id) WHERE feature_request_id IS NOT NULL;
CREATE INDEX idx_feature_requests_priority ON platform_feature_requests(priority);
CREATE INDEX idx_ai_logs_model ON ai_request_logs(ai_model);

-- Platform updated_at triggers
CREATE TRIGGER trg_platform_users_updated BEFORE UPDATE ON platform_users FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_feature_requests_updated BEFORE UPDATE ON platform_feature_requests FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_broadcasts_updated BEFORE UPDATE ON platform_broadcasts FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_surveys_updated BEFORE UPDATE ON platform_surveys FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- ==========================================
-- PLATFORM RLS (عزل حسب دور المنصة)
-- ==========================================
-- ملاحظة: جداول المنصة لا تستخدم workspace_id للعزل
-- بدلاً من ذلك، الوصول يُحدد بدور المنصة (platform_owner, platform_admin, etc.)
-- التحقق يتم على مستوى التطبيق عبر middleware منفصل عن workspace middleware
