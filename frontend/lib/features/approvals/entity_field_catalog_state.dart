// SmartBiz AI — Entity Field Catalog state management.
//
// Manages fetching and caching of:
//   1. Entity type list (from GET /api/approval-entity-types)
//   2. Per-entity field schemas (from GET /api/approval-entity-field-catalog)
//
// Safety guarantees:
//   - Cache keys include workspace ID.
//   - clearData() must be called on logout / workspace switch.
//   - Late responses from old workspace are discarded.
//   - Duplicate in-flight requests are collapsed.
import 'package:flutter/foundation.dart';
import '../../core/api/approval_service.dart';
import '../../core/api/entity_field_catalog_models.dart';

class EntityFieldCatalogState extends ChangeNotifier {
  final ApprovalService _svc;
  EntityFieldCatalogState(this._svc);

  /// Current workspace ID — set by the screen before loading.
  /// Used to scope cache and detect stale responses.
  String? _workspaceId;

  /// Set the active workspace. If different from current, clears cache.
  void setWorkspace(String workspaceId) {
    if (_workspaceId == workspaceId) return;
    // Workspace changed — invalidate all cached data.
    _workspaceId = workspaceId;
    _entityTypes = null;
    _entityTypesLoading = false;
    _entityTypesError = null;
    _entityTypesInFlight = null;
    _schemaCache.clear();
    _schemaLoading.clear();
    _schemaErrors.clear();
    _inFlight.clear();
    notifyListeners();
  }

  // ── Entity Type List ───────────────────────────────────

  /// Cached entity type descriptors for the current workspace.
  List<ApprovalEntityTypeDescriptor>? _entityTypes;

  /// Whether entity types are currently loading.
  bool _entityTypesLoading = false;

  /// Error message from the last entity type load attempt.
  String? _entityTypesError;

  /// In-flight request to avoid duplicates.
  Future<List<ApprovalEntityTypeDescriptor>>? _entityTypesInFlight;

  /// Get the cached entity type list. Returns null if not loaded.
  List<ApprovalEntityTypeDescriptor>? get entityTypes => _entityTypes;

  /// Whether entity types are currently loading.
  bool get entityTypesLoading => _entityTypesLoading;

  /// Error from the last entity type load attempt.
  String? get entityTypesError => _entityTypesError;

  /// Look up an entity type descriptor by key. Returns null if not found.
  ApprovalEntityTypeDescriptor? descriptorFor(String entityType) {
    if (_entityTypes == null) return null;
    for (final d in _entityTypes!) {
      if (d.entityType == entityType) return d;
    }
    return null;
  }

  /// Load the entity type list from the backend.
  /// Caches the result by workspace. Set [forceReload] to bypass cache.
  /// Collapses duplicate in-flight requests.
  /// Discards late responses from a different workspace.
  Future<List<ApprovalEntityTypeDescriptor>?> loadEntityTypes({
    bool forceReload = false,
  }) async {
    final capturedWorkspace = _workspaceId;

    // Return cached if available.
    if (!forceReload && _entityTypes != null) {
      return _entityTypes;
    }

    // Collapse duplicate in-flight requests.
    if (_entityTypesInFlight != null) {
      return _entityTypesInFlight;
    }

    _entityTypesLoading = true;
    _entityTypesError = null;
    notifyListeners();

    final future = _svc.listEntityTypes();
    _entityTypesInFlight = future;

    try {
      final result = await future;
      _entityTypesInFlight = null;

      // Discard if workspace changed while loading.
      if (_workspaceId != capturedWorkspace) return null;

      _entityTypes = result;
      _entityTypesLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _entityTypesInFlight = null;

      // Discard if workspace changed while loading.
      if (_workspaceId != capturedWorkspace) return null;

      _entityTypesError = e.toString();
      _entityTypesLoading = false;
      notifyListeners();
      return null;
    }
  }

  // ── Per-Entity Field Schemas ────────────────────────────

  /// Cached field schemas keyed by `workspaceId:entityType`.
  final Map<String, EntityFieldSchema> _schemaCache = {};

  /// Per-entity loading state.
  final Map<String, bool> _schemaLoading = {};

  /// Per-entity error state.
  final Map<String, String?> _schemaErrors = {};

  /// In-flight requests to avoid duplicates.
  final Map<String, Future<EntityFieldSchema?>> _inFlight = {};

  /// Cache key combining workspace and entity type.
  String _cacheKey(String entityType) => '${_workspaceId ?? '_'}:$entityType';

  /// Get cached field schema for an entity type. Returns null if not loaded.
  EntityFieldSchema? schemaFor(String entityType) =>
      _schemaCache[_cacheKey(entityType)];

  /// Whether a specific entity type's schema is currently loading.
  bool isSchemaLoading(String entityType) =>
      _schemaLoading[_cacheKey(entityType)] ?? false;

