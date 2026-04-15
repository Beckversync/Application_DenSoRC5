import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/program_command.dart';
import '../models/program_definition.dart';
import 'widgets/app_card.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _defaultDelayController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _defaultDelayController = TextEditingController();
    _syncMetaFromController();
    widget.controller.addListener(_syncMetaFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncMetaFromController);
    _nameController.dispose();
    _descriptionController.dispose();
    _defaultDelayController.dispose();
    super.dispose();
  }

  void _syncMetaFromController() {
    _nameController.text = widget.controller.draftProgramName;
    _descriptionController.text = widget.controller.draftProgramDescription;
    _defaultDelayController.text = widget.controller.draftDefaultDelayMs.toString();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final current = widget.controller.selectedScheduleTime ?? now.add(const Duration(minutes: 10));
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;

    widget.controller.selectScheduleTime(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveProgram() async {
    widget.controller.updateDraftProgramMeta(
      name: _nameController.text,
      description: _descriptionController.text,
      defaultDelayMs: int.tryParse(_defaultDelayController.text) ?? 1000,
    );
    await widget.controller.saveDraftProgram();
    if (!mounted) return;
    if (widget.controller.errorMessage != null) {
      _showMessage(widget.controller.errorMessage!);
    } else {
      _showMessage('Program template đã lưu trong app thành công.');
    }
  }

  Future<void> _createSchedule() async {
    widget.controller.updateDraftProgramMeta(
      name: _nameController.text,
      description: _descriptionController.text,
      defaultDelayMs: int.tryParse(_defaultDelayController.text) ?? 1000,
    );
    await widget.controller.createSchedule();
    if (!mounted) return;
    if (widget.controller.errorMessage != null) {
      _showMessage(widget.controller.errorMessage!);
    } else {
      _showMessage('Schedule request đã publish qua MQTT thành công.');
    }
  }

  void _openCommandEditor([ProgramCommand? existing]) {
    final isWait = existing?.commandType == ProgramCommandType.wait;
    var commandType = existing?.commandType ?? ProgramCommandType.moveJoints;
    final jointControllers = List<TextEditingController>.generate(
      6,
      (index) => TextEditingController(
        text: existing?.jointAngles.length == 6 ? existing!.jointAngles[index].toStringAsFixed(1) : '0',
      ),
    );
    final speedController = TextEditingController(text: (existing?.speed ?? 30).toString());
    final delayController = TextEditingController(text: (existing?.delayAfterMs ?? widget.controller.draftDefaultDelayMs).toString());
    final noteController = TextEditingController(text: existing?.note ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final waitMode = commandType == ProgramCommandType.wait;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(existing == null ? 'Add Command' : 'Edit Command', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ProgramCommandType>(
                      value: commandType,
                      items: ProgramCommandType.values
                          .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => commandType = value);
                      },
                      decoration: const InputDecoration(labelText: 'Command Type'),
                    ),
                    const SizedBox(height: 12),
                    if (!waitMode)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < 6; i++)
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: jointControllers[i],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(labelText: 'J${i + 1}'),
                              ),
                            ),
                        ],
                      ),
                    if (!waitMode) const SizedBox(height: 12),
                    if (!waitMode)
                      TextField(
                        controller: speedController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Speed'),
                      ),
                    if (!waitMode) const SizedBox(height: 12),
                    TextField(
                      controller: delayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Delay After (ms)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        final joints = waitMode
                            ? const <double>[0, 0, 0, 0, 0, 0]
                            : jointControllers.map((c) => double.tryParse(c.text) ?? 0).toList(growable: false);
                        final next = ProgramCommand(
                          id: existing?.id ?? 'CMD-${DateTime.now().microsecondsSinceEpoch}',
                          commandType: commandType,
                          jointAngles: joints,
                          speed: waitMode ? 0 : (int.tryParse(speedController.text) ?? 30),
                          delayAfterMs: int.tryParse(delayController.text) ?? widget.controller.draftDefaultDelayMs,
                          note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                        );

                        if (existing == null) {
                          widget.controller.addCommand(next);
                        } else {
                          widget.controller.updateCommand(existing.id, next);
                        }
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: Text(existing == null ? 'Add Command' : 'Update Command'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      speedController.dispose();
      delayController.dispose();
      noteController.dispose();
      for (final controller in jointControllers) {
        controller.dispose();
      }
    });
  }

  String _formatRuntime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final programs = widget.controller.programs;
        final schedules = widget.controller.schedules;
        final draftProgram = ProgramDefinition(
          id: widget.controller.selectedProgramId ?? widget.controller.draftProgramId,
          name: widget.controller.draftProgramName,
          description: widget.controller.draftProgramDescription,
          commands: widget.controller.draftCommands,
          defaultDelayMs: widget.controller.draftDefaultDelayMs,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MQTT Program Builder', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Remote app chỉ publish một luồng production vào robot/v1/default/{robotId}/schedule/request. Mini PC sẽ phản hồi qua schedule/response, đồng bộ lại schedule/list và tự thực thi lịch cục bộ khi tới giờ.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: widget.controller.selectedProgramId,
                    items: [
                      for (final item in programs) DropdownMenuItem(value: item.id, child: Text(item.name)),
                    ],
                    onChanged: widget.controller.canSchedule ? widget.controller.selectProgram : null,
                    decoration: const InputDecoration(labelText: 'Load Existing Program'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.controller.startNewProgramDraft,
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('New Draft'),
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.controller.canSchedule && !widget.controller.busy ? _saveProgram : null,
                        icon: const Icon(Icons.publish_outlined),
                        label: const Text('Publish Program'),
                      ),
                      if (widget.controller.selectedProgramId != null)
                        OutlinedButton.icon(
                          onPressed: widget.controller.canSchedule && !widget.controller.busy
                              ? widget.controller.deleteSelectedProgram
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Program'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Program Name'),
                    onChanged: (value) => widget.controller.updateDraftProgramMeta(name: value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) => widget.controller.updateDraftProgramMeta(description: value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _defaultDelayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Default Delay (ms)'),
                    onChanged: (value) => widget.controller.updateDraftProgramMeta(defaultDelayMs: int.tryParse(value) ?? 1000),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: widget.controller.canSchedule ? () => _openCommandEditor() : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Command'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: widget.controller.toggleAdvancedJson,
                        icon: const Icon(Icons.code_outlined),
                        label: Text(widget.controller.showAdvancedJson ? 'Hide JSON' : 'View JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SummaryChip(label: '${draftProgram.commands.length} command(s)'),
                      _SummaryChip(label: 'Runtime ${_formatRuntime(draftProgram.estimatedRuntime)}'),
                      _SummaryChip(label: 'Default delay ${draftProgram.defaultDelayMs} ms'),
                    ],
                  ),
                  if (widget.controller.showAdvancedJson) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        widget.controller.generatedProgramJson,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Commands', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (widget.controller.draftCommands.isEmpty)
                    const Text('Chưa có command nào trong program.')
                  else
                    ListView.separated(
                      itemCount: widget.controller.draftCommands.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final command = widget.controller.draftCommands[index];
                        return _CommandCard(
                          index: index,
                          command: command,
                          onEdit: () => _openCommandEditor(command),
                          onDuplicate: () => widget.controller.duplicateCommand(command.id),
                          onDelete: () => widget.controller.removeCommand(command.id),
                          onMoveUp: () => widget.controller.moveCommandUp(command.id),
                          onMoveDown: () => widget.controller.moveCommandDown(command.id),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Publish Schedule', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    widget.controller.selectedScheduleTime == null
                        ? 'Chưa chọn thời gian.'
                        : widget.controller.selectedScheduleTime!.toLocal().toString(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.controller.canSchedule ? _pickDateTime : null,
                        icon: const Icon(Icons.event_outlined),
                        label: const Text('Select Date & Time'),
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.controller.canSchedule && !widget.controller.busy ? _createSchedule : null,
                        icon: const Icon(Icons.schedule_send_outlined),
                        label: const Text('Publish Schedule'),
                      ),
                    ],
                  ),
                  if (widget.controller.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(widget.controller.errorMessage!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scheduled Programs', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (schedules.isEmpty)
                    const Text('Chưa có schedule nào.')
                  else
                    ListView.separated(
                      itemCount: schedules.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final schedule = schedules[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(schedule.programName),
                          subtitle: Text(
  '${schedule.scheduledAt.toLocal()}\n'
  '${schedule.commandCount} command(s) • ${schedule.defaultDelayMs} ms delay',
),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Switch(
                                value: schedule.enabled,
                                onChanged: widget.controller.canSchedule
                                    ? (value) => widget.controller.toggleSchedule(schedule.id, value)
                                    : null,
                              ),
                              IconButton(
                                tooltip: 'Delete schedule',
                                onPressed: widget.controller.canSchedule
                                    ? () => widget.controller.deleteSchedule(schedule.id)
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.index,
    required this.command,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final ProgramCommand command;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final summary = command.commandType == ProgramCommandType.moveJoints
        ? command.jointAngles.map((e) => e.toStringAsFixed(1)).join(', ')
        : command.note ?? 'Delay command';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Step ${index + 1} • ${command.commandType.label}', style: Theme.of(context).textTheme.titleMedium),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'duplicate':
                      onDuplicate();
                      break;
                    case 'up':
                      onMoveUp();
                      break;
                    case 'down':
                      onMoveDown();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'up', child: Text('Move Up')),
                  PopupMenuItem(value: 'down', child: Text('Move Down')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text('speed ${command.speed} • delay ${command.delayAfterMs} ms', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
