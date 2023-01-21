import 'package:nyxx/nyxx.dart';

const _owlEvent = "owl";
const _frogeEvent = "froge";
const _tlauncherEvent = "tlauncher";

const rule3Text =
    "follow the discord tos and community guidelines \n\n> to be perfectly clear, this also includes cracked minecraft launchers such as tlauncher and the likes. as much as we would like to, we can and will not provide support when you are using one of these ";

final Map<String, int> _cooldowns = {_owlEvent: 0, _frogeEvent: 0, _tlauncherEvent: 0};

void handleOwl(IMessageReceivedEvent event) {
  if (!_checkCooldown(_owlEvent)) return;
  if (!event.message.mentions.any((element) => element.id.id == 527201723677278217)) return;

  final channel = event.message.channel;
  channel.sendMessage(MessageBuilder.embed(EmbedBuilder()
    ..title = "Thou hast poketh the owle"
    ..description = "👉🦉"
    ..imageUrl = "https://media.discordapp.net/attachments/804707289223004194/908718259266781205/owlpoke.gif"
    ..addFooter((footer) => footer.text = "pokey poke")));

  _cooldowns[_owlEvent] = millis();
}

void handleTLauncher(IMessageReceivedEvent event) {
  if (!_checkCooldown(_tlauncherEvent)) return;
  var content = event.message.content.toLowerCase();
  if (!(content.contains(" tlauncher") || content.contains(" t launcher "))) return;

  event.message.channel.sendMessage(MessageBuilder.embed(EmbedBuilder()
    ..title = "friendly reminder about rule #3"
    ..description = rule3Text)
    ..replyBuilder = ReplyBuilder.fromMessage(event.message));
}

bool _checkCooldown(String key) {
  return millis() - (_cooldowns[key] ?? 0) >= 60000;
}

int millis() => DateTime.now().millisecondsSinceEpoch;
