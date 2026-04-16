# Backend Data Access Rules — Child Table Isolation

## Rule

**Child tables that lack a `workspace_id` column MUST NEVER be queried directly.**

These tables have no Row-Level Security (RLS) policies. They rely entirely on their parent table's RLS for tenant isolation. Every query against a child table **must** join through the parent that owns `workspace_id`.

Violating this rule **will leak data across tenants**.

## Affected Child Tables

| Child Table | Parent Table | Parent FK Column |
|---|---|---|
| `invoice_items` | `invoices` | `invoice_id` |
| `order_items` | `orders` | `order_id` |
| `journal_lines` | `journal_entries` | `entry_id` |
| `price_list_items` | `price_lists` | `price_list_id` |
| `stock_transfer_items` | `stock_transfers` | `transfer_id` |
| `product_variants` | `products` | `product_id` |
| `campaign_metrics` | `campaigns` | `campaign_id` |
| `segment_contacts` | `segments` | `segment_id` |
| `nurturing_enrollments` | `nurturing_sequences` | `sequence_id` |
| `delivery_proofs` | `delivery_assignments` | `assignment_id` |
| `delivery_sla_breaches` | `delivery_assignments` | `assignment_id` |
| `delivery_tracking` | `delivery_assignments` | `assignment_id` |
| `loyalty_transactions` | `loyalty_accounts` | `account_id` |
| `webhook_deliveries` | `webhook_subscriptions` | `subscription_id` |

## ❌ Wrong — Direct child query (cross-tenant data leak)

```sql
SELECT * FROM invoice_items WHERE product_id = '...';
```

This returns rows from **all workspaces** because `invoice_items` has no RLS.

## ✅ Correct — Join through parent

```sql
SELECT ii.*
FROM invoice_items ii
JOIN invoices i ON ii.invoice_id = i.id
WHERE i.workspace_id = current_setting('app.workspace_id', true)::UUID
  AND ii.product_id = '...';
```

The parent table `invoices` has RLS enforcing workspace isolation. Joining through it ensures only the current tenant's data is returned.

This rule applies even when the child table has useful filters or indexes.
Workspace isolation must always come from the parent path.
