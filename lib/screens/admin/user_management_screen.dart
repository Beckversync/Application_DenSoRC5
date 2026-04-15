import 'package:flutter/material.dart';
import 'package:best_flutter_ui_templates/models/user_role.dart';
import '../../controllers/app_controller.dart';
import '../widgets/app_card.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('User Management', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Màn này được dựng sẵn cho Admin. Khi tích hợp backend thật, chỉ cần thay datasource và form CRUD.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final user in controller.users) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(user.username),
                      subtitle: Text(user.role.label),
                      trailing: FilledButton.tonal(
                        onPressed: () {},
                        child: const Text('View'),
                      ),
                    ),
                    if (user != controller.users.last) const Divider(height: 1),
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
