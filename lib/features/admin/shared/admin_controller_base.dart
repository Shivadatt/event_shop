import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/data/query.dart';

/// Shared scaffolding for admin controllers: load state, in-flight guards and one failure sink.
///
/// Every one of these screens must distinguish four states, and `error == null` alone cannot do
/// it — a table that has never answered looks identical to a table that legitimately matched zero
/// rows. [hasLoaded] is what makes that distinction, and [OmAdminSection] is where it is read.
abstract class AdminController extends GetxController {
  AdminController({this.pageSize = 25});

  final int pageSize;

  final RxBool isLoading = false.obs;
  final RxBool isSubmitting = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  /// Set once a load has completed or failed, so an empty result is rendered as empty and a
  /// never-returned result is rendered as a failure with a retry.
  final RxBool hasLoaded = false.obs;

  SessionStore get session => Get.find<SessionStore>();

  /// Runs [body] with loading + failure bookkeeping. Only [OmFailure] is caught: anything else is
  /// a bug and must reach the zone handler rather than a red banner an operator can retry.
  @protected
  Future<T?> guard<T>(
    Future<T> Function() body, {
    bool silent = false,
    bool asSubmitting = false,
  }) async {
    if (asSubmitting) {
      if (isSubmitting.value) return null;
      isSubmitting.value = true;
    } else if (!silent) {
      if (isLoading.value) return null;
      isLoading.value = true;
    }
    clearFailure();
    try {
      final result = await body();
      hasLoaded.value = true;
      return result;
    } on OmFailure catch (error) {
      failure.value = error;
      hasLoaded.value = true;
      return null;
    } finally {
      if (asSubmitting) {
        isSubmitting.value = false;
      } else if (!silent) {
        isLoading.value = false;
      }
    }
  }

  /// Mutation entry point for repositories that return the updated document. Success is decided
  /// by the failure sink, never by trusting the object the form already held.
  @protected
  Future<T?> mutate<T>(Future<T> Function() body) =>
      guard<T>(body, asSubmitting: true);

  /// Mutation entry point for repository methods that return void.
  ///
  /// `guard` answers `null` when the write failed, so the await has to happen before the fallback:
  /// `guard<bool>(...) ?? false` would test the *Future object* for null, which is never null, and
  /// hand callers an `Object` instead of a bool.
  @protected
  Future<bool> mutateVoid(Future<void> Function() body) async {
    final result = await guard<bool>(
      () async {
        await body();
        return true;
      },
      asSubmitting: true,
    );
    return result ?? false;
  }

  @protected
  void clearFailure() => failure.value = null;

  /// One voice for every admin confirmation and refusal.
  @protected
  void announce(String message, {bool error = false}) {
    Get.snackbar(
      error ? 'Action failed' : 'Done',
      message,
      maxWidth: 420,
      margin: const EdgeInsets.symmetric(horizontal: OmSpacing.md, vertical: OmSpacing.lg),
      borderRadius: OmRadius.md,
      leftBarIndicatorColor: error ? OmColors.danger : OmColors.gold,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

/// A server-paginated list. Page one comes from [fetch] with a null cursor; "load more" passes
/// back the cursor the previous page returned. Nothing here slices a client-side array, because
/// the admin tables must show exactly the page the server sent.
mixin PagedAdminList<T> on AdminController {
  final RxList<T> rows = <T>[].obs;
  final RxnString nextCursor = RxnString();

  /// The server's own estimate of how many rows match, when the page carries one. Null means the
  /// backend did not answer that question, and [OmAdminPager] then says "N rows loaded" instead of
  /// inventing a total from the page length.
  final RxnInt totalEstimate = RxnInt();

  bool get hasMore => nextCursor.value != null;
  bool get hasRows => rows.isNotEmpty;
  bool get isPageEmpty => hasLoaded.value && rows.isEmpty && failure.value == null;

  Future<PagedResult<T>> fetch({String? cursor});

  /// Reloads page one and discards any pages already appended. Called after every mutation and
  /// after every filter change, so a stale second page cannot survive a server-side edit.
  Future<void> loadFirstPage() async {
    final page = await guard<PagedResult<T>>(fetch);
    if (page == null) return;
    rows.assignAll(page.items);
    nextCursor.value = page.nextCursor;
    totalEstimate.value = page.totalEstimate;
  }

  /// Appends, so an operator scrolling a long order list keeps their place.
  Future<void> loadMore() async {
    final cursor = nextCursor.value;
    if (cursor == null) return;
    final page = await guard<PagedResult<T>>(() => fetch(cursor: cursor), silent: true);
    if (page == null) return;
    rows.addAll(page.items);
    nextCursor.value = page.nextCursor;
  }

  /// GetX declares `refresh()` as a void notification hook; here it re-reads page one so a list
  /// bound to a `RefreshIndicator` or an explicit reload button gets server-truth rows.
  @override
  Future<void> refresh() => loadFirstPage();

  void clearRows() {
    rows.clear();
    nextCursor.value = null;
    totalEstimate.value = null;
  }
}
