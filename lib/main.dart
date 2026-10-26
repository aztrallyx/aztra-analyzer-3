import 'package:flutter/foundation.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_page.dart';
import 'library.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();
  final settings = await AppSettings.load();
  final controller = LibraryController(
    concurrency: () => settings.analysisParallelism,
  );
  await controller.init();
  runApp(AztraApp(settings: settings, controller: controller));
}

void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'Mornye (analizador de audio)': 'assets/licenses/Mornye-LGPL-3.0.txt',
      'Google Sans Flex': 'assets/licenses/GoogleSansFlex-LICENSE.txt',
      'Inter': 'assets/licenses/Inter-LICENSE.txt',
    }.entries) {
      try {
        yield LicenseEntryWithLineBreaks([
          entry.key,
        ], await rootBundle.loadString(entry.value));
      } catch (_) {}
    }
  });
}

class AztraApp extends StatelessWidget {
  const AztraApp({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            return MaterialApp(
              title: 'Aztra Analyzer',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(darkDynamic, settings.fontFamily),
              home: HomePage(controller: controller, settings: settings),
            );
          },
        );
      },
    );
  }
}
