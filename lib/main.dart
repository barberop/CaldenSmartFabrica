import 'dart:io';
import 'package:caldensmartfabrica/devices/calefactores.dart';
import 'package:caldensmartfabrica/devices/detectores.dart';
import 'package:caldensmartfabrica/devices/domotica.dart';
import 'package:caldensmartfabrica/devices/millenium.dart';
import 'package:caldensmartfabrica/firebase_options.dart';
import 'package:caldensmartfabrica/global/loading.dart';
import 'package:caldensmartfabrica/global/login.dart';
import 'package:caldensmartfabrica/global/menu.dart';
import 'package:caldensmartfabrica/global/permission.dart';
import 'package:caldensmartfabrica/master.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'devices/patito.dart';
import 'devices/rele.dart';
import 'devices/roller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase solo si no ha sido inicializado previamente.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FlutterError.onError = (FlutterErrorDetails details) async {
    String errorReport = generateErrorReport(details);
    final fileName = 'error_report_${DateTime.now().toIso8601String()}.txt';
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(errorReport);
      sendReportOnWhatsApp(file.path);
    } else {
      printLog('Failed to get external storage directory');
    }
  };

  printLog('Todo configurado, iniciando app');
  runApp(
    ChangeNotifierProvider(
      create: (context) => GlobalDataNotifier(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      fbData = await fetchDocumentData();
      printLog(fbData, "rojo");
    });
    printLog('Empezamos');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'CaldénSmart Fábrica',
      theme: ThemeData(
        primaryColor: const Color(0xFF302b36),
        primaryColorLight: const Color(0xFFCFC8BD),
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0xFFCFC8BD),
          selectionHandleColor: Color(0xFFCFC8BD),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.transparent,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF302b36),
        ),
        useMaterial3: true,
      ),
      initialRoute: '/perm',
      routes: {
        '/perm': (context) => const PermissionHandler(),
        '/login': (context) => const LoginPage(),
        '/loading': (context) => const LoadingPage(),
        '/menu': (context) => const MenuPage(),
        '/calefactor': (context) => const CalefactoresPage(),
        '/detector': (context) => const DetectorPage(),
        '/rele': (context) => const RelePage(),
        '/domotica': (context) => const DomoticaPage(),
        '/patito': (context) => const PatitoPage(),
        '/roller': (context) => const RollerPage(),
        '/millenium': (context) => const MilleniumPage(),
      },
    );
  }
}
