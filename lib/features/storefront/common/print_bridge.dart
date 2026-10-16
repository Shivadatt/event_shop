import 'print_bridge_stub.dart'
    if (dart.library.js_interop) 'print_bridge_web.dart' as bridge;

/// Triggers the browser print dialog over the current document. On non-web builds it degrades
/// to a no-op and the UI still tells the user to use Ctrl+P.
abstract final class OmPrint {
  static bool get canPrint => bridge.canPrint;
  static void printCurrentPage() => bridge.printCurrentPage();
}
