// Copyright (c) 2022, Very Good Ventures
// https://verygood.ventures
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:convert';
import 'dart:io';

import 'package:cli_menu/cli_menu.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// {@template script_command}
///
/// `flutter_scripts script`
/// A [Command] to exemplify a sub command
/// {@endtemplate}
class ScriptCommand extends Command<int> {
  /// {@macro script_command}
  ScriptCommand({
    Logger? logger,
  }) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'command',
        abbr: 'c',
        help: 'Command to run',
      )
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Path to project',
      );
  }

  @override
  String get description => 'Run a script in a pubspec.yaml file';

  @override
  String get name => 'run';

  final Logger _logger;

  @override
  Future<int> run() async {
    var workingPath = argResults!['path'] as String?;
    // Get script working path
    workingPath ??= Directory.current.path;

    final file = File('$workingPath/pubspec.yaml');
    if (!file.existsSync()) {
      _logger.err('pubspec.yaml not found!');
      return ExitCode.software.code;
    }

    final lines = file.readAsLinesSync();
    final scriptsIdx = lines.indexWhere((line) {
      return line.startsWith('scripts:');
    });
    final commands = <String>[];
    for (var i = scriptsIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith(' ')) break;
      if (line.startsWith(' ')) {
        commands.add(line.trim());
      }
    }
    final commandMap = <String, String>{};
    for (final command in commands) {
      final splitIdx = command.indexOf(':');
      final prefix = command.substring(0, splitIdx);
      final suffix = command.substring(splitIdx + 1);
      if (suffix.isEmpty || prefix.isEmpty) {
        _logger.err('Invalid command: $command');
        return ExitCode.software.code;
      }
      commandMap[prefix.trim()] = suffix.trim();
    }

    if (commands.isEmpty) {
      _logger.err('No commands found!');
      return ExitCode.software.code;
    }

    _logger.info('Found ${commands.length} commands');

    var command = argResults!['command'] as String?;
    if (command == null) {
      _logger.info('Select a command');
      final menu = Menu(commandMap.keys.toList());
      final result = menu.choose();
      command = result.value;
    }

    final script = commandMap[command]!;
    _logger.info('Running: $command -> $script');
    await runCommand(script, workingPath, _logger);

    return ExitCode.success.code;
  }
}

Future<void> runCommand(
  String command,
  String path,
  Logger _logger,
) async {
  final parts = command.split(' ');
  // Run command in process
  final process = await Process.start(
    parts[0],
    parts.length > 1 ? parts.skip(1).toList() : [],
    workingDirectory: path,
  );
  process.stdout.transform(utf8.decoder).listen(_logger.info);
  process.stderr.transform(utf8.decoder).listen(_logger.err);
  await process.exitCode;
}
