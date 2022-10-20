import 'dart:math';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

import 'interaction_extensions.dart';
import 'web_data.dart';

final _random = Random();

final _mittwochEmbed = EmbedBuilder()
  ..title = "Es ist Mittwoch meine Kerle"
  ..description = "und Kerlinnen"
  ..imageUrl = "https://i.redd.it/c86uo3xitcoz.jpg";

final _keinMittwochEmbed = EmbedBuilder()
  ..title = "Es ist leider kein Mittwoch meine Kerle"
  ..description = "und Kerlinnen"
  ..imageUrl = "https://i.imgur.com/EQT3sZ2.png"
  ..footer = (EmbedFooterBuilder()
    ..text = "Zertifiziert Schade™"
    ..iconUrl = "https://cdn.discordapp.com/emojis/819666029638058064.png?v=1");

void handleMittwochCommand(ISlashCommandInteractionEvent event) {
  if (_random.nextInt(100) < 10) {
    event.respond(MessageBuilder.content(
        "https://media.discordapp.net/attachments/884751057933197313/942595066126544906/1642792870874.gif"));
  } else {
    event.respondEmbed(_isWednesday() ? _mittwochEmbed : _keinMittwochEmbed);
  }
}

void handleDocsCommand(ISlashCommandInteractionEvent event) {
  final path = event.getOption<String>("path")!.replaceAll(".", "/");
  event.respond(MessageBuilder()..content = "https://docs.wispforest.io/$path/");
}

void handleFaqCommand(ISlashCommandInteractionEvent event) {
  final requestedEntry = event.getArg("entry").value as String;

  if (faqMappings.containsKey(requestedEntry)) {
    final faqEntry = faqMappings[requestedEntry]!;

    event.respondEmbed(EmbedBuilder()
      ..title = "Wisp Forest FAQ"
      ..color = DiscordColor.fromInt(0x4051b5)
      ..description = "[${faqEntry.title}](${faqEntry.url})");
  } else {
    event.respondError("Unknown FAQ entry");
  }
}

void handleTruth(ISlashCommandInteractionEvent event) {
  event.respond(MessageBuilder()..content = "Bow before the destroyer of your saviour, Mittwotsch on 🎯");
}

void handleLie(ISlashCommandInteractionEvent event) {
  event.respond(MessageBuilder()..content = _isWednesday() ? "it's not wednesday" : "it's wednesday");
}

void Function(IAutocompleteInteractionEvent event) autocompleteHandler(Iterable<String> candidates, String option) {
  return (event) {
    if (event.focusedOption.name == option) {
      event.respond(_suggestMatching(candidates, event.focusedOption.value));
    } else {
      event.respond([]);
    }
  };
}

List<ArgChoiceBuilder> _suggestMatching(Iterable<String> candidates, String input) {
  var choices = candidates.where((element) => element.contains(input)).map((e) => ArgChoiceBuilder(e, e)).toList();

  if (choices.length > 25) {
    return [for (int i = 0; i < 25; i++) choices[i]];
  } else {
    return choices;
  }
}

bool _isWednesday() {
  return DateTime.now().weekday == DateTime.wednesday;
}
