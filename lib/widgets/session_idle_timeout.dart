import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SessionIdleTimeout extends StatefulWidget {
  const SessionIdleTimeout({
    super.key,
    required this.child,
    required this.onExpired,
  });

  final Widget child;
  final VoidCallback onExpired;

  @override
  State<SessionIdleTimeout> createState() => _SessionIdleTimeoutState();
}

class _SessionIdleTimeoutState extends State<SessionIdleTimeout>
    with WidgetsBindingObserver {
  static const _limit = Duration(minutes: 5);

  late final StreamSubscription<User?> _authSubscription;
  Timer? _timer;
  String? _uid;
  DateTime? _deadline;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        _timer?.cancel();
        _uid = user?.uid;
        _deadline = null;
        if (_uid != null) _restart();
      },
    );
  }

  bool _onKey(KeyEvent event) {
    _onActivity();
    return false;
  }

  void _onActivity() {
    final deadline = _deadline;
    if (deadline == null || _signingOut) return;
    if (DateTime.now().isBefore(deadline)) {
      _restart();
    } else {
      unawaited(_expire());
    }
  }

  void _restart() {
    _timer?.cancel();
    _deadline = DateTime.now().add(_limit);
    _timer = Timer(_limit, () => unawaited(_expire()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final deadline = _deadline;
    if (state == AppLifecycleState.resumed &&
        deadline != null &&
        !DateTime.now().isBefore(deadline)) {
      unawaited(_expire());
    }
  }

  Future<void> _expire() async {
    final uid = _uid;
    if (uid == null ||
        _signingOut ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      return;
    }

    _signingOut = true;
    _timer?.cancel();
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted && FirebaseAuth.instance.currentUser == null) {
        widget.onExpired();
      }
    } catch (error) {
      debugPrint('Error al cerrar la sesión por inactividad: $error');
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        _timer = Timer(const Duration(seconds: 5), () => unawaited(_expire()));
      }
    } finally {
      _signingOut = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_authSubscription.cancel());
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      onPointerMove: (_) => _onActivity(),
      onPointerSignal: (_) => _onActivity(),
      child: widget.child,
    );
  }
}
