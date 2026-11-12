import 'package:flutter/material.dart';

import 'declaration_views.dart' as declaration_views;

class TimelinePage extends StatelessWidget {
  final String id;

  const TimelinePage({
    super.key,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    return declaration_views.DeclarationHistoryPage(
      id: id,
    );
  }
}

