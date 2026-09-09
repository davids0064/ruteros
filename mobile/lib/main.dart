import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertUsableInRelease();
  runApp(const ProviderScope(child: BoulderCoSetterApp()));
}
