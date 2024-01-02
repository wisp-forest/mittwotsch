import 'dart:math';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

import 'interaction_extensions.dart';
import 'web_data.dart';

final _random = Random();

final _mittwochEmbed = EmbedBuilder()
  ..title = "Es ist Mittwoch meine Kerle"
  ..description = "und Kerlinnen"
  ..image = EmbedImageBuilder(url: Uri.parse("https://i.redd.it/c86uo3xitcoz.jpg"));

final _keinMittwochEmbed = EmbedBuilder()
  ..title = "Es ist leider kein Mittwoch meine Kerle"
  ..description = "und Kerlinnen"
  ..image = EmbedImageBuilder(url: Uri.parse("https://i.imgur.com/EQT3sZ2.png"))
  ..footer = (EmbedFooterBuilder(text: "Zertifiziert Schade™")
    ..iconUrl = Uri.parse("https://cdn.discordapp.com/emojis/819666029638058064.png?v=1"));

Iterable<String> provideFaqEntries(ContextData data) => faqMappings.keys;
Iterable<String> provideDocEntries(ContextData data) => docEntries;
String stringToString(String string) => string;

void registerCommands(CommandsPlugin commands) {
  commands.addCommand(ChatCommand(
    "mittwoch",
    "Foil",
    id("mittwotch", (ChatContext context) {
      if (_random.nextInt(100) < 10) {
        context.respond(MessageBuilder(
            content:
                "https://media.discordapp.net/attachments/884751057933197313/942595066126544906/1642792870874.gif"));
      } else {
        context.respondEmbed(_isWednesday() ? _mittwochEmbed : _keinMittwochEmbed);
      }
    }),
  ));

  commands.addCommand(ChatCommand(
    "truth",
    "Tells you the truth",
    id("truth", (ChatContext context) {
      context.respond(MessageBuilder(content: "Bow before the destroyer of your saviour, Mittwotsch on 🎯"));
    }),
  ));

  commands.addCommand(ChatCommand(
    "lie",
    "Tells you a lie",
    id("lie", (ChatContext context) {
      context.respond(MessageBuilder(content: _isWednesday() ? "it's not wednesday" : "it's wednesday"));
    }),
  ));

  // ---

  const Converter<String> faqConverter = SimpleConverter(provider: provideFaqEntries, stringify: stringToString);
  commands.addCommand(ChatCommand(
    "faq",
    "Get the URl to a Wisp Forest FAQ entry",
    id("faq", (ChatContext context, @UseConverter(faqConverter) @Description("The entry to query") String entry) {
      final requestedEntry = faqMappings[entry]!;

      context.respondEmbed(EmbedBuilder()
        ..title = "Wisp Forest FAQ"
        ..color = DiscordColor(0x4051b5)
        ..description = "[${requestedEntry.title}](${requestedEntry.url})");
    }),
  ));

  // ---

  const Converter<String> docsConverter = SimpleConverter(provider: provideDocEntries, stringify: stringToString);
  commands.addCommand(ChatCommand(
    "docs",
    "Get a URL to the specified Wisp Forest docs page",
    id("docs", (ChatContext context, @UseConverter(docsConverter) @Description("The page to query") String path) {
      context.respond(MessageBuilder()..content = "https://docs.wispforest.io/${path.replaceAll(".", "/")}/");
    }),
  ));
}

bool _isWednesday() {
  return DateTime.now().weekday == DateTime.wednesday;
}
