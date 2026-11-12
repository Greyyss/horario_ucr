import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/dashboard.dart';
import 'pages/login_page.dart';
import 'pages/registro_padron_page.dart';
import 'widgets/session_idle_timeout.dart';

class DeclaraApp extends StatefulWidget {
  const DeclaraApp({super.key});

  @override
  State<DeclaraApp> createState() => _DeclaraAppState();
}

class _DeclaraAppState extends State<DeclaraApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeclaraHorario',
      navigatorKey: _navigatorKey,
      builder: (context, child) => SessionIdleTimeout(
        onExpired: () => _navigatorKey.currentState?.popUntil(
          (route) => route.isFirst,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'MyriadPro',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF244D72),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
      locale: const Locale('es', 'ES'),
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text(
                  'Error de autenticación: ${snapshot.error}',
                ),
              ),
            );
          }

          if (snapshot.data == null) {
            return const LoginPage();
          }

          final uid = snapshot.data!.uid;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            key: ValueKey(uid),
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, perfil) {
              if (perfil.hasError) {
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: Text(
                          'Error al leer el perfil: ${perfil.error}\nCerrar sesión'),
                    ),
                  ),
                );
              }

              if (!perfil.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (perfil.data!.exists) {
                return const Dashboard();
              }

              return ValueListenableBuilder<bool>(
                valueListenable: registroPadronEnCurso,
                builder: (context, guardando, child) {
                  if (guardando) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return const RegistroPadronPage();
                },
              );
            },
          );
        },
      ),
    );
  }
}
