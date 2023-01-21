import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:modrinth_api/modrinth_api.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

import 'announcement_handling.dart' as announcements;
import 'chat_handlers.dart';
import 'command_handlers.dart';
import 'web_data.dart';

final _logger = Logger("bot");
final modrinth = ModrinthApi.createClient("wisp-forest/mittwoch-bot");
final http = Client();

late final INyxxWebsocket bot;
late final Map<String, dynamic> _config;

void main() async {
  final earlyLogging = _logger.onRecord.listen((event) => print("${event.level}: ${event.message}"));

  loadWebData();

  final detailsFile = openConfig("client_details");
  _config = jsonDecode(openConfig("config").readAsStringSync());

  final token = jsonDecode(detailsFile.readAsStringSync())["token"] as String;
  final privilegedGuild = _config["privileged_guild"] as int;

  bot = NyxxFactory.createNyxxWebsocket(token, GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
      options: ClientOptions(
          initialPresence: PresenceBuilder.of(
              status: UserStatus.idle, activity: ActivityBuilder("being a better Mittwoch", ActivityType.competing))
            ..afk = true));

  bot
    ..registerPlugin(Logging())
    ..registerPlugin(CliIntegration())
    ..registerPlugin(IgnoreExceptions())
    ..registerPlugin(CloseHttp())
    ..connect();

  await earlyLogging.cancel();

  final interactions = IInteractions.create(WebsocketInteractionBackend(bot))
    ..registerSlashCommand(SlashCommandBuilder("mittwoch", "Foil", [])..registerHandler(handleMittwochCommand))
    ..registerSlashCommand(SlashCommandBuilder("faq", "Get the URl to a Wisp Forest FAQ entry", [
      CommandOptionBuilder(CommandOptionType.string, "entry", "The entry to query", required: true, autoComplete: true)
        ..autocompleteHandler = autocompleteHandler(faqMappings.keys, "entry")
    ])
      ..registerHandler(handleFaqCommand))
    ..registerSlashCommand(SlashCommandBuilder("announce", "Announces a new mod release", [],
        guild: Snowflake.value(privilegedGuild), requiredPermissions: PermissionsConstants.administrator)
      ..registerHandler(announcements.handleAnnounceCommand))
    ..registerSlashCommand(SlashCommandBuilder("docs", "Get a URL to the specified Wisp Forest docs page", [
      CommandOptionBuilder(CommandOptionType.string, "path", "The page to query", required: true, autoComplete: true)
        ..autocompleteHandler = autocompleteHandler(docEntries, "path")
    ])
      ..registerHandler(handleDocsCommand))
    ..registerSlashCommand(SlashCommandBuilder("truth", "Tells you the truth", [])..registerHandler(handleTruth))
    ..registerSlashCommand(SlashCommandBuilder("lie", "Tells you a lie", [])..registerHandler(handleLie))
    ..events.onModalEvent.listen(announcements.handleAnnounceModal)
    ..events.onButtonEvent.listen(announcements.handlePublishCancel)
    ..events.onButtonEvent.listen(announcements.handleAskForPublish)
    ..events.onButtonEvent.listen(announcements.handlePublishConfirm)
    ..syncOnReady();

  stdin.transform(systemEncoding.decoder).transform(LineSplitter()).listen((event) async {
    if (event == "reset-commands") {
      _logger.warning("Resetting commands");

      await interactions.deleteGlobalCommands();
      _logger.info("Global commands deleted");

      await interactions.deleteGuildCommands([Snowflake.value(privilegedGuild)]);
      _logger.info("Guild commands deleted");

      await interactions.sync();
      _logger.info("Synced successfully");
    }
  });

  bot.eventsWs.onMessageReceived.listen(handleOwl);
  bot.eventsWs.onMessageReceived.listen(handleTLauncher);
}

class CloseHttp extends BasePlugin {
  @override
  FutureOr<void> onBotStop(INyxx nyxx, Logger logger) async => http.close();
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

Map<String, dynamic> getConfig() {
  return _config;
}
