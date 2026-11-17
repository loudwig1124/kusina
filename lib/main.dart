/// Entry point: open the on-device SQLite database (bundled DDL + seed on first
/// run), then run the one app (`docs/08` §3.1, §4.10).
library;

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phase B: the app runs on SQLite behind the same ports; the seed runs inside
  // `Repositories.sqlite` before the first screen is built.
  final repositories = await Repositories.sqlite();
  runApp(KusinaApp(repositories: repositories));
}
