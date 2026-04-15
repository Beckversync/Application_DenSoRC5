import 'dart:convert';

import 'program_command.dart';

class ProgramDefinition {
  const ProgramDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.commands,
    required this.defaultDelayMs,
  });

  final String id;
  final String name;
  final String description;
  final List<ProgramCommand> commands;
  final int defaultDelayMs;

  ProgramDefinition copyWith({
    String? id,
    String? name,
    String? description,
    List<ProgramCommand>? commands,
    int? defaultDelayMs,
  }) {
    return ProgramDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      commands: commands ?? this.commands,
      defaultDelayMs: defaultDelayMs ?? this.defaultDelayMs,
    );
  }

  Duration get estimatedRuntime {
    var totalMs = 0;
    for (final command in commands) {
      totalMs += command.delayAfterMs;
    }
    return Duration(milliseconds: totalMs);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'programId': id,
        'programName': name,
        'description': description,
        'defaultDelayMs': defaultDelayMs,
        'commands': commands.map((e) => e.toJson()).toList(growable: false),
      };

  factory ProgramDefinition.fromJson(Map<String, dynamic> json) {
    final rawCommands = json['commands'];
    return ProgramDefinition(
      id: json['programId']?.toString() ?? 'P-0',
      name: json['programName']?.toString() ?? 'Program',
      description: json['description']?.toString() ?? '',
      defaultDelayMs: (json['defaultDelayMs'] as num?)?.toInt() ?? 1000,
      commands: rawCommands is List
          ? rawCommands
                .map((e) => ProgramCommand.fromJson((e as Map).cast<String, dynamic>()))
                .toList(growable: false)
          : const <ProgramCommand>[],
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
