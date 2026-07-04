// SmartBiz AI — Point of Sale screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../products/products_state.dart';
import '../../products/models/product_models.dart';

/// A single item in the POS cart.
class _CartItem {
  final Product product;
  int quantity;
  _CartItem(this.product) : quantity = 1;
  double get total => product.sellingPrice * quantity;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<_CartItem> _cart = [];
  final _searchCtrl = TextEditingController();
  String _search = '';
  int _paymentMethod = 0; // 0=Cash, 1=Card, 2=Transfer

  double get _subtotal => _cart.fold(0.0, (s, i) => s + i.total);
  double get _tax => _subtotal * 0.05;
  double get _grandTotal => _subtotal + _tax;
  int get _itemCount => _cart.fold(0, (s, i) => s + i.quantity);

  void _addToCart(Product product) {
    final existing = _cart.where((c) => c.product.id == product.id).toList();
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.quantity++;
      } else {
        _cart.add(_CartItem(product));
      }
    });
  }

  void _updateQty(_CartItem item, int delta) {
    setState(() {
      item.quantity += delta;
      if (item.quantity <= 0) _cart.remove(item);
    });
  }

  void _removeItem(_CartItem item) => setState(() => _cart.remove(item));

  void _clearCart() => setState(() => _cart.clear());

  void _checkout() {
    if (_cart.isEmpty) return;
    final method = [tr(context, 'pos_cash'), tr(context, 'pos_card'), tr(context, 'pos_transfer')][_paymentMethod];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${tr(context, 'pos_checkout_demo')} · $method · \$${_grandTotal.toStringAsFixed(2)}'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.success,
    ));
    _clearCart();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return isMobile ? _buildMobileLayout() : _buildDesktopLayout();
  }

  // ═══════════════════════════════════════════════════════════
  //  Desktop: products left, cart right
  // ═══════════════════════════════════════════════════════════

  Widget _buildDesktopLayout() => Row(
    children: [
      Expanded(flex: 3, child: _buildProductPanel()),
      Container(width: 1, color: AppColors.divider),
      SizedBox(width: 360, child: _buildCartPanel()),
    ],
  );

  // ═══════════════════════════════════════════════════════════
  //  Mobile: stacked with bottom sheet cart
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobileLayout() => Column(
    children: [
      Expanded(child: _buildProductPanel()),
      // Cart summary bar
      if (_cart.isNotEmpty) _buildMobileCartBar(),
    ],
  );

  Widget _buildMobileCartBar() => GestureDetector(
    onTap: () => _showMobileCart(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Text('$_itemCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(tr(context, 'pos_view_cart'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          Text('\$${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    ),
  );

  void _showMobileCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) => _buildCartPanel(scrollCtrl: scrollCtrl, onChanged: () => setBS(() {})),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Product Panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildProductPanel() {
    final products = context.watch<ProductsState>().all
        .where((p) => p.status == ProductStatus.active)
        .where((p) {
          if (_search.isEmpty) return true;
          final q = _search.toLowerCase();
          return p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q);
        })
        .toList();

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'pos_title'), style: AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                textDirection: Directionality.of(context),
                decoration: InputDecoration(
                  hintText: tr(context, 'pos_search'),
                  hintTextDirection: Directionality.of(context),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        // Product grid
        Expanded(
          child: products.isEmpty
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.neutral300),
                    const SizedBox(height: AppSpacing.sm),
                    Text(tr(context, 'pos_no_products'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  ],
                ))
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, i) => _ProductTile(
                    product: products[i],
                    onTap: () => _addToCart(products[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Cart Panel
  // ═══════════════════════════════════════════════════════════

  Widget _buildCartPanel({ScrollController? scrollCtrl, VoidCallback? onChanged}) {
    void refresh() { setState(() {}); onChanged?.call(); }

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Cart header
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(tr(context, 'pos_cart'), style: AppTypography.headingSmall),
                const Spacer(),
                if (_cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () { _clearCart(); onChanged?.call(); },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(tr(context, 'pos_clear')),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error, textStyle: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Cart items
          Expanded(
            child: _cart.isEmpty
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 48, color: AppColors.neutral300),
                      const SizedBox(height: AppSpacing.sm),
                      Text(tr(context, 'pos_cart_empty'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(tr(context, 'pos_cart_hint'), style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
                    ],
                  ))
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: _cart.length,
                    itemBuilder: (_, i) => _CartRow(
                      item: _cart[i],
                      onIncrease: () { _updateQty(_cart[i], 1); refresh(); },
                      onDecrease: () { _updateQty(_cart[i], -1); refresh(); },
                      onRemove: () { _removeItem(_cart[i]); refresh(); },
                    ),
                  ),
          ),

          // Totals + checkout
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(top: BorderSide(color: AppColors.divider)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Column(
              children: [
                _TotalRow(label: tr(context, 'pos_subtotal'), value: '\$${_subtotal.toStringAsFixed(2)}'),
                const SizedBox(height: 4),
                _TotalRow(label: '${tr(context, 'pos_tax')} (5%)', value: '\$${_tax.toStringAsFixed(2)}', muted: true),
                const Divider(height: AppSpacing.base),
                _TotalRow(label: tr(context, 'pos_total'), value: '\$${_grandTotal.toStringAsFixed(2)}', bold: true),
                const SizedBox(height: AppSpacing.md),

                // Payment method selector
                Row(
                  children: List.generate(3, (i) {
                    final labels = [tr(context, 'pos_cash'), tr(context, 'pos_card'), tr(context, 'pos_transfer')];
                    final icons = [Icons.money, Icons.credit_card, Icons.swap_horiz];
                    final selected = _paymentMethod == i;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(end: i < 2 ? AppSpacing.xs : 0),
                        child: OutlinedButton.icon(
                          onPressed: () { setState(() => _paymentMethod = i); onChanged?.call(); },
                          icon: Icon(icons[i], size: 16),
                          label: FittedBox(child: Text(labels[i])),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: selected ? AppColors.primary : AppColors.neutral500,
                            backgroundColor: selected ? AppColors.primarySurface : Colors.transparent,
                            side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            textStyle: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.md),

                // Checkout button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _cart.isEmpty ? null : _checkout,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(tr(context, 'pos_checkout')),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.success,
                      disabledBackgroundColor: AppColors.neutral200,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Product Tile
// ═══════════════════════════════════════════════════════════

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stockLevel == StockLevel.outOfStock;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: outOfStock ? AppColors.neutral200 : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2_outlined, size: 22,
                    color: outOfStock ? AppColors.neutral400 : AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(product.name, style: AppTypography.labelMedium, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('\$${product.sellingPrice.toStringAsFixed(2)}',
                  style: AppTypography.labelLarge.copyWith(color: outOfStock ? AppColors.neutral400 : AppColors.primary)),
              if (outOfStock)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr(context, 'pos_out_of_stock'),
                      style: TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Cart Row
// ═══════════════════════════════════════════════════════════

class _CartRow extends StatelessWidget {
  final _CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  const _CartRow({required this.item, required this.onIncrease, required this.onDecrease, required this.onRemove});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
    child: Row(
      children: [
        // Product info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.product.name, style: AppTypography.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('\$${item.product.sellingPrice.toStringAsFixed(2)}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        // Qty controls
        Container(
          decoration: BoxDecoration(
            color: AppColors.neutral100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QtyBtn(icon: Icons.remove, onTap: onDecrease),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.quantity}', style: AppTypography.labelMedium),
              ),
              _QtyBtn(icon: Icons.add, onTap: onIncrease),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Line total
        SizedBox(
          width: 60,
          child: Text('\$${item.total.toStringAsFixed(2)}', style: AppTypography.labelMedium, textAlign: TextAlign.end),
        ),
        // Remove
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: onRemove,
          color: AppColors.error,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          splashRadius: 14,
        ),
      ],
    ),
  );
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, size: 14, color: AppColors.neutral600),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Total Row
// ═══════════════════════════════════════════════════════════

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool muted;
  const _TotalRow({required this.label, required this.value, this.bold = false, this.muted = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: bold
          ? AppTypography.labelLarge
          : AppTypography.bodySmall.copyWith(color: muted ? AppColors.textTertiary : AppColors.textSecondary)),
      Text(value, style: bold
          ? AppTypography.headingSmall.copyWith(color: AppColors.primary)
          : AppTypography.labelMedium.copyWith(color: muted ? AppColors.textTertiary : null)),
    ],
  );
}