  /// Error message for a specific entity type's schema load.
  String? schemaError(String entityType) =>
      _schemaErrors[_cacheKey(entityType)];

  /// Load the field schema for a specific entity type.
  /// Caches the result to avoid redundant requests.
  /// Collapses duplicate in-flight requests.
  /// Discards late responses from a different workspace.
  ///
  /// Set [forceReload] to true to bypass cache.
  /// Returns the schema on success, null on failure.
  Future<EntityFieldSchema?> loadSchema(
    String entityType, {
    bool forceReload = false,
  }) async {
    final key = _cacheKey(entityType);
    final capturedWorkspace = _workspaceId;

    // Return cached version if not forcing reload.
    if (!forceReload && _schemaCache.containsKey(key)) {
      return _schemaCache[key];
    }

    // Collapse duplicate in-flight requests.
    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    _schemaLoading[key] = true;
    _schemaErrors[key] = null;
    notifyListeners();

    final future = _svc.getEntityFieldSchema(entityType);
    _inFlight[key] = future;

    try {
      final schema = await future;
      _inFlight.remove(key);

      // Discard if workspace changed while we were loading.
      if (_workspaceId != capturedWorkspace) return null;

      if (schema != null) {
        _schemaCache[key] = schema;
      }
      _schemaLoading[key] = false;
      notifyListeners();
      return schema;
    } catch (e) {
      _inFlight.remove(key);

      // Discard if workspace changed while we were loading.
      if (_workspaceId != capturedWorkspace) return null;

      _schemaErrors[key] = e.toString();
      _schemaLoading[key] = false;
      notifyListeners();
      return null;
    }
  }

  // ── Cache Management ───────────────────────────────────

  /// Clear all cached data (call on logout / workspace switch).
  /// Prevents stale tenant data from leaking across sessions.
  void clearData() {
    _workspaceId = null;
    _entityTypes = null;
    _entityTypesLoading = false;
    _entityTypesError = null;
    _entityTypesInFlight = null;
    _schemaCache.clear();
    _schemaLoading.clear();
    _schemaErrors.clear();
    _inFlight.clear();
    notifyListeners();
  }

  // ── Coordinated Metadata Preload ─────────────────────

  /// Preload entity-type descriptors and field schemas for all entity
  /// types referenced by [workflows].  Deduplicates entity types, skips
  /// empty values, and reuses existing in-flight / cached data.
  ///
  /// Call this whenever a new workflow list becomes available.
  Future<void> loadMetadataForWorkflows(List<dynamic> workflows) async {
    // Ensure entity type list is loaded first.
    await loadEntityTypes();

    // Collect unique, non-empty entity types from loaded workflows.
    final entityTypes = <String>{};
    for (final wf in workflows) {
      // wf.entityType — works for ApprovalWorkflow or any object with
      // this getter; we use dynamic to avoid a tight import coupling.
      try {
        final et = (wf as dynamic).entityType as String?;
        if (et != null && et.isNotEmpty) entityTypes.add(et);
      } catch (_) {
        // Skip objects without entityType.
      }
    }

    // Load schemas in parallel — loadSchema deduplicates in-flight.
    if (entityTypes.isNotEmpty) {
      await Future.wait(entityTypes.map((et) => loadSchema(et)));
    }
  }

  /// Whether entity type metadata is fully resolved for the given key.
  /// Returns true when either a descriptor or schema is cached.
  bool isEntityTypeResolved(String entityType) {
    return descriptorFor(entityType) != null ||
        _schemaCache.containsKey(_cacheKey(entityType));
  }

  /// Whether the field schema for [entityType] has completed loading
  /// (either successfully cached or encountered an error).
  bool isSchemaResolved(String entityType) {
    final key = _cacheKey(entityType);
    return _schemaCache.containsKey(key) || _schemaErrors.containsKey(key);
  }

  // ── Test Helpers ───────────────────────────────────────

  /// Expose internal state for testing only.
  @visibleForTesting
  String? get testWorkspaceId => _workspaceId;

  @visibleForTesting
  Map<String, EntityFieldSchema> get testSchemaCache =>
      Map.unmodifiable(_schemaCache);

  @visibleForTesting
  Map<String, bool> get testSchemaLoading => Map.unmodifiable(_schemaLoading);

  @visibleForTesting
  Map<String, String?> get testSchemaErrors => Map.unmodifiable(_schemaErrors);

  @visibleForTesting
  List<ApprovalEntityTypeDescriptor>? get testEntityTypes => _entityTypes;

  @visibleForTesting
  bool get testEntityTypesLoading => _entityTypesLoading;

  @visibleForTesting
  String? get testEntityTypesError => _entityTypesError;
}
