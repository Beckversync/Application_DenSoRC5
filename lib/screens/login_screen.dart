import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'widgets/app_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController(text: 'operator');
  final TextEditingController _passwordController = TextEditingController(text: '123456');

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DENSO RC5 Remote Monitor & Scheduler', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text(
                      'Ứng dụng mobile đã được cập nhật theo kiến trúc mới: Operator có thể quan sát 3D, điều khiển 6 joints và lập lịch qua MQTT; Viewer chỉ có thể xem mô hình 3D.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'operator / viewer',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 20),
                    AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              onPressed: widget.controller.busy
                                  ? null
                                  : () => widget.controller.login(
                                        _usernameController.text,
                                        _passwordController.text,
                                      ),
                              child: Text(widget.controller.busy ? 'Đang đăng nhập...' : 'Đăng nhập'),
                            ),
                            if (widget.controller.errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                widget.controller.errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Lưu ý: username/password ở đây dùng để xác định vai trò giao diện. MQTT broker vẫn dùng credential cố định trong cấu hình app.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
