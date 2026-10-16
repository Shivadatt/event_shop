import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/errors/failures.dart';

/// Every `await` in a storefront controller goes through here so an unexpected non-`OmFailure`
/// throw (including a `Get.find` on a repository Agent 3 never bound) still renders as an honest
/// error state instead of a red screen.
Future<T?> safeCall<T>(
  Future<T> Function() action, {
  void Function(OmFailure failure)? onFailure,
}) async {
  try {
    return await action();
  } on OmFailure catch (failure) {
    onFailure?.call(failure);
    return null;
  } catch (error, stack) {
    debugPrint('storefront unexpected error: $error\n$stack');
    onFailure?.call(const ServerFailure());
    return null;
  }
}

/// Fire an action and only report success when it actually completed; the boolean is for
/// "show a snackbar", never for money or permission decisions.
Future<bool> tryCall(Future<void> Function() action, {void Function(OmFailure)? onFailure}) async {
  var ok = false;
  await safeCall<void>(
    () async {
      await action();
      ok = true;
    },
    onFailure: (failure) {
      onFailure?.call(failure);
    },
  );
  return ok;
}
