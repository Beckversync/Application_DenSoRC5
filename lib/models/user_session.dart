import 'user_role.dart';

class UserSession {
  const UserSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.token,
  });

  final String userId;
  final String username;
  final UserRole role;
  final String token;

  UserSession copyWith({
    String? userId,
    String? username,
    UserRole? role,
    String? token,
  }) {
    return UserSession(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      role: role ?? this.role,
      token: token ?? this.token,
    );
  }
}
