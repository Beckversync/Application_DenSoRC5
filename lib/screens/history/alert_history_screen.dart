import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../widgets/app_card.dart';

class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final items = controller.alertLogs;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alert & Warning History', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Text('Chưa có cảnh báo nào.')
                  else
                    for (final item in items) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        title: Text(item.level),
                        subtitle: Text('${item.message}\n${item.timestamp.toLocal()}'),
                        isThreeLine: true,
                      ),
                      if (item != items.last) const Divider(height: 1),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
