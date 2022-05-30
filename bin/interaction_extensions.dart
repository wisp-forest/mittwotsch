import 'package:nyxx/nyxx.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

extension RespondError on IInteractionEventWithAcknowledge {
  void respondError(String message, {bool followup = false}) {
    (followup ? sendFollowup : respond)(MessageBuilder.embed(EmbedBuilder()
      ..color = DiscordColor.red
      ..title = message));
  }

  Future<void> respondEmbed(EmbedBuilder embed) {
    return respond(MessageBuilder.embed(embed));
  }
}

extension ById<T extends IMessageTextInput> on Iterable<T> {
  T byName(String customId) {
    return firstWhere((element) => element.customId == customId);
  }
}

extension GetArgs on ISlashCommandInteractionEvent {
  T? getOption<T>(String name) {
    return args.firstWhereSafe((element) => element.name == name, orElse: () => null)?.value as T?;
  }
}
