import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../widgets/app_card.dart';

class CommandHistoryScreen extends StatelessWidget {
  const CommandHistoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final items = controller.commandLogs;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Command History', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Text('Chưa có lệnh nào.')
                  else
                    for (final item in items) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.success ? Icons.check_circle_outline : Icons.error_outline,
                          color: item.success ? Colors.green : Colors.red,
                        ),
                        title: Text(item.commandType),
                        subtitle: Text('${item.message}\n${item.username} • ${item.timestamp.toLocal()}'),
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
