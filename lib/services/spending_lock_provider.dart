import 'package:flutter/material.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/spending_lock.dart';
import 'package:finora/models/spending_lock_event.dart';
import 'package:finora/services/spending_lock_service.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/services/safe_lock_risk_engine.dart';

class SpendingLockProvider extends ChangeNotifier {
  SpendingLock? _lock;
  bool _loading = false;
  List<SpendingLockEvent> _recentEvents = [];
  SafetyAssessment _lastAssessment = SafetyAssessment.empty;

  // In-memory guard only (not persisted): stops the *same* just-saved
  // expense id from ever being evaluated twice in one app session, per
  // "don't increment warnings repeatedly for the same transaction".
  String? _lastEvaluatedExpenseId;
  bool _notificationsEnabled = true;

  /// Last error message, safe to show directly in a SnackBar/banner. Set
  /// whenever any SafeLock operation fails, cleared on the next successful
  /// call. Nothing in this provider ever lets an exception disappear
  /// silently — every public method below catches and records it here.
  String? _error;

  SpendingLock? get lock => _lock;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLocked => _lock?.lockStatus ?? false;
  bool get isStrictLocked => _lock?.isStrictLocked ?? false;
  int get warningCount => _lock?.warningCount ?? 0;
  int get emergencyLeft => _lock?.emergencyUnlocksLeftThisWeek ?? 3;
  bool get strictMode => _lock?.strictMode ?? false;
  double get budgetLimit => _lock?.budgetLimit ?? 0;
  bool get enabled => _lock?.enabled ?? true;
  SafeLockStatus get status => _lock?.status ?? SafeLockStatus.monitoring;
  List<SpendingLockEvent> get recentEvents => _recentEvents;
  SafetyAssessment get lastAssessment => _lastAssessment;
  bool get notificationsEnabled => _notificationsEnabled;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> load(String userId, double budgetLimit) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      var lockState = await SpendingLockService.getLockState(userId);
      lockState ??= await SpendingLockService.initLockState(userId, budgetLimit);
      _lock = lockState;
      _recentEvents = await SpendingLockService.getRecentEvents(userId);
      _notificationsEnabled = await SpendingLockService.getNotificationsEnabled(userId);
    } on SafeLockException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not load SafeLock. Please try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setNotificationsEnabled(String userId, bool val) async {
    _notificationsEnabled = val;
    notifyListeners();
    await SpendingLockService.setNotificationsEnabled(userId, val);
  }

  /// Re-derives the current SafetyAssessment (ring indicator + reasons)
  /// from real, already-loaded expense data — read-only, never writes
  /// anything, safe to call on every screen build.
  void refreshAssessment(List<Expense> expenses) {
    _lastAssessment = SafeLockRiskEngine.evaluate(
      expenses: expenses,
      budgetLimit: budgetLimit,
    );
    notifyListeners();
  }

  /// Call this after adding an expense. Evaluates real spending data via
  /// [SafeLockRiskEngine]; only issues a warning when genuine risk
  /// conditions are met, and never twice for the same [latestExpenseId].
  /// Never throws — on failure it records [error] and returns
  /// [WarningResult.ok] so the expense save itself isn't blocked by a
  /// SafeLock hiccup.
  Future<WarningResult> checkAndWarn(
    String userId,
    List<Expense> allExpensesNewestFirst, {
    String? latestExpenseId,
  }) async {
    if (_lock == null) return WarningResult.ok;
    if (!_lock!.enabled) return WarningResult.ok; // SafeLock is paused

    if (latestExpenseId != null && latestExpenseId == _lastEvaluatedExpenseId) {
      return WarningResult.ok; // already evaluated this exact transaction
    }

    try {
      final assessment = SafeLockRiskEngine.evaluate(
        expenses: allExpensesNewestFirst,
        budgetLimit: _lock!.budgetLimit,
      );
      _lastAssessment = assessment;

      if (latestExpenseId != null) _lastEvaluatedExpenseId = latestExpenseId;

      if (assessment.level == SafetyLevel.safe || assessment.reasons.isEmpty) {
        notifyListeners();
        return WarningResult.ok;
      }

      if (_lock!.warningCount >= 3) {
        notifyListeners();
        return WarningResult.locked;
      }

      // Issue a warning, tagged with the clearest real reason detected.
      _lock = await SpendingLockService.incrementWarning(
        userId,
        _lock!.warningCount,
        reason: assessment.reasons.first,
      );
      _recentEvents = await SpendingLockService.getRecentEvents(userId);
      notifyListeners();

      if (_lock!.lockStatus) {
        if (_notificationsEnabled) {
          await NotificationService().showLockAlert();
        }
        return WarningResult.locked;
      }
      return WarningResult.warned;
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
      return WarningResult.ok; // don't block the expense save on a SafeLock error
    } catch (e) {
      _error = 'SafeLock could not check this transaction, but your expense was still saved.';
      notifyListeners();
      return WarningResult.ok;
    }
  }

  /// Returns true if user is allowed to proceed after emergency unlock
  Future<bool> useEmergencyUnlock(String userId) async {
    if (_lock == null) return false;
    if (emergencyLeft <= 0) return false;

    try {
      _lock = await SpendingLockService.recordEmergencyUnlock(userId, _lock!.emergencyCount);
      notifyListeners();
      return true;
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Could not use emergency unlock. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleStrictMode(String userId, bool val) async {
    try {
      _lock = await SpendingLockService.toggleStrictMode(userId, val);
      notifyListeners();
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Could not update Strict Mode. Please try again.';
      notifyListeners();
    }
  }

  /// SafeLock master ON/OFF switch. Turning it off pauses monitoring
  /// (status becomes PAUSED) without touching the existing warning count,
  /// so re-enabling resumes exactly where it left off.
  Future<void> toggleEnabled(String userId, bool val) async {
    try {
      _lock = await SpendingLockService.toggleEnabled(userId, val);
      notifyListeners();
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Could not update SafeLock. Please try again.';
      notifyListeners();
    }
  }

  Future<void> resetLock(String userId) async {
    try {
      _lock = await SpendingLockService.resetLock(userId);
      _lastEvaluatedExpenseId = null;
      notifyListeners();
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Could not reset SafeLock. Please try again.';
      notifyListeners();
    }
  }

  Future<void> updateBudgetLimit(String userId, double limit) async {
    try {
      await SpendingLockService.updateBudgetLimit(userId, limit);
      _lock = _lock?.copyWith(budgetLimit: limit);
      notifyListeners();
    } on SafeLockException catch (e) {
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _error = 'Could not update budget limit. Please try again.';
      notifyListeners();
    }
  }
}

enum WarningResult { ok, warned, locked }
