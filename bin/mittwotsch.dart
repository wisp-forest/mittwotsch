import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:modrinth_api/modrinth_api.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

import 'announcement_handling.dart';
import 'chat_handlers.dart';
import 'command_handlers.dart';
import 'web_data.dart';

final _logger = Logger("bot");
final modrinth = ModrinthApi.createClient("wisp-forest/mittwoch-bot");
final http = Client();

late final NyxxGateway bot;
late final Map<String, dynamic> _config;

void main() async {
  final earlyLogging = _logger.onRecord.listen((event) => print("${event.level}: ${event.message}"));

  loadWebData();

  final detailsFile = openConfig("client_details");
  _config = jsonDecode(openConfig("config").readAsStringSync());

  final token = jsonDecode(detailsFile.readAsStringSync())["token"] as String;

  final commands = CommandsPlugin(prefix: null, options: CommandsOptions(type: CommandType.slashOnly));
  registerCommands(commands);
  registerAnnouncementCommand(commands);

  bot = await Nyxx.connectGatewayWithOptions(
    GatewayApiOptions(
      token: token,
      intents: GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
      initialPresence: PresenceBuilder(
        isAfk: true,
        status: CurrentUserStatus.idle,
        activities: [ActivityBuilder(name: "being a better Mittwoch", type: ActivityType.competing)],
      ),
    ),
    GatewayClientOptions(plugins: [
      logging,
      // cliIntegration,
      ignoreExceptions,
      ShutdownHook(),
      commands,
    ]),
  );

  await earlyLogging.cancel();

  bot.onMessageCreate.listen(handleOwl);
  bot.onMessageCreate.listen(handleTLauncher);
}

class ShutdownHook extends NyxxPlugin {
  @override
  Future<void> doClose(Nyxx client, Future<void> Function() close) async {
    super.doClose(client, close);

    http.close();
    modrinth.dispose();
  }
}

File openConfig(String filename) {
  filename = "config/$filename.json";

  final file = File(filename);
  if (!file.existsSync()) {
    _logger.shout("Missing config file $filename");
    exit(1);
  }
  return file;
}

Map<String, dynamic> get botConfig => _config;
