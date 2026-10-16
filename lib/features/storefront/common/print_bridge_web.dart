// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

bool get canPrint => true;

void printCurrentPage() => web.window.print();
