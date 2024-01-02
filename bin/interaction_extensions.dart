import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

extension RespondError on InteractiveContext {
  void respondError(String message, {ResponseLevel level = ResponseLevel.public}) =>
      respondEmbed(EmbedBuilder(color: DiscordColor(0xff0000), title: message), level: level);

  Future<void> respondEmbed(EmbedBuilder embed, {ResponseLevel level = ResponseLevel.public}) =>
      respond(MessageBuilder(embeds: [embed]), level: level);
}
