import 'dart:convert';

enum ProgramCommandType { moveJoints, wait, setOutput, comment }

extension ProgramCommandTypeX on ProgramCommandType {
  String get label {
    switch (this) {
      case ProgramCommandType.moveJoints:
        return 'MOVE_JOINTS';
      case ProgramCommandType.wait:
        return 'WAIT';
      case ProgramCommandType.setOutput:
        return 'SET_OUTPUT';
      case ProgramCommandType.comment:
        return 'COMMENT';
    }
  }

  static ProgramCommandType fromWire(String value) {
    switch (value.toUpperCase()) {
      case 'WAIT':
        return ProgramCommandType.wait;
      case 'SET_OUTPUT':
        return ProgramCommandType.setOutput;
      case 'COMMENT':
        return ProgramCommandType.comment;
      case 'MOVE_JOINTS':
      default:
        return ProgramCommandType.moveJoints;
    }
  }
}

class ProgramCommand {
  const ProgramCommand({
    required this.id,
    required this.commandType,
    required this.jointAngles,
    required this.speed,
    required this.delayAfterMs,
    this.note,
    this.outputTag,
    this.outputValue,
  });

  final String id;
  final ProgramCommandType commandType;
  final List<double> jointAngles;
  final int speed;
  final int delayAfterMs;
  final String? note;
  final String? outputTag;
  final bool? outputValue;

  ProgramCommand copyWith({
    String? id,
    ProgramCommandType? commandType,
    List<double>? jointAngles,
    int? speed,
    int? delayAfterMs,
    String? note,
    String? outputTag,
    bool? outputValue,
  }) {
    return ProgramCommand(
      id: id ?? this.id,
      commandType: commandType ?? this.commandType,
      jointAngles: jointAngles ?? this.jointAngles,
      speed: speed ?? this.speed,
      delayAfterMs: delayAfterMs ?? this.delayAfterMs,
      note: note ?? this.note,
      outputTag: outputTag ?? this.outputTag,
      outputValue: outputValue ?? this.outputValue,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'commandType': commandType.label,
        'jointAngles': jointAngles,
        'speed': speed,
        'delayAfterMs': delayAfterMs,
        'note': note,
        'outputTag': outputTag,
        'outputValue': outputValue,
      };

  factory ProgramCommand.fromJson(Map<String, dynamic> json) {
    final rawJoints = json['jointAngles'];
    return ProgramCommand(
      id: json['id']?.toString() ?? 'CMD-0',
      commandType: ProgramCommandTypeX.fromWire(json['commandType']?.toString() ?? 'MOVE_JOINTS'),
      jointAngles: rawJoints is List
          ? rawJoints.map((e) => (e as num).toDouble()).toList(growable: false)
          : const <double>[0, 0, 0, 0, 0, 0],
      speed: (json['speed'] as num?)?.toInt() ?? 0,
      delayAfterMs: (json['delayAfterMs'] as num?)?.toInt() ?? 1000,
      note: json['note']?.toString(),
      outputTag: json['outputTag']?.toString(),
      outputValue: json['outputValue'] as bool?,
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
