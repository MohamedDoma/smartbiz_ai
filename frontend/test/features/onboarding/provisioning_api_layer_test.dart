// SmartBiz AI — Step 1.7 Verification: Flutter Provisioning API Layer.
//
// Structural verification tests for:
//   1. Session/auth model backward compatibility
//   2. Provisioning model parsing (preview, apply, finalize)
//   3. Error model mapping
//   4. API exception hierarchy (403, 404)
//   5. Repository result types

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_exceptions.dart';
import 'package:smartbiz_ai/core/api/auth_models.dart';
import 'package:smartbiz_ai/core/api/provisioning_models.dart';
import 'package:smartbiz_ai/features/onboarding/data/provisioning_repository.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  //  1. Session/Auth Model — Backward Compatibility
  // ═══════════════════════════════════════════════════════════

  group('AuthSession backward compatibility', () {
    test('old session without onboarding_completed defaults to false', () {
      final json = {
        'user': {'id': 'u1', 'full_name': 'Test', 'email': 'a@b.com'},
        'active_workspace': {'id': 'ws1', 'name': 'W1'},
        'memberships': [
          {
            'id': 'm1',
            'workspace_id': 'ws1',
            'workspace': {'id': 'ws1', 'name': 'W1'},
            'status': 'active',
            'roles': [],
            'permissions': [],
          }
        ],
      };
      final session = AuthSession.fromJson(json);
      expect(session.activeWorkspace?.onboardingCompleted, false);
      expect(session.memberships.first.onboardingCompleted, false);
    });

    test('new session with onboarding_completed=true parses correctly', () {
      final json = {
        'user': {'id': 'u1', 'full_name': 'Test', 'email': 'a@b.com'},
        'active_workspace': {
          'id': 'ws1',
          'name': 'W1',
          'onboarding_completed': true,
          'enabled_modules': ['sales'],
          'permissions': ['products.view'],
        },
        'memberships': [
          {
            'id': 'm1',
            'workspace_id': 'ws1',
            'workspace': {'id': 'ws1', 'name': 'W1'},
            'status': 'active',
            'onboarding_completed': true,
            'roles': [],
            'permissions': ['products.view'],
            'enabled_modules': ['sales'],
          }
        ],
      };
      final session = AuthSession.fromJson(json);
      expect(session.activeWorkspace?.onboardingCompleted, true);
      expect(session.memberships.first.onboardingCompleted, true);
    });

    test('null active_workspace does not crash', () {
      final json = {
        'user': {'id': 'u1', 'full_name': 'Test', 'email': 'a@b.com'},
        'active_workspace': null,
        'memberships': [],
      };
      final session = AuthSession.fromJson(json);
      expect(session.activeWorkspace, null);
      expect(session.memberships, isEmpty);
    });

    test('token field preserved', () {
      final json = {
        'token': 'abc123',
        'user': {'id': 'u1', 'full_name': 'Test', 'email': 'a@b.com'},
      };
      final session = AuthSession.fromJson(json);
      expect(session.token, 'abc123');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. ProvisioningRunStatus enum
  // ═══════════════════════════════════════════════════════════

  group('ProvisioningRunStatus', () {
    test('parses all known status strings', () {
      expect(ProvisioningRunStatus.fromString('preview'),
          ProvisioningRunStatus.preview);
      expect(ProvisioningRunStatus.fromString('prepared'),
          ProvisioningRunStatus.prepared);
      expect(ProvisioningRunStatus.fromString('processing'),
          ProvisioningRunStatus.processing);
      expect(ProvisioningRunStatus.fromString('foundation_applied'),
          ProvisioningRunStatus.foundationApplied);
      expect(ProvisioningRunStatus.fromString('applied'),
          ProvisioningRunStatus.applied);
      expect(ProvisioningRunStatus.fromString('onboarding_complete'),
          ProvisioningRunStatus.onboardingComplete);
      expect(ProvisioningRunStatus.fromString('rolled_back'),
          ProvisioningRunStatus.rolledBack);
      expect(ProvisioningRunStatus.fromString('failed'),
          ProvisioningRunStatus.failed);
    });

    test('unknown string returns unknown', () {
      expect(ProvisioningRunStatus.fromString('garbage'),
          ProvisioningRunStatus.unknown);
      expect(ProvisioningRunStatus.fromString(null),
          ProvisioningRunStatus.unknown);
    });

    test('isOnboardingDone is correct', () {
      expect(ProvisioningRunStatus.applied.isOnboardingDone, true);
      expect(ProvisioningRunStatus.onboardingComplete.isOnboardingDone, true);
      expect(ProvisioningRunStatus.preview.isOnboardingDone, false);
      expect(ProvisioningRunStatus.failed.isOnboardingDone, false);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Preview Result Parsing
  // ═══════════════════════════════════════════════════════════

  group('PreviewResult', () {
    test('parses valid preview response', () {
      final json = {
        'run_id': 'r1',
        'status': 'preview',
        'version': 3,
        'plan': {
          'operations': {'roles': [], 'departments': []}
        },
      };
      final result = PreviewResult.fromJson(json);
      expect(result.runId, 'r1');
      expect(result.status, 'preview');
      expect(result.version, 3);
      expect(result.isValid, true);
      expect(result.plan.containsKey('operations'), true);
    });

    test('parses validation_failed preview', () {
      final json = {
        'run_id': '',
        'status': 'validation_failed',
        'validation_errors': ['Unknown permission: foo.bar'],
      };
      final result = PreviewResult.fromJson(json);
      expect(result.isValid, false);
      expect(result.validationErrors, ['Unknown permission: foo.bar']);
    });

    test('handles empty/missing fields safely', () {
      final result = PreviewResult.fromJson({});
      expect(result.runId, '');
      expect(result.status, '');
      expect(result.version, 1);
      expect(result.plan, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Apply Result Parsing
  // ═══════════════════════════════════════════════════════════

  group('ApplyResult', () {
    test('parses successful apply response', () {
      final json = {
        'run_id': 'r2',
        'status': 'applied',
        'workspace_id': 'ws1',
        'entities_created': 12,
        'entities_adopted': 3,
        'entities': [
          {
            'entity_type': 'role',
            'entity_id': 'role-1',
            'key': 'owner',
            'name': 'Owner',
            'action': 'created',
          },
          {
            'entity_type': 'department',
            'entity_id': 'dept-1',
            'key': 'engineering',
            'action': 'adopted',
          },
        ],
      };
      final result = ApplyResult.fromJson(json);
      expect(result.runId, 'r2');
      expect(result.status, 'applied');
      expect(result.entitiesCreated, 12);
      expect(result.entitiesAdopted, 3);
      expect(result.entities.length, 2);
      expect(result.entities[0].entityType, 'role');
      expect(result.entities[0].key, 'owner');
      expect(result.entities[1].action, 'adopted');
      expect(result.alreadyApplied, false);
    });

    test('parses idempotent apply (already_applied)', () {
      final json = {
        'run_id': 'r2',
        'status': 'applied',
        'already_applied': true,
        'message': 'Already applied with same version.',
      };
      final result = ApplyResult.fromJson(json);
      expect(result.alreadyApplied, true);
      expect(result.message, 'Already applied with same version.');
    });

    test('parses active_run conflict', () {
      final json = {
        'run_id': '',
        'status': '',
        'message': 'An active run exists.',
        'active_run': {'run_id': 'r-old'},
      };
      final result = ApplyResult.fromJson(json);
      expect(result.activeRunId, 'r-old');
    });

    test('handles empty apply response', () {
      final result = ApplyResult.fromJson({});
      expect(result.runId, '');
      expect(result.entities, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Finalize Result Parsing
  // ═══════════════════════════════════════════════════════════

  group('FinalizeResult', () {
    test('parses successful finalize response', () {
      final json = {
        'run_id': 'r3',
        'status': 'onboarding_complete',
        'workspace_id': 'ws1',
        'primary_owner_role': {
          'key': 'owner',
          'id': 'role-1',
          'name': 'Owner',
        },
        'owner_membership': {
          'id': 'm1',
          'user_id': 'u1',
        },
        'role_assigned': true,
        'onboarding_completed': true,
      };
      final result = FinalizeResult.fromJson(json);
      expect(result.runId, 'r3');
      expect(result.status, 'onboarding_complete');
      expect(result.primaryOwnerRole?.key, 'owner');
      expect(result.primaryOwnerRole?.name, 'Owner');
      expect(result.ownerMembership?.userId, 'u1');
      expect(result.roleAssigned, true);
      expect(result.onboardingCompleted, true);
      expect(result.alreadyFinalized, false);
    });

    test('parses idempotent finalize response', () {
      final json = {
        'run_id': 'r3',
        'status': 'onboarding_complete',
        'already_finalized': true,
        'onboarding_completed': true,
      };
      final result = FinalizeResult.fromJson(json);
      expect(result.alreadyFinalized, true);
      expect(result.onboardingCompleted, true);
    });

    test('handles missing optional fields', () {
      final result = FinalizeResult.fromJson({'run_id': 'r3', 'status': 'ok'});
      expect(result.primaryOwnerRole, null);
      expect(result.ownerMembership, null);
      expect(result.roleAssigned, false);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. ProvisioningError Model
  // ═══════════════════════════════════════════════════════════

  group('ProvisioningError', () {
    test('parses from backend JSON', () {
      final json = {
        'message': 'Run not found.',
        'error': 'run_not_found',
      };
      final error = ProvisioningError.fromJson(json, statusCode: 404);
      expect(error.message, 'Run not found.');
      expect(error.errorCode, 'run_not_found');
      expect(error.statusCode, 404);
      expect(error.isNotFound, true);
      expect(error.isConflict, false);
    });

    test('parses conflict error', () {
      final json = {
        'message': 'Invalid status transition.',
        'error': 'invalid_status_transition',
      };
      final error = ProvisioningError.fromJson(json, statusCode: 409);
      expect(error.isConflict, true);
      expect(error.errorCode, 'invalid_status_transition');
    });

    test('parses validation error', () {
      final json = {
        'message': 'Missing primary owner role.',
        'error': 'missing_primary_owner_role',
      };
      final error = ProvisioningError.fromJson(json, statusCode: 422);
      expect(error.isValidation, true);
    });

    test('parses forbidden error', () {
      final error = ProvisioningError(
        message: 'Forbidden',
        statusCode: 403,
      );
      expect(error.isForbidden, true);
    });

    test('handles missing error field', () {
      final error = ProvisioningError.fromJson({}, statusCode: 500);
      expect(error.message, 'Unknown error');
      expect(error.errorCode, null);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. API Exception Hierarchy
  // ═══════════════════════════════════════════════════════════

  group('API Exceptions', () {
    test('ForbiddenException has 403 status', () {
      const e = ForbiddenException('Nope');
      expect(e.statusCode, 403);
      expect(e.message, 'Nope');
      expect(e, isA<ApiException>());
    });

    test('NotFoundException has 404 status and error code', () {
      const e = NotFoundException(
        message: 'Not here',
        errorCode: 'run_not_found',
      );
      expect(e.statusCode, 404);
      expect(e.errorCode, 'run_not_found');
      expect(e, isA<ApiException>());
    });

    test('ConflictException preserved', () {
      const e = ConflictException(
        message: 'Conflict',
        errorCode: 'concurrent_run',
      );
      expect(e.statusCode, 409);
      expect(e.errorCode, 'concurrent_run');
    });

    test('AuthException preserved', () {
      const e = AuthException('Unauthenticated.');
      expect(e.statusCode, 401);
    });

    test('ValidationException preserved', () {
      const e = ValidationException(
        message: 'Bad input',
        errors: {
          'email': ['Required']
        },
      );
      expect(e.statusCode, 422);
      expect(e.firstMessage, 'Required');
    });

    test('NetworkException preserved', () {
      const e = NetworkException();
      expect(e.message, 'Network error. Check your connection.');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8. Repository Result Types
  // ═══════════════════════════════════════════════════════════

  group('ProvisioningResult', () {
    test('success result', () {
      final result = ProvisioningResult<String>.success('ok');
      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.data, 'ok');
      expect(result.error, null);
      expect(result.errorType, ProvisioningErrorType.none);
    });

    test('failure result with 404', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(
          message: 'Not found',
          errorCode: 'run_not_found',
          statusCode: 404,
        ),
      );
      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.errorType, ProvisioningErrorType.notFound);
    });

    test('failure result with 409', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(
          message: 'Conflict',
          statusCode: 409,
        ),
      );
      expect(result.errorType, ProvisioningErrorType.conflict);
    });

    test('failure result with 401', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(message: 'Unauth', statusCode: 401),
      );
      expect(result.errorType, ProvisioningErrorType.unauthorized);
    });

    test('failure result with 403', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(message: 'Forbidden', statusCode: 403),
      );
      expect(result.errorType, ProvisioningErrorType.forbidden);
    });

    test('failure result with 422', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(message: 'Validation', statusCode: 422),
      );
      expect(result.errorType, ProvisioningErrorType.validation);
    });

    test('failure result with 500', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(message: 'Server', statusCode: 500),
      );
      expect(result.errorType, ProvisioningErrorType.server);
    });

    test('failure result with 0 (network)', () {
      final result = ProvisioningResult<String>.failure(
        const ProvisioningError(message: 'Net', statusCode: 0),
      );
      expect(result.errorType, ProvisioningErrorType.network);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  9. ProvisioningRun Model
  // ═══════════════════════════════════════════════════════════

  group('ProvisioningRun model', () {
    test('parses from backend JSON', () {
      final json = {
        'id': 'run-1',
        'workspace_id': 'ws-1',
        'blueprint_id': 'bp-1',
        'status': 'applied',
        'version': 2,
        'config': {
          'operations': {'roles': []}
        },
        'created_at': '2026-07-17T00:00:00Z',
      };
      final run = ProvisioningRun.fromJson(json);
      expect(run.id, 'run-1');
      expect(run.status, ProvisioningRunStatus.applied);
      expect(run.version, 2);
      expect(run.config['operations'], isNotNull);
    });

    test('handles missing/null fields', () {
      final run = ProvisioningRun.fromJson({});
      expect(run.id, '');
      expect(run.status, ProvisioningRunStatus.unknown);
      expect(run.config, isEmpty);
    });
  });
}
